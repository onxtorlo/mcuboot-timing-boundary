#!/bin/bash
# reset_only.sh <session> <size> <n> : 이미지를 한 번만 기록한 뒤 플래시 쓰기 없이 리셋+고해상도 캡처만 n회 반복
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib_supp.sh"
sess=$1; size=$2; n=$3
out="$DATA_DIR/resetonly_${sess}.csv"; js="$DATA_DIR/resetonly_${sess}.jsonl"
echo "session,i,img_size,wall,t_first,t_last,nbytes" > "$out"; : > "$js"
set_img_size "$size"; write_header_sector
for i in $(seq 1 "$n"); do
  wall=$(date +%s.%N)
  python3 "$SCRIPT_DIR/hr_capture.py" 3 > /tmp/ro.json
  cat /tmp/ro.json >> "$js"
  hr=$(python3 -c 'import json; d=json.load(open("/tmp/ro.json")); print(d["t_first_ms"], d["t_last_ms"], d["nbytes"])')
  echo "$sess,$i,$size,$wall,${hr// /,}" >> "$out"
done
echo RO_DONE "$sess"
