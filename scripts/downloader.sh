#!/usr/bin/env bash

set -euo pipefail

RAW_INPUT="$1"

mkdir -p downloads tmp logs

LOG="logs/download_$(date +%s).log"
exec > >(tee -a "$LOG") 2>&1

echo "================================================="
echo "DOWNLOAD PIPELINE START"
echo "================================================="

# normalize input → array
IFS=$'\n' read -rd '' -a URL_LIST <<< "$(echo "$RAW_INPUT" | tr ' ' '\n' | sed '/^$/d')"

echo "Total URLs: ${#URL_LIST[@]}"

# -------------------------------------------------
# CONFIG
# -------------------------------------------------
MAX_RETRIES=3
CONNECT_TIMEOUT=10
TIMEOUT=30
CHUNK_SIZE="50M"

# -------------------------------------------------
# PROCESS EACH URL
# -------------------------------------------------
for URL in "${URL_LIST[@]}"; do

  echo
  echo "================================================="
  echo "URL: $URL"
  echo "================================================="

  HOST=$(echo "$URL" | awk -F/ '{print $3}')
  SAFE_HASH=$(echo -n "$URL" | sha1sum | cut -c1-8)
  RAW_NAME=$(basename "$URL" | cut -d'?' -f1)

  if [[ -z "$RAW_NAME" || "$RAW_NAME" == "/" ]]; then
    RAW_NAME="file_${SAFE_HASH}"
  fi

  SAFE_NAME="$(echo "$RAW_NAME" | tr -cd '[:alnum:]._-')"
  OUT="downloads/${SAFE_NAME}_${SAFE_HASH}.bin"

  echo "Host: $HOST"
  echo "Output: $OUT"

  # -------------------------------------------------
  # FAST PRECHECK (NO WASTED TIME)
  # -------------------------------------------------
  echo "TCP precheck..."

  if ! timeout $CONNECT_TIMEOUT bash -c "</dev/tcp/$HOST/443"; then
    echo "❌ TCP 443 unreachable → skipping"
    continue
  fi

  # -------------------------------------------------
  # DOWNLOAD WITH CONTROLLED RETRIES
  # -------------------------------------------------
  ATTEMPT=1
  SUCCESS=0

  while [ $ATTEMPT -le $MAX_RETRIES ]; do

    echo "Attempt $ATTEMPT / $MAX_RETRIES"

    aria2c \
      --file-allocation=none \
      --continue=true \
      --max-connection-per-server=4 \
      --split=4 \
      --min-split-size=$CHUNK_SIZE \
      --timeout=$TIMEOUT \
      --connect-timeout=$CONNECT_TIMEOUT \
      --retry-wait=3 \
      --max-tries=1 \
      --summary-interval=5 \
      --dir=downloads \
      --out="$(basename "$OUT")" \
      "$URL"

    if [ $? -eq 0 ]; then
      SUCCESS=1
      break
    fi

    echo "Retrying..."
    ATTEMPT=$((ATTEMPT + 1))
    sleep 2

  done

  if [ $SUCCESS -ne 1 ]; then
    echo "❌ FAILED: $URL"
    echo "$URL" >> logs/failed.txt
  else
    echo "✅ DONE: $URL"
  fi

done

echo
echo "================================================="
echo "PIPELINE FINISHED"
echo "================================================="