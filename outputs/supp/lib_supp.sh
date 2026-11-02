#!/bin/bash
# lib_supp.sh — 보충 실험(2026-10) 공통 함수. measure.sh(섹터 쓰기 + 폴링 주기 T 인자) 위에 구성.
SUPP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SUPP_DIR/measure.sh"
DATA_DIR="$SUPP_DIR/data"
mkdir -p "$DATA_DIR"

# 측정 실패(NONE/WRITE_FAILED) 시 최대 3회 재시도. stdout: "elapsed_ms CLASS"
measure_retry() {
  local T="$1" r i
  for i in 1 2 3; do
    r=$(measure_T "$T")
    case "$r" in *FAST|*SLOW) echo "$r"; return 0;; esac
    echo "  [WARN] $r (재시도 $i)" >&2
    sleep 2
  done
  echo "$r"; return 1
}

# 고해상도 캡처 1회: set_img_size 후 호출. stdout: "t_first t_last nbytes"
hr_once() {
  write_header_sector || { echo "NA NA 0"; return 1; }
  python3 "$SUPP_DIR/hr_capture.py" 3 | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["t_first_ms"], d["t_last_ms"], d["nbytes"])'
}

# 원 스캔(exp1_boundary_scan.sh)과 같은 이진탐색. 인자: 태그, T(초), [임계값 ms=150]
# 결과 CSV: data/scan_<tag>.csv, stdout 마지막 줄: "<low> <high>"
scan_once() {
  local tag="$1" T="$2" thr="${3:-150}"
  local csv="$DATA_DIR/scan_${tag}.csv"
  echo "step,img_size,elapsed_ms,class,zombie" > "$csv"
  local low=$((0x3c6f)) high=$((0xbfdff)) step=0 mid r e c z
  local old_thr=$FAST_THRESHOLD_MS; FAST_THRESHOLD_MS=$thr
  while [ $((high - low)) -gt 1 ]; do
    step=$((step+1)); mid=$(( (low + high) / 2 ))
    set_img_size "$mid"
    r=$(measure_retry "$T") || { echo "SCAN_ABORT $tag step $step" >&2; FAST_THRESHOLD_MS=$old_thr; return 1; }
    e=${r% *}; c=${r#* }
    z=0; is_serial_zombie && z=1
    echo "$step,$mid,$e,$c,$z" >> "$csv"
    if [ "$c" = FAST ]; then low=$mid; else high=$mid; fi
  done
  FAST_THRESHOLD_MS=$old_thr
  echo "$low $high"
}
