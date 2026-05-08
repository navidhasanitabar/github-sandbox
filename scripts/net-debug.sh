#!/usr/bin/env bash

set +e

URL="$1"

mkdir -p logs downloads

TIMESTAMP=$(date +%s)

LOG="logs/debug_${TIMESTAMP}.log"

exec > >(tee -a "$LOG") 2>&1

echo "================================================="
echo "URL: $URL"
echo "TIME: $(date)"
echo "================================================="

HOST=$(echo "$URL" | awk -F/ '{print $3}')

echo
echo "================================================="
echo "BASIC INFO"
echo "================================================="

echo "Host: $HOST"

echo
echo "Public IP:"
curl -s ifconfig.me
echo

echo
echo "Resolver config:"
cat /etc/resolv.conf

echo
echo "================================================="
echo "DNS TESTS"
echo "================================================="

echo
echo "getent:"
getent hosts "$HOST"

echo
echo "host:"
host "$HOST"

echo
echo "dig default:"
dig "$HOST"

echo
echo "dig cloudflare:"
dig @"1.1.1.1" "$HOST"

echo
echo "dig google:"
dig @"8.8.8.8" "$HOST"

echo
echo "dig quad9:"
dig @"9.9.9.9" "$HOST"

echo
echo "================================================="
echo "TCP TESTS"
echo "================================================="

echo
echo "Port 443:"
nc -vz "$HOST" 443

echo
echo "Port 80:"
nc -vz "$HOST" 80

echo
echo "================================================="
echo "TLS TEST"
echo "================================================="

timeout 30 openssl s_client \
  -connect "${HOST}:443" \
  -servername "$HOST" </dev/null

echo
echo "================================================="
echo "HTTP HEAD"
echo "================================================="

curl -I -L \
  --connect-timeout 20 \
  --max-time 60 \
  -v \
  "$URL"

echo
echo "================================================="
echo "WGET TEST"
echo "================================================="

wget \
  --server-response \
  --spider \
  "$URL"

echo
echo "================================================="
echo "ARIA2 TEST"
echo "================================================="

aria2c \
  --dry-run=true \
  --check-certificate=false \
  --max-connection-per-server=2 \
  --split=2 \
  --console-log-level=debug \
  --log-level=debug \
  --log="logs/aria2_${TIMESTAMP}.log" \
  "$URL"

echo
echo "================================================="
echo "DOWNLOAD TEST"
echo "================================================="

aria2c \
  --continue=true \
  --max-connection-per-server=4 \
  --split=4 \
  --min-split-size=50M \
  --file-allocation=none \
  --summary-interval=5 \
  --console-log-level=notice \
  --dir=downloads \
  "$URL"

echo
echo "================================================="
echo "FILES"
echo "================================================="

ls -lah downloads/

echo
echo "================================================="
echo "DONE"
echo "================================================="
