#!/bin/bash
# check_pairs2.sh — check_pairs.sh와 같은 절차 + 수신 바이트 수 기록 + 무효 표본 재측정
# 무효 기준(재측정 전 사전 정의, PREDICTIONS_supp.txt P10): 경과 < 0 또는 > 3000ms, 또는 수신 바이트 < 391B.
# 무효이면 같은 조건을 최대 3회 다시 측정. 무효 표본도 valid=0으로 모두 기록.
# 사용: check_pairs2.sh <session> <pair_id:a:b> [...]
# 결과: data/check_<session>.csv (session,pair_id,T,rep,img_size,elapsed_ms,class,nbytes,valid)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib_supp.sh"
sess="$1"; shift
out="$DATA_DIR/check_${sess}.csv"
[ -f "$out" ] || echo "session,pair_id,T,rep,img_size,elapsed_ms,class,nbytes,valid" > "$out"
MIN_BYTES=391
for spec in "$@"; do
  IFS=: read -r pid a b <<< "$spec"
  for T in 0.005 0.02 0.05 0.1 0.2; do
    for rep in 1 2; do
      if [ "$rep" -eq 1 ]; then order="$a $b"; else order="$b $a"; fi
      for s in $order; do
        set_img_size "$s"
        for try in 1 2 3 4; do
          r=$(measure_T2 "$T"); read -r e c n <<< "$r"
          v=1
          if [ "$e" -lt 0 ] || [ "$e" -gt 3000 ] || [ "$n" -lt "$MIN_BYTES" ]; then v=0; fi
          echo "$sess,$pid,$T,$rep,$s,$e,$c,$n,$v" >> "$out"
          [ "$v" -eq 1 ] && break
          echo "  [INVALID] $pid T=$T rep=$rep size=$s e=$e n=$n (try $try)" >&2
        done
      done
    done
  done
  echo "checked $pid ($a vs $b) $(date +%T)"
done
