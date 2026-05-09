#!/usr/bin/env bash

set -e

ID="job-$(date +%s)"
URL="$1"

if [ -z "$URL" ]; then
  echo "Usage: ./enqueue.sh <url>"
  exit 1
fi

cat > "queue/pending/${ID}.json" <<EOF
{
  "id": "${ID}",
  "url": "${URL}",
  "retries": 0,
  "max_retries": 3
}
EOF

echo "Enqueued: $ID"