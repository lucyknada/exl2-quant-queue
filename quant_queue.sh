#!/bin/bash

USER=""
HFTOKEN=""

. ./venv/bin/activate

quant() {
  BPW="$2"

  mkdir -p ./output/$1/temp || exit

  if [ ! -f "./output/$1/measurement.json" ]; then
    python convert.py \
      -i ./models/$1/ \
      -o ./output/$1/temp/ \
      -nr \
      -om ./output/$1/measurement.json || exit
  fi

  OUTPUT_DIRECTORY="./output/$1/output-${BPW}"

  if [ ! -f "${OUTPUT_DIRECTORY}/config.json" ]; then
    python convert.py \
      -i ./models/$1/ \
      -o ./output/$1/temp/ \
      -nr \
      -m ./output/$1/measurement.json \
      -cf "$OUTPUT_DIRECTORY" \
      -b $BPW || exit
  fi

  cat "./models/${1}/README.md" | sed -z "s/---/---\n### exl2 quant (measurement.json in main branch)\n---\n### check revisions for quants\n---\n/2" > "${OUTPUT_DIRECTORY}/README.md"
  HF_HUB_ENABLE_HF_TRANSFER=1 huggingface-cli upload --private --revision ${BPW}bpw "${USER}/${1}-exl2" "${OUTPUT_DIRECTORY}" || exit
  HF_HUB_ENABLE_HF_TRANSFER=1 huggingface-cli upload --private "${USER}/${1}-exl2" ${OUTPUT_DIRECTORY}/README.md ./README.md || exit
  HF_HUB_ENABLE_HF_TRANSFER=1 huggingface-cli upload --private "${USER}/${1}-exl2" ./output/$1/measurement.json ./measurement.json || exit
}

while IFS= read -r line || [[ -n "$line" ]]; do
  modified_line="${line#https://}"
  IFS="/" read -ra parts <<< "$modified_line"
  x="${parts[-3]}"
  y="${parts[-2]}"
  BPW="${parts[-1]}"

  response_code=$(curl --write-out '%{http_code}' --silent --output /dev/null "https://huggingface.co/${USER}/${x}_${y}-exl2/tree/${BPW}bpw")
  if [ $response_code -eq 200 ]; then
    continue
  fi
  
  if [ ! -f "./output/${x}_${y}/output/output.safetensors" ]; then
    if [ ! -f "./models/${x}_${y}/config.json" ]; then
      HF_HUB_ENABLE_HF_TRANSFER=1 huggingface-cli download "${x}/${y}" --local-dir="./models/${x}_${y}" --local-dir-use-symlinks=False
      python ./util/convert_safetensors.py ./models/${x}_${y}/*.bin
      rm ./models/${x}_${y}/*.bin
      rm ./models/${x}_${y}/*.pth
    fi
    quant "${x}_${y}" "$BPW"
  fi
done < "queue.txt"
