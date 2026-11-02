#!/bin/bash
# run_session.sh <session> <real_pair_spec...>
# 세션 재시작 직후 실행: (1) 고해상도 기준 측정 (2) T=0.05 이진탐색 2회 (3) 점검(허위 2쌍 + 지정 실제 쌍) (4) 시계열 20회
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib_supp.sh"
sess=$1; shift
out="$DATA_DIR/hr_${sess}.csv"
echo "session,img_size,rep,t_first,t_last,nbytes" > "$out"
for rep in 1 2 3 4 5 6 7 8; do for s in 60000 76628 785920; do
  set_img_size $s; r=$(hr_once); echo "$sess,$s,$rep,${r// /,}" >> "$out"
done; done
echo "HR_DONE $sess $(date +%T)"
specs=()
for k in 1 2; do
  r=$(scan_once "${sess}_$k" 0.05) || { echo "SCAN_ABORT ${sess}_$k"; exit 1; }
  echo "scan ${sess}_$k -> $r $(date +%T)"
  lo=${r% *}; hi=${r#* }
  specs+=("F_${sess}_$k:$hi:$lo")
done
"$SCRIPT_DIR/check_pairs.sh" "$sess" "${specs[@]}" "$@"
"$SCRIPT_DIR/timeseries.sh" "$sess" 72000 20
echo "SESSION_DONE $sess $(date +%T)"
