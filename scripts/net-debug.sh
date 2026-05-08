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
curl -s --max-time 10 ifconfig.me
echo

echo
echo "Resolver config:"
cat /etc/resolv.conf

echo
echo "Routes:"
ip route

echo
echo "================================================="
echo "SOURCE ASN"
echo "================================================="

timeout 15 whois "$(curl -s --max-time 10 ifconfig.me)" | head -40

echo
echo "================================================="
echo "TARGET ASN"
echo "================================================="

TARGET_IP=$(getent hosts "$HOST" | awk '{print $1}' | head -1)

echo "Resolved IP: $TARGET_IP"

if [ -n "$TARGET_IP" ]; then
  timeout 15 whois "$TARGET_IP" | head -60
fi

echo
echo "================================================="
echo "DNS TESTS"
echo "================================================="

echo
echo "getent:"
timeout 10 getent hosts "$HOST"

echo
echo "host:"
timeout 10 host "$HOST"

echo
echo "dig default:"
timeout 10 dig "$HOST"

echo
echo "dig cloudflare:"
timeout 10 dig @"1.1.1.1" "$HOST"

echo
echo "dig google:"
timeout 10 dig @"8.8.8.8" "$HOST"

echo
echo "dig quad9:"
timeout 10 dig @"9.9.9.9" "$HOST"

echo
echo "================================================="
echo "TCP TESTS"
echo "================================================="

TCP443_OK=0
TCP80_OK=0

echo
echo "Port 443:"
timeout 15 nc -vz "$HOST" 443
if [ $? -eq 0 ]; then
  TCP443_OK=1
fi

echo
echo "Port 80:"
timeout 15 nc -vz "$HOST" 80
if [ $? -eq 0 ]; then
  TCP80_OK=1
fi

echo
echo "================================================="
echo "TRACEROUTE TCP 443"
echo "================================================="

timeout 60 traceroute -T -p 443 "$HOST"

echo
echo "================================================="
echo "MTR"
echo "================================================="

timeout 60 mtr -rwzc 10 "$HOST"

if [ "$TCP443_OK" -ne 1 ] && [ "$TCP80_OK" -ne 1 ]; then
  echo
  echo "================================================="
  echo "EARLY EXIT"
  echo "================================================="
  echo "TCP connectivity failed on both 80 and 443."
  echo "Skipping TLS/HTTP/download tests."
  exit 1
fi

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

timeout 30 curl \
  -I \
  -L \
  --connect-timeout 10 \
  --max-time 20 \
  -v \
  "$URL"

echo
echo "================================================="
echo "WGET TEST"
echo "================================================="

timeout 30 wget \
  --tries=1 \
  --timeout=15 \
  --dns-timeout=10 \
  --connect-timeout=10 \
  --read-timeout=20 \
  --server-response \
  --spider \
  "$URL"

echo
echo "================================================="
echo "ARIA2 TEST"
echo "================================================="

timeout 40 aria2c \
  --dry-run=true \
  --max-tries=1 \
  --retry-wait=0 \
  --timeout=20 \
  --connect-timeout=10 \
  --dns-timeout=10 \
  --check-certificate=false \
  --max-connection-per-server=2 \
  --split=2 \
  --console-log-level=notice \
  --log-level=debug \
  --log="logs/aria2_${TIMESTAMP}.log" \
  "$URL"

echo
echo "================================================="
echo "DOWNLOAD TEST"
echo "================================================="

timeout 300 aria2c \
  --continue=true \
  --max-tries=1 \
  --retry-wait=0 \
  --timeout=30 \
  --connect-timeout=15 \
  --dns-timeout=10 \
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