#!/bin/bash
# check_pairs.sh — 해상도 불변성 점검(논문 2.2절 절차): 각 후보 쌍 (a,b)를 T=5,20,50,100,200ms에서 2회씩 측정.
# 사용: check_pairs.sh <session> <pair_id:a:b> [<pair_id:a:b> ...]
# 결과: data/check_<session>.csv (session,pair_id,T,rep,img_size,elapsed_ms,class)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib_supp.sh"
sess="$1"; shift
out="$DATA_DIR/check_${sess}.csv"
[ -f "$out" ] || echo "session,pair_id,T,rep,img_size,elapsed_ms,class" > "$out"
for spec in "$@"; do
  IFS=: read -r pid a b <<< "$spec"
  for T in 0.005 0.02 0.05 0.1 0.2; do
    for rep in 1 2; do
      # 순서 교대(a,b / b,a)로 드리프트 상쇄
      if [ "$rep" -eq 1 ]; then order="$a $b"; else order="$b $a"; fi
      for s in $order; do
        set_img_size "$s"
        r=$(measure_retry "$T")
        echo "$sess,$pid,$T,$rep,$s,${r// /,}" >> "$out"
      done
    done
  done
  echo "checked $pid ($a vs $b) $(date +%T)"
done
