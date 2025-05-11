#!/bin/bash

USER=""

quant() {
  BPW="$2"

  WORK_DIRECTORY="./output/$1/temp"
  OUTPUT_DIRECTORY="./output/$1/output-${BPW}"

  mkdir -p "$WORK_DIRECTORY" || exit
  mkdir -p "$OUTPUT_DIRECTORY" || exit

  if [ -f "${OUTPUT_DIRECTORY}/config.json" ]; then
    echo "Conversion for $1 at ${BPW}bpw already complete. Skipping."
  else
    python convert.py \
      -i ./models/$1/ \
      -w "$WORK_DIRECTORY" \
      -d 1 \
      -o "$OUTPUT_DIRECTORY" \
      -b $BPW || exit
  fi

  cat "./models/${1}/README.md" | sed -z "s/---/---\n### exl3 quant\n---\n### check revisions for quants\n---\n/2" > "${OUTPUT_DIRECTORY}/README.md"
  HF_HUB_ENABLE_HF_TRANSFER=1 huggingface-cli upload --private --revision ${BPW}bpw "${USER}/${1}-exl3" "${OUTPUT_DIRECTORY}" || return 0
  HF_HUB_ENABLE_HF_TRANSFER=1 huggingface-cli upload --private "${USER}/${1}-exl3" ${OUTPUT_DIRECTORY}/README.md ./README.md || return 0
}

while IFS= read -r line || [[ -n "$line" ]]; do
  modified_line="${line#https://}"
  IFS="/" read -ra parts <<< "$modified_line"
  x="${parts[-3]}"
  y="${parts[-2]}"
  BPW="${parts[-1]}"

  if [ ! -f "./models/${x}_${y}/config.json" ]; then
    HF_HUB_ENABLE_HF_TRANSFER=1 huggingface-cli download "${x}/${y}" --exclude "*.arrow" "*checkpoint*" "*global_state*" "*.pth" "*.pt" "*.nemo" --local-dir="./models/${x}_${y}"
    if ls ./models/${x}_${y}/*.bin 1> /dev/null 2>&1; then
      python ./util/convert_safetensors.py ./models/${x}_${y}/*.bin
      rm ./models/${x}_${y}/*.bin
    fi
  fi

  quant "${x}_${y}" "$BPW"

done < "queue.txt"
