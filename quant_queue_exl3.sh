#!/bin/bash

USER=""

# Number of GPUs per quant job
GPUS_PER_JOB=2

# List of all available GPUs
DEVICES=(0 1 2 3 4 5 6 7)

# TMUX session name
SESSION="quant_session"

# Default tmux dimensions to ensure pane splits succeed when detached
DEFAULT_TMUX_COLS=200
DEFAULT_TMUX_LINES=60

# Path to job queue file
QUEUE_FILE="queue.txt"

# Lock folder for serializing downloads
LOCKDIR="./locks"
mkdir -p "$LOCKDIR"

# Lock file naming
PANE_READY_PREFIX="pane_"
PANE_READY_SUFFIX=".ready"
DOWNLOAD_LOCK_SUFFIX=".lock"

# Clean stale locks from previous runs
find "$LOCKDIR" -maxdepth 1 -type f -name "${PANE_READY_PREFIX}*${PANE_READY_SUFFIX}" -delete
find "$LOCKDIR" -maxdepth 1 -type f -name "*${DOWNLOAD_LOCK_SUFFIX}" -delete

NUM_DEVICES=${#DEVICES[@]}
PARALLEL=$(( NUM_DEVICES / GPUS_PER_JOB ))
if (( PARALLEL < 1 )); then
  echo "Error: Not enough GPUs"
  exit 1
fi

quant() {
  MODEL="$1"; BPW="$2"; DEVSTR="$3"
  [ -z "$DEVSTR" ] && { echo "ERR: empty devices"; return 1; }

  WORK_DIRECTORY="./output/$MODEL/temp-${BPW}"
  OUTPUT_DIRECTORY="./output/$MODEL/output-${BPW}"
  mkdir -p "$WORK_DIRECTORY" "$OUTPUT_DIRECTORY" || return 1

  if [ ! -f "${OUTPUT_DIRECTORY}/config.json" ]; then
    echo "Running quant on $MODEL at ${BPW}bpw using GPUs $DEVSTR"
    python convert.py -i "./models/$MODEL/" -w "$WORK_DIRECTORY" -d "$DEVSTR" -o "$OUTPUT_DIRECTORY" -b "$BPW" || return 1
  fi

  sed -z "s/---/---\\n### exl3 quant\\n---\\n### check revisions for quants\\n---\\n/2" \
    "./models/${MODEL}/README.md" > "${OUTPUT_DIRECTORY}/README.md"

  HF_HUB_ENABLE_HF_TRANSFER=1 hf upload --private --revision "${BPW}bpw" "${USER}/${MODEL}-exl3" "${OUTPUT_DIRECTORY}" || true
  HF_HUB_ENABLE_HF_TRANSFER=1 hf upload --private "${USER}/${MODEL}-exl3" "${OUTPUT_DIRECTORY}/README.md" ./README.md || true
}

download_model() {
  MODEL="$1"; X="$2"; Y="$3"
  LOCKFILE="$LOCKDIR/${MODEL}.lock"
  mkdir -p "$LOCKDIR"
  exec 9>"$LOCKFILE" || return 1
  flock -x 9

  if [ ! -f "./models/${MODEL}/config.json" ]; then
    echo "Downloading $X/$Y ..."
    HF_HUB_ENABLE_HF_TRANSFER=1 hf download "${X}/${Y}" \
      --exclude "*.arrow" \
      --exclude "*checkpoint*" \
      --exclude "*global_state*" \
      --exclude "*.pth" \
      --exclude "*.pt" \
      --exclude "*.nemo" \
      --local-dir="./models/${MODEL}"
    if ls ./models/${MODEL}/*.bin 1>/dev/null 2>&1; then
      python ./util/convert_safetensors.py ./models/${MODEL}/*.bin && rm ./models/${MODEL}/*.bin
    fi
  fi
  # release the download lock immediately after ensuring presence
  flock -u 9; exec 9>&-
}

process_line() {
  src="$1"; devstr="$2"; local_devs="$3"; idx="$4"
  # Read URL line from file if a file path is provided
  if [ -f "$src" ]; then
    line="$(cat "$src")"
  else
    line="$src"
  fi
  # Robustly parse https://<host>/<org>/<repo>/<bpw>
  modified="$line"
  modified="${modified#http://}"
  modified="${modified#https://}"
  IFS='/' read -r host x y BPW <<< "$modified"
  MODEL="${x}_${y}"

  echo "[job $idx] -> GPUs $devstr (local: $local_devs)"
  echo "[job $idx] url='$line' x='$x' y='$y' bpw='$BPW'"
  download_model "$MODEL" "$x" "$y"
  quant "$MODEL" "$BPW" "$local_devs"
}

export -f process_line quant download_model
export USER GPUS_PER_JOB LOCKDIR

# Materialize function definitions for tmux panes to source (export -f is not reliable across tmux)
LIB_PATH="$LOCKDIR/lib.sh"
{
  declare -f process_line
  declare -f quant
  declare -f download_model
} > "$LIB_PATH"

# detect venv path
if [ -d "./venv" ]; then
  VENV_PATH="./venv/bin/activate"
elif [ -d "./.venv" ]; then
  VENV_PATH="./.venv/bin/activate"
else
  VENV_PATH=""
fi

# ensure tmux exists
if ! command -v tmux >/dev/null 2>&1; then
  echo "Error: tmux is not installed or not on PATH"; exit 1
fi

# Determine number of jobs (ignore blank lines and lines starting with #)
JOB_COUNT=$(awk 'BEGIN{c=0} /^[[:space:]]*#/ {next} NF {c++} END{print c+0}' "$QUEUE_FILE" 2>/dev/null || echo 0)
if (( JOB_COUNT == 0 )); then
  echo "No jobs found in $QUEUE_FILE"
  exit 0
fi

# Do not create more panes than jobs
if (( PARALLEL > JOB_COUNT )); then
  PARALLEL=$JOB_COUNT
fi

# Kill old tmux session if exists and start one fresh
tmux kill-session -t "$SESSION" 2>/dev/null
tmux new-session -d -s "$SESSION" -x "$(tput cols 2>/dev/null || echo "$DEFAULT_TMUX_COLS")" -y "$(tput lines 2>/dev/null || echo "$DEFAULT_TMUX_LINES")" -c "$PWD" bash   # start detached with one shell sized to terminal

# Build fixed GPU groups of size GPUS_PER_JOB so groups are never re-used concurrently
# Helper to compute device string for a given pane index
compute_devstr_for_pane() {
  local pane_idx=$1
  local start=$(( pane_idx * GPUS_PER_JOB ))
  local group=( "${DEVICES[@]:$start:$GPUS_PER_JOB}" )
  if [ ${#group[@]} -lt $GPUS_PER_JOB ]; then
    local needed=$(( GPUS_PER_JOB - ${#group[@]} ))
    group+=( "${DEVICES[@]:0:$needed}" )
  fi
  ( IFS=,; echo "${group[*]}" )
}

# Ensure we have exactly PARALLEL panes ready and mark them initially idle
for (( i=1; i<PARALLEL; i++ )); do
  if tmux split-window -t "$SESSION:0" -h -d -c "$PWD" bash 2>/dev/null; then
    :
  elif tmux split-window -t "$SESSION:0" -v -d -c "$PWD" bash 2>/dev/null; then
    :
  else
    echo "Warning: Unable to create additional tmux pane; limiting concurrency."
    break
  fi
  tmux select-layout -t "$SESSION:0" tiled
done

# Adapt PARALLEL to the actual number of panes that were created
actual_panes="$(tmux list-panes -t "$SESSION:0" 2>/dev/null | wc -l | tr -d ' ')"
if [ -n "$actual_panes" ] && [ "$actual_panes" -gt 0 ]; then
  PARALLEL="$actual_panes"
fi

next_pane=0
for (( i=0; i<PARALLEL; i++ )); do
  touch "$LOCKDIR/${PANE_READY_PREFIX}${i}${PANE_READY_SUFFIX}"
done

find_ready_pane() {
  while true; do
    for (( k=0; k<PARALLEL; k++ )); do
      idx=$(( (k + next_pane) % PARALLEL ))
      file="$LOCKDIR/${PANE_READY_PREFIX}${idx}${PANE_READY_SUFFIX}"
      if [ -f "$file" ]; then
        next_pane=$(( (idx + 1) % PARALLEL ))
        echo "$idx"
        return 0
      fi
    done
    sleep 1
  done
}

job_index=0
pane_index=0
while IFS= read -r line || [[ -n "$line" ]]; do
  pane=$(find_ready_pane)
  devstr="$(compute_devstr_for_pane "$pane")"
  # build local device indices for this process and remap via CUDA_VISIBLE_DEVICES
  local_devs=""
  for (( j=0; j<GPUS_PER_JOB; j++ )); do
    if [ $j -gt 0 ]; then local_devs+=","; fi
    local_devs+="$j"
  done
  # mark pane busy immediately to avoid double-dispatch races
  ready_file="$LOCKDIR/${PANE_READY_PREFIX}${pane}${PANE_READY_SUFFIX}"
  rm -f "$ready_file"

  # write the job line to a file to avoid complex quoting/arg passing issues
  job_file="$LOCKDIR/pane_${pane}.job"
  printf "%s" "$line" > "$job_file"

  cmd="bash -c 'export CUDA_VISIBLE_DEVICES=\"\$1\"; export LOCKDIR=\"\$8\"; if [ -n \"\$2\" ] && [ -f \"\$2\" ]; then . \"\$2\"; fi; . \"\$7\"; echo \"[dispatch] pane ${pane} -> GPUs \$1 (CVD=\$CUDA_VISIBLE_DEVICES)\"; process_line \"\$3\" \"\$1\" \"\$4\" \"\$5\"; status=\$?; touch \"\$6\"; echo \"--- DONE (status=\$status) ---\"; exec bash' -- \"$devstr\" \"$VENV_PATH\" \"$job_file\" \"$local_devs\" \"$job_index\" \"$ready_file\" \"$LIB_PATH\" \"$LOCKDIR\""

  tmux respawn-pane -t "$SESSION:0.$pane" -k "$cmd"

  ((job_index++))
done < "$QUEUE_FILE"

# Attach or switch to the session depending on whether we're already in tmux
if [ -n "$TMUX" ]; then
  tmux switch-client -t "$SESSION"
else
  exec tmux attach -t "$SESSION"
fi
