#!/bin/bash
# common.sh — 공통 함수: 헤더 조작, 시리얼 복구, 타이밍 측정
# source 해서 사용: source "$(dirname "${BASH_SOURCE[0]}")/common.sh"  (같은 폴더의 스크립트에서)

set -uo pipefail

OUTPUTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLOT0_ORIG="$OUTPUTS_DIR/slot0_orig.bin"
SLOT0_TEST="$OUTPUTS_DIR/slot0_test.bin"
FLASH_ADDR="0x08020000"
IMG_SIZE_OFFSET=12          # +0x0C
FAST_THRESHOLD_MS=150       # 이보다 빠르면 1단계 컷으로 판정 (재측정 B 약 53ms, C 약 650ms 사이)
CAPTURE_TIMEOUT_S=3         # 응답 대기 최대 시간

# ---- 시리얼 좀비 상태 자동 복구 -------------------------------------------
recover_serial() {
  local iface
  iface=$(readlink -f /sys/class/tty/ttyACM0/device 2>/dev/null | grep -oE '[0-9]+-[0-9.]+:[0-9.]+$')
  if [ -z "$iface" ]; then
    echo "  [WARN] ttyACM0 인터페이스 경로를 못 찾음, 기본값 1-1:1.2 시도" >&2
    iface="1-1:1.2"
  fi
  echo -n "$iface" | sudo tee /sys/bus/usb/drivers/cdc_acm/unbind >/dev/null 2>&1
  sleep 1
  echo -n "$iface" | sudo tee /sys/bus/usb/drivers/cdc_acm/bind >/dev/null 2>&1
  sleep 1
  stty -F /dev/ttyACM0 115200 raw -echo 2>/dev/null
}

# 최근 dmesg에 -104(ECONNRESET)가 "몰려서" 쌓이고 있는지 확인
# 주의: 포트를 정상적으로 닫을 때도 -104가 1~수개 찍히는 것은 정상 부산물임.
# (exec 3<&- 로 fd를 닫아도 vhci_hcd가 진행 중 URB를 unlink하며 -104를 남김)
# 따라서 "존재 여부"가 아니라 "최근 dmesg 꼬리 안에서의 발생 빈도"로 판정한다.
ZOMBIE_BURST_THRESHOLD=15   # 최근 50줄 안에 이 개수 이상이면 진짜 좀비 큐로 판정

is_serial_zombie() {
  local count
  count=$(dmesg | tail -50 | grep -c "urb->status -104")
  [ "$count" -ge "$ZOMBIE_BURST_THRESHOLD" ]
}

# 스캔 도중 N스텝마다 호출: 좀비 감지 시 사람에게 복구를 요청하고,
# 콘솔에서 Enter를 누르면 계속 진행 (완전 중단이 아니라 "일시정지")
zombie_checkpoint() {
  local step_no="$1"
  if is_serial_zombie; then
    echo
    echo "  [!!!] step ${step_no}: vhci_hcd -104 버스트 감지 (최근 50줄 중 임계치 ${ZOMBIE_BURST_THRESHOLD} 이상)" >&2
    echo "  [!!!] Windows 쪽에서 아래 절차를 진행해 주세요:" >&2
    echo "        1) usbipd detach --busid <ST-Link busid>" >&2
    echo "        2) wsl --shutdown" >&2
    echo "        3) wsl -e true   (distro 재기동)" >&2
    echo "        4) usbipd attach --wsl --busid <ST-Link busid>" >&2
    echo "  [!!!] 완료 후 이 터미널에서 Enter를 누르면 스캔을 계속합니다." >&2
    read -r -p "  >>> 복구 완료 후 Enter: " _
    echo "  [체크포인트] 재개합니다." >&2
  fi
}

# ---- 헤더 img_size 필드 조작 ----------------------------------------------
# set_img_size <hex_value>   예: set_img_size 0x3c6e
set_img_size() {
  local hexval="$1"
  cp "$SLOT0_ORIG" "$SLOT0_TEST"
  # little-endian 4바이트로 변환해서 offset 12에 기록
  printf '%08x' "$hexval" | \
    sed -E 's/(..)(..)(..)(..)/\4\3\2\1/' | \
    xxd -r -p | \
    dd of="$SLOT0_TEST" bs=1 seek=$IMG_SIZE_OFFSET conv=notrunc 2>/dev/null
}

# bash 5+ 내장 EPOCHREALTIME(마이크로초 정밀도, 서브프로세스 無)을 정수 us로 변환.
# 주의: 루프 안에서 `date +%s%N`을 쓰면 매 바이트마다 프로세스를 fork/exec하게 되어
# 수백 바이트짜리 부트로그를 드레인하는 동안 지연이 누적됨(실측: 17ms짜리 케이스가
# 878ms로 부풀려짐). EPOCHREALTIME은 순수 bash 내장 변수라 이 오버헤드가 없다.
_now_us() {
  local t=$EPOCHREALTIME
  echo "${t/./}"
}

# ---- 플래시 쓰기 + 리셋 + 타이밍 측정 -------------------------------------
# flash_and_measure  →  stdout으로 "elapsed_ms classification" 출력
# classification: FAST(1단계 컷 추정) / SLOW(2단계 진입 추정) / NONE(응답 없음)
#
# 리팩터링 이력:
#  v1(원본): head -c1로 매번 포트 재open → vhci 좀비 큐 유발.
#  v2: exec 3< 로 fd 한 번만 열고 read -n1(1바이트)씩 읽음 → read 1회당
#      ~0.5ms 오버헤드가 있어서, 출력이 긴 케이스일수록 드레인 지연이 누적되어
#      실제 타이밍보다 크게 부풀려짐(실측: 17ms 케이스가 878ms로 나옴).
#  v3(현재): 큰 청크(-N 4096, -t 0.05)로 한 번에 읽어 read 호출 횟수를 줄이고,
#      "250ms 조용하면 조기 종료" 로직을 제거해 CAPTURE_TIMEOUT_S 전체를 읻는다.
#      (MCUboot 내부 검증 연산 중 650ms대 무음 구간이 있어서 조기 종료 시
#      SLOW 케이스의 마지막 응답을 놓치는 문제가 있었음.)
flash_and_measure() {
  st-flash --connect-under-reset write "$SLOT0_TEST" "$FLASH_ADDR" >/dev/null 2>&1 || {
    echo "0 WRITE_FAILED"
    return 1
  }

  stty -F /dev/ttyACM0 115200 raw -echo 2>/dev/null

  local start_us elapsed_ms last_byte_us got_byte chunk

  # fd 3으로 포트를 한 번만 open. 함수를 어떤 경로로 빠져나가든 close 보장.
  exec 3< /dev/ttyACM0
  trap 'exec 3<&- 2>/dev/null' RETURN

  st-flash --connect-under-reset reset >/dev/null 2>&1
  start_us=$(_now_us)

  got_byte=0
  last_byte_us=$start_us
  local deadline_s=$((SECONDS + CAPTURE_TIMEOUT_S))   # 서브프로세스 없는 초 단위 전체 상한

  while [ "$SECONDS" -lt "$deadline_s" ]; do
    IFS= read -r -N 4096 -t 0.05 -u 3 chunk
    if [ -n "$chunk" ]; then
      got_byte=1
      last_byte_us=$(_now_us)
    fi
  done

  # exec 3<&- 는 trap에서 실행됨 (RETURN 트랩)

  elapsed_ms=$(( (last_byte_us - start_us) / 1000 ))

  if [ "$got_byte" -eq 0 ]; then
    echo "0 NONE"
    return 2
  fi

  if [ "$elapsed_ms" -lt "$FAST_THRESHOLD_MS" ]; then
    echo "$elapsed_ms FAST"
  else
    echo "$elapsed_ms SLOW"
  fi
}
