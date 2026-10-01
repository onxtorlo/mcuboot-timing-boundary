#!/bin/bash
# exp1_boundary_scan.sh — 실험 1: 1단계 컷(FAST) ↔ 2단계 진입(SLOW) 전이 지점을 이진탐색으로 특정
#
# 사용법: ./exp1_boundary_scan.sh
# 결과: 콘솔 출력 + boundary_scan_log_<YYYYmmdd_HHMMSS>.csv (스크립트와 같은 폴더)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || {
  echo "[ERROR] common.sh를 불러오지 못함: $SCRIPT_DIR/common.sh" >&2
  exit 1
}
if [ ! -f "$SLOT0_ORIG" ]; then
  echo "[ERROR] 원본 이미지 없음: $SLOT0_ORIG" >&2
  exit 1
fi

LOG_CSV="$SCRIPT_DIR/boundary_scan_log_$(date +%Y%m%d_%H%M%S).csv"
echo "step,img_size_hex,elapsed_ms,classification" > "$LOG_CSV"

# 재보정 검증(2026-09-20, 각 값 2회 반복 재확인, 일관됨):
#   0x1000   → FAST (50~51ms)
#   0x3c6f   → FAST (102ms)   * 중간에 한 번 SLOW(~680ms)로 나온 적이 있었으나
#                                 이후 3회 연속 FAST로 재현되어 그게 오탐(당시
#                                 usbip 재attach 직후 불안정한 상태에서 생긴
#                                 잔여 버퍼 잡음)이었던 것으로 결론. FAST 확정.
#   0xbfdff  → SLOW (710~719ms)
#   0x100000 → FAST (50~51ms, 슬롯 용량 0xC0000 초과라 별도의 상단 경계로 즉시 거부)
# 원본 유효 크기(slot0_orig.bin)는 0x3c6e(15470).
# 결론: 원래 노트의 LOW/HIGH 설정이 맞았음 — 그대로 유지.
LOW=0x3c6f      # 케이스 B: FAST 확인됨
HIGH=0xbfdff    # 케이스 C: SLOW 확인됨
THEORY=$((0xC0000 - 0x20))   # 슬롯크기 - hdr_size = 상단(용량) 경계 이론값
                              # 참고용: 0xbfdff(SLOW)~0x100000(FAST) 사이에 있는
                              # "다른" 경계이며, 이번 하단 경계 탐색의 정답과는 별개.

echo "=== 실험 1: 경계 이진탐색 시작 ==="
echo "탐색 범위: $LOW (FAST 확인됨) ~ $HIGH (SLOW 확인됨)"
printf "참고 - 상단(용량) 경계 이론값(이번 탐색 대상 아님): 0x%x\n" "$THEORY"
echo

ZOMBIE_CHECK_EVERY=5   # 매 N스텝마다 -104 버스트 체크
MAX_CONSECUTIVE_FAILS=3   # 응답 없음/쓰기 실패가 연속 N회면 스캔 중단

step=0
fail_count=0
low_dec=$((LOW))
high_dec=$((HIGH))

while [ $((high_dec - low_dec)) -gt 1 ]; do
  step=$((step+1))
  mid_dec=$(( (low_dec + high_dec) / 2 ))
  mid_hex=$(printf '0x%x' "$mid_dec")

  echo -n "[step $step] 시도값=$mid_hex ... "
  set_img_size "$mid_hex"
  result=$(flash_and_measure)
  elapsed=$(echo "$result" | awk '{print $1}')
  cls=$(echo "$result" | awk '{print $2}')
  echo "${elapsed}ms → $cls"
  echo "$step,$mid_hex,$elapsed,$cls" >> "$LOG_CSV"

  if [ $((step % ZOMBIE_CHECK_EVERY)) -eq 0 ]; then
    zombie_checkpoint "$step"
  fi

  case "$cls" in
    FAST)
      low_dec=$mid_dec   # 여전히 1단계 컷 → 경계는 더 위쪽
      fail_count=0
      ;;
    SLOW)
      high_dec=$mid_dec  # 2단계까지 진입 → 경계는 더 아래쪽
      fail_count=0
      ;;
    *)
      # NONE / WRITE_FAILED / 예상하지 못한 출력
      fail_count=$((fail_count+1))
      echo "  [WARN] 응답 없음/쓰기 실패(${cls:-빈 결과}), 재시도 (${fail_count}/${MAX_CONSECUTIVE_FAILS})"
      if [ "$fail_count" -ge "$MAX_CONSECUTIVE_FAILS" ]; then
        echo "  [ERROR] 연속 ${MAX_CONSECUTIVE_FAILS}회 실패로 스캔 중단. 보드 연결과 /dev/ttyACM0 상태를 확인하세요." >&2
        echo "  지금까지의 로그: $LOG_CSV" >&2
        exit 1
      fi
      step=$((step-1))
      ;;
  esac
done

boundary_hex=$(printf '0x%x' "$low_dec")
slow_hex=$(printf '0x%x' "$high_dec")
echo
echo "=== 결과 ==="
echo "실측 경계: FAST 쪽 마지막 값=$boundary_hex, SLOW 쪽 첫 값=$slow_hex"
echo "(원본 유효 크기 0x3c6e 기준으로 이 값이 무엇을 의미하는지는 본문에서 분석 필요)"
echo "상세 로그: $LOG_CSV"
