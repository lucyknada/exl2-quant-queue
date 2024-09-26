#!/bin/bash

# usage: ./quant_single.sh https://huggingface.co/Qwen/Qwen2.5-72B-Instruct/3.0

USER=""

quant() {
  BPW="$2"

  mkdir -p ./output/$1/temp/$BPW || exit

  if [ ! -f "./output/$1/measurement.json" ]; then
    python convert.py \
      -i ./models/$1/ \
      -o ./output/$1/temp/$BPW/ \
      -nr \
      -om ./output/$1/measurement.json || exit
  fi

  OUTPUT_DIRECTORY="./output/$1/output-${BPW}"

  if [ ! -f "${OUTPUT_DIRECTORY}/config.json" ]; then
    python convert.py \
      -i ./models/$1/ \
      -o ./output/$1/temp/$BPW/ \
      -nr \
      -m ./output/$1/measurement.json \
      -cf "$OUTPUT_DIRECTORY" \
      -b $BPW || exit
  fi

  echo "" > "${OUTPUT_DIRECTORY}/README.md"
  HF_HUB_ENABLE_HF_TRANSFER=1 huggingface-cli upload --private --revision ${BPW}bpw "${USER}/${1}-exl2" "${OUTPUT_DIRECTORY}" || return 0
  HF_HUB_ENABLE_HF_TRANSFER=1 huggingface-cli upload --private "${USER}/${1}-exl2" ${OUTPUT_DIRECTORY}/README.md ./README.md || return 0
  HF_HUB_ENABLE_HF_TRANSFER=1 huggingface-cli upload --private "${USER}/${1}-exl2" ./output/$1/measurement.json ./measurement.json || return 0
}

line="$1"
modified_line="${line#https://}"
IFS="/" read -ra parts <<< "$modified_line"
x="${parts[-3]}"
y="${parts[-2]}"
BPW="${parts[-1]}"

if [ ! -f "./models/${x}_${y}/config.json" ]; then
  HF_HUB_ENABLE_HF_TRANSFER=1 huggingface-cli download "${x}/${y}" --local-dir="./models/${x}_${y}" --local-dir-use-symlinks=False
  python ./util/convert_safetensors.py ./models/${x}_${y}/*.bin
  rm ./models/${x}_${y}/*.bin
  rm ./models/${x}_${y}/*.pth
fi

quant "${x}_${y}" "$BPW"
