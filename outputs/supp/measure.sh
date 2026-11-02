#!/bin/bash
# measure.sh — common.sh의 flash_and_measure와 동일하되 폴링 주기 T(초)를 인자로 받음
# 사용: source measure.sh; set_img_size <hex|dec>; measure_T <T초>  -> "elapsed_ms CLASS"
SUPP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SUPP_DIR/../common.sh"
# 플래시 방식: 헤더가 있는 첫 128KB 섹터(sector 5)만 재기록. img_size 필드만 바뀌므로 slot0 나머지가
# slot0_orig와 같다는 전제에서 최종 플래시 내용은 전체 쓰기와 동일 (restore_slot0로 전제 보장).
SLOT0_SECTOR="/tmp/slot0_sector.bin"
restore_slot0() { st-flash --connect-under-reset write "$SLOT0_ORIG" "$FLASH_ADDR" >/dev/null 2>&1; }
write_header_sector() {
  head -c 131072 "$SLOT0_TEST" > "$SLOT0_SECTOR"
  st-flash --connect-under-reset write "$SLOT0_SECTOR" "$FLASH_ADDR" >/dev/null 2>&1
}
measure_T() {
  local T="$1"
  write_header_sector || { echo "0 WRITE_FAILED"; return 1; }
  stty -F /dev/ttyACM0 115200 raw -echo 2>/dev/null
  local start_us elapsed_ms last_byte_us got_byte chunk
  exec 3< /dev/ttyACM0
  trap "exec 3<&- 2>/dev/null" RETURN
  st-flash --connect-under-reset reset >/dev/null 2>&1
  start_us=$(_now_us)
  got_byte=0; last_byte_us=$start_us
  local deadline_s=$((SECONDS + CAPTURE_TIMEOUT_S))
  while [ "$SECONDS" -lt "$deadline_s" ]; do
    IFS= read -r -N 4096 -t "$T" -u 3 chunk
    if [ -n "$chunk" ]; then got_byte=1; last_byte_us=$(_now_us); fi
  done
  elapsed_ms=$(( (last_byte_us - start_us) / 1000 ))
  [ "$got_byte" -eq 0 ] && { echo "0 NONE"; return 2; }
  if [ "$elapsed_ms" -lt "$FAST_THRESHOLD_MS" ]; then echo "$elapsed_ms FAST"; else echo "$elapsed_ms SLOW"; fi
}

# measure_T2: measure_T와 같은 측정 + 수신 바이트 수 기록 (2026-10-05 S4R부터 사용)
# 출력: "elapsed_ms CLASS nbytes"
measure_T2() {
  local T="$1"
  write_header_sector || { echo "0 WRITE_FAILED 0"; return 1; }
  stty -F /dev/ttyACM0 115200 raw -echo 2>/dev/null
  local start_us elapsed_ms last_byte_us got_byte chunk nb=0
  local LC_ALL=C
  exec 3< /dev/ttyACM0
  trap "exec 3<&- 2>/dev/null" RETURN
  st-flash --connect-under-reset reset >/dev/null 2>&1
  start_us=$(_now_us)
  got_byte=0; last_byte_us=$start_us
  local deadline_s=$((SECONDS + CAPTURE_TIMEOUT_S))
  while [ "$SECONDS" -lt "$deadline_s" ]; do
    IFS= read -r -N 4096 -t "$T" -u 3 chunk
    if [ -n "$chunk" ]; then got_byte=1; last_byte_us=$(_now_us); nb=$((nb + ${#chunk})); fi
  done
  elapsed_ms=$(( (last_byte_us - start_us) / 1000 ))
  [ "$got_byte" -eq 0 ] && { echo "0 NONE 0"; return 2; }
  if [ "$elapsed_ms" -lt "$FAST_THRESHOLD_MS" ]; then echo "$elapsed_ms FAST $nb"; else echo "$elapsed_ms SLOW $nb"; fi
}
