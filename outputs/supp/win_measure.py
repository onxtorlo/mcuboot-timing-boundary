#!/usr/bin/env python3
"""win_measure.py — Windows 네이티브 경로(WSL2/USB-IP 미사용) 측정.
ST-Link를 Windows에 직접 연결한 상태(usbipd detach)에서 pyocd로 헤더 섹터 기록·nRESET 리셋,
pyserial로 COM 포트 수신. 측정 정의는 WSL 측(measure.sh / hr_capture.py)과 같게 맞춘다.
  - 원점: 리셋 해제(nRESET deassert) 반환 직후 (WSL: st-flash reset 반환 직후)
  - poll 모드: read(4096)를 타임아웃 T로 반복, 데이터를 받은 read의 반환 시각 = 응답 시간 (bash read -N 4096 -t T 대응)
  - hr 모드: 0.5ms 간격으로 수신 대기 바이트를 확인해 청크별 도착 시각 기록 (폴링 격자 없음)
구현 메모(2026-10-05 시험에서 확인):
  - pyocd target.reset()은 부팅 출력이 끝난 뒤 반환 -> 원점 불가. probe.assert_reset으로 직접 nRESET 조작.
  - 측정 중 pyocd 세션이 열려 있거나 Windows 수신 버퍼가 기본값이면 UART 바이트가 빠짐(391B 중 130~240B 수신)
    -> 기록 후 세션을 닫고, set_buffer_size(rx=64KB) 사용. 이 조건에서 391B 전량 수신 확인.
  - 실행 중(PLL 168MHz) 상태에서 flash algo init 시간 초과 -> reset_and_halt 후 기록.
사용:
  win_measure.py hr    <out.csv> <tag> <reps> <size1,size2,...>
  win_measure.py check <out.csv> <tag> <pair_id:a:b> [...]
  win_measure.py scan  <out.csv> <tag> <T> [thr=150]
"""
import sys, time, struct, csv, os, json, io, ctypes
import serial
from pyocd.core.helpers import ConnectHelper
from pyocd.core.session import Session
from pyocd.flash.file_programmer import FileProgrammer
from pyocd.probe.aggregator import DebugProbeAggregator

ctypes.windll.winmm.timeBeginPeriod(1)  # Windows 타이머 해상도 1ms (기본 15.6ms면 T=5ms 폴링 불가)

HERE = os.path.dirname(os.path.abspath(__file__))
SLOT0_ORIG = os.path.join(HERE, "..", "slot0_orig.bin")
FLASH_ADDR = 0x08020000
SECTOR = 131072
PORT = "COM5"
CAP_S = 3.0
MIN_BYTES = 391

orig = open(SLOT0_ORIG, "rb").read()
ser = serial.Serial(PORT, 115200, timeout=0)
ser.set_buffer_size(rx_size=65536, tx_size=4096)


def write_header_sector(size):
    img = bytearray(orig[:SECTOR])
    img[12:16] = struct.pack("<I", size)
    with ConnectHelper.session_with_chosen_probe(target_override="stm32f429xi",
                                                 options={"connect_mode": "under-reset"}) as session:
        target = session.board.target
        target.reset_and_halt()
        FileProgrammer(session, progress=None).program(io.BytesIO(bytes(img)), file_format="bin",
                                                       base_address=FLASH_ADDR)
        target.set_vector_catch(0)
    time.sleep(1.0)  # 세션 종료 시 재개된 부팅 출력이 끝날 때까지 대기 (785,919B 해시 약 0.7s)


def reset_and_capture(T=None):
    p = DebugProbeAggregator.get_all_connected_probes()[0]
    Session(p, target_override="stm32f429xi")
    p.open()
    ser.timeout = 0 if T is None else T  # 루프 밖에서 한 번만 설정 (루프 안 재설정은 포트 재구성으로 바이트 유실, S5 1차 확인)
    ser.reset_input_buffer()
    p.assert_reset(True)
    time.sleep(0.005)
    p.assert_reset(False)
    t0 = time.perf_counter()
    p.close()  # 측정 중 ST-Link 디버그 측 활동 없음
    chunks, buf = [], b""
    while True:
        now = time.perf_counter()
        if now - t0 >= CAP_S:
            break
        if T is None:
            n = ser.in_waiting
            if n:
                d = ser.read(n)
            else:
                time.sleep(0.0005)
                continue
        else:
            d = ser.read(4096)
        if d:
            chunks.append((round((time.perf_counter() - t0) * 1000, 3), len(d)))
            buf += d
    return chunks, buf


def poll_value(size, T, thr=150):
    write_header_sector(size)
    ch, buf = reset_and_capture(T)
    if not ch:
        return 0, "NONE", 0
    e = int(ch[-1][0])
    return e, ("FAST" if e < thr else "SLOW"), len(buf)


mode = sys.argv[1]
path = sys.argv[2]
new = not os.path.exists(path)
out = open(path, "a", newline="")
w = csv.writer(out)
tag = sys.argv[3]
if mode == "hr":
    if new:
        w.writerow(["session", "img_size", "rep", "t_first", "t_last", "nbytes"])
    reps, sizes = int(sys.argv[4]), [int(x) for x in sys.argv[5].split(",")]
    for r in range(1, reps + 1):
        for s in sizes:
            write_header_sector(s)
            ch, buf = reset_and_capture(None)
            with open(path + ".jsonl", "a", encoding="utf-8") as jf:
                jf.write(json.dumps({"tag": tag, "size": s, "rep": r, "wall": time.time(), "chunks": ch,
                                     "text": buf.decode(errors="replace")}, ensure_ascii=False) + "\n")
            w.writerow([tag, s, r, ch[0][0] if ch else "NA", ch[-1][0] if ch else "NA", len(buf)])
            out.flush()
elif mode == "check":
    # check_pairs2.sh와 같은 절차/형식/무효 기준
    if new:
        w.writerow(["session", "pair_id", "T", "rep", "img_size", "elapsed_ms", "class", "nbytes", "valid"])
    for spec in sys.argv[4:]:
        pid, a, b = spec.split(":"); a, b = int(a), int(b)
        for T in (0.005, 0.02, 0.05, 0.1, 0.2):
            for rep in (1, 2):
                for s in ((a, b) if rep == 1 else (b, a)):
                    for _ in range(4):
                        e, c, n = poll_value(s, T)
                        v = 0 if (e < 0 or e > 3000 or n < MIN_BYTES) else 1
                        w.writerow([tag, pid, T, rep, s, e, c, n, v]); out.flush()
                        if v:
                            break
        print("checked", pid, time.strftime("%H:%M:%S"), flush=True)
elif mode == "scan":
    if new:
        w.writerow(["session", "step", "img_size", "elapsed_ms", "class", "nbytes"])
    T = float(sys.argv[4]); thr = int(sys.argv[5]) if len(sys.argv) > 5 else 150
    low, high, step = 0x3c6f, 0xbfdff, 0
    while high - low > 1:
        mid = (low + high) // 2
        e, c, n = poll_value(mid, T, thr)
        if c == "NONE" or n < MIN_BYTES:
            w.writerow([tag, step, mid, e, c, n]); out.flush()
            continue  # 무효 표본은 기록 후 같은 값 재측정
        step += 1
        w.writerow([tag, step, mid, e, c, n]); out.flush()
        if c == "FAST":
            low = mid
        else:
            high = mid
    print("scan", tag, low, high, time.strftime("%H:%M:%S"), flush=True)
ser.close()
