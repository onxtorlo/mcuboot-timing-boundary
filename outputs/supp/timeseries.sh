#!/bin/bash
# timeseries.sh <session> <size> <cycles> : [고해상도 캡처(JSON 전체 저장) -> T=0.05 측정] 교대
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib_supp.sh"
sess=$1; size=$2; n=$3
out="$DATA_DIR/ts_${sess}.csv"; js="$DATA_DIR/ts_${sess}.jsonl"
echo "session,cycle,img_size,wall,t_first,t_last,nbytes,poll50_ms,poll50_class" > "$out"; : > "$js"
set_img_size "$size"
for i in $(seq 1 "$n"); do
  wall=$(date +%s.%N)
  write_header_sector; python3 "$SCRIPT_DIR/hr_capture.py" 3 > /tmp/ts.json
  cat /tmp/ts.json >> "$js"
  hr=$(python3 -c 'import json; d=json.load(open("/tmp/ts.json")); print(d["t_first_ms"], d["t_last_ms"], d["nbytes"])')
  r=$(measure_retry 0.05)
  echo "$sess,$i,$size,$wall,${hr// /,},${r// /,}" >> "$out"
done
echo TS_DONE "$sess"
