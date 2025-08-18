#!/bin/bash

USER=""
PARALLEL=2
DEVICES=(0 1 2 3 4 5 6 7)   # available GPUs
LOCKDIR="./locks"
mkdir -p "$LOCKDIR"

NUM_DEVICES=${#DEVICES[@]}
CHUNK_SIZE=$(( (NUM_DEVICES + PARALLEL - 1) / PARALLEL ))

if [ $CHUNK_SIZE -lt 1 ]; then
  echo "Error: Not enough GPUs (${NUM_DEVICES}) for PARALLEL=$PARALLEL"
  exit 1
fi

quant() {
  MODEL="$1"
  BPW="$2"
  DEVSTR="$3"

  WORK_DIRECTORY="./output/$MODEL/temp"
  OUTPUT_DIRECTORY="./output/$MODEL/output-${BPW}"

  mkdir -p "$WORK_DIRECTORY" || exit
  mkdir -p "$OUTPUT_DIRECTORY" || exit

  if [ -f "${OUTPUT_DIRECTORY}/config.json" ]; then
    echo "Conversion for $MODEL at ${BPW}bpw already complete. Skipping."
  else
    echo "Running quant on $MODEL at ${BPW}bpw using GPUs $DEVSTR"
    python convert.py \
      -i ./models/$MODEL/ \
      -w "$WORK_DIRECTORY" \
      -d "$DEVSTR" \
      -o "$OUTPUT_DIRECTORY" \
      -b $BPW || exit
  fi

  sed -z "s/---/---\n### exl3 quant\n---\n### check revisions for quants\n---\n/2" \
    "./models/${MODEL}/README.md" > "${OUTPUT_DIRECTORY}/README.md"

  HF_HUB_ENABLE_HF_TRANSFER=1 hf upload --private --revision ${BPW}bpw "${USER}/${MODEL}-exl3" "${OUTPUT_DIRECTORY}" || return 0
  HF_HUB_ENABLE_HF_TRANSFER=1 hf upload --private "${USER}/${MODEL}-exl3" ${OUTPUT_DIRECTORY}/README.md ./README.md || return 0
}

download_model() {
  MODEL="$1"
  X="$2"
  Y="$3"

  LOCKFILE="$LOCKDIR/${MODEL}.lock"

  # acquire exclusive lock per model
  exec {fd}>$LOCKFILE
  flock -x $fd

  if [ ! -f "./models/${MODEL}/config.json" ]; then
    echo "Downloading model $X/$Y ..."
    HF_HUB_ENABLE_HF_TRANSFER=1 hf download "${X}/${Y}" \
      --exclude "*.arrow" "*checkpoint*" "*global_state*" "*.pth" "*.pt" "*.nemo" \
      --local-dir="./models/${MODEL}"

    if ls ./models/${MODEL}/*.bin 1> /dev/null 2>&1; then
      python ./util/convert_safetensors.py ./models/${MODEL}/*.bin
      rm ./models/${MODEL}/*.bin
    fi
  fi

  # lock released automatically when fd goes out of scope
}

process_line() {
  line="$1"
  slot="$2"  # worker slot number (0..PARALLEL-1)

  modified_line="${line#https://}"
  IFS="/" read -ra parts <<< "$modified_line"
  x="${parts[-3]}"
  y="${parts[-2]}"
  BPW="${parts[-1]}"
  MODEL="${x}_${y}"

  start=$(( slot * CHUNK_SIZE ))
  devices=("${DEVICES[@]:$start:$CHUNK_SIZE}")

  if [ ${#devices[@]} -eq 0 ]; then
    echo "Error: No GPUs assigned for slot $slot"
    exit 1
  fi

  devstr=$(IFS=, ; echo "${devices[*]}")

  # guarded model download
  download_model "$MODEL" "$x" "$y"

  quant "$MODEL" "$BPW" "$devstr"
}

export -f process_line quant download_model
export USER DEVICES PARALLEL CHUNK_SIZE LOCKDIR

# slot dispatcher: alternate jobs between slots 0..PARALLEL-1
slot=0
while IFS= read -r line || [[ -n "$line" ]]; do
  ( process_line "$line" "$slot" ) &
  ((slot=(slot+1)%PARALLEL))
  if (( slot == 0 )); then
    wait
  fi
done < "queue.txt"
wait
