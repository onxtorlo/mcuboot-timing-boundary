#!/usr/bin/env python3
"""hr_capture.py — 폴링 없는 고해상도 UART 캡처.
select()로 데이터가 도착하는 즉시 깨어나 청크별 도착 시각을 기록한다(폴링 주기에 의한 올림 없음).
원점은 bash 측정(common.sh)과 동일하게 'st-flash reset 명령 반환 직후'.
출력(JSON 1줄): t_first_ms, t_last_ms, nbytes, chunks=[[t_ms, nbytes], ...], text(앞 200자)
사용: hr_capture.py [capture_s=3]   (플래시 기록은 호출 전에 끝나 있어야 함)
"""
import os, sys, time, select, json, subprocess, termios

cap = float(sys.argv[1]) if len(sys.argv) > 1 else 3.0
subprocess.run(["stty", "-F", "/dev/ttyACM0", "115200", "raw", "-echo"], check=False)
fd = os.open("/dev/ttyACM0", os.O_RDONLY | os.O_NOCTTY | os.O_NONBLOCK)
termios.tcflush(fd, termios.TCIFLUSH)
subprocess.run(["st-flash", "--connect-under-reset", "reset"],
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
t0 = time.monotonic()
chunks, buf = [], b""
deadline = t0 + cap
while True:
    rem = deadline - time.monotonic()
    if rem <= 0:
        break
    r, _, _ = select.select([fd], [], [], rem)
    if r:
        try:
            d = os.read(fd, 4096)
        except BlockingIOError:
            continue
        t = time.monotonic()
        if d:
            chunks.append([round((t - t0) * 1000, 3), len(d)])
            buf += d
os.close(fd)
out = {"t_first_ms": chunks[0][0] if chunks else None,
       "t_last_ms": chunks[-1][0] if chunks else None,
       "nbytes": len(buf), "chunks": chunks,
       "text": buf[:200].decode(errors="replace")}
print(json.dumps(out, ensure_ascii=False))
