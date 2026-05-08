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
PUBLIC_IP=$(curl -s --max-time 10 ifconfig.me)
echo "$PUBLIC_IP"

echo
echo "Geo:"
curl -s --max-time 10 ipinfo.io
echo

echo
echo "Resolver config:"
cat /etc/resolv.conf

echo
echo "Routes:"
ip route

if [ -n "$FORCED_IP" ]; then
  echo
  echo "================================================="
  echo "FORCED HOST ENTRY"
  echo "================================================="

  echo "$FORCED_IP $HOST" | sudo tee -a /etc/hosts

  echo
  echo "/etc/hosts:"
  tail -10 /etc/hosts
fi

echo
echo "================================================="
echo "SOURCE ASN"
echo "================================================="

timeout 20 whois "$PUBLIC_IP" | head -40

echo
echo "================================================="
echo "TARGET ASN"
echo "================================================="

TARGET_IP=$(getent hosts "$HOST" | awk '{print $1}' | head -1)

echo "Resolved IP: $TARGET_IP"

if [ -n "$TARGET_IP" ]; then
  timeout 20 whois "$TARGET_IP" | head -60
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
echo "RAW TCP TESTS"
echo "================================================="

echo
echo "Bash TCP 443:"
timeout 10 bash -c "</dev/tcp/$HOST/443"
echo "Exit code: $?"

echo
echo "Bash TCP 80:"
timeout 10 bash -c "</dev/tcp/$HOST/80"
echo "Exit code: $?"

echo
echo "================================================="
echo "TCP TESTS"
echo "================================================="

TCP443_OK=0
TCP80_OK=0

echo
echo "Port 443:"
timeout 15 bash -c "nc -vz $HOST 443"
RET443=$?

if [ "$RET443" -eq 0 ]; then
  echo "TCP 443 OK"
  TCP443_OK=1
else
  echo "TCP 443 FAILED (exit=$RET443)"
fi

echo
echo "Port 80:"
timeout 15 bash -c "nc -vz $HOST 80"
RET80=$?

if [ "$RET80" -eq 0 ]; then
  echo "TCP 80 OK"
  TCP80_OK=1
else
  echo "TCP 80 FAILED (exit=$RET80)"
fi

echo
echo "================================================="
echo "TRACEPATH"
echo "================================================="

timeout 60 tracepath "$HOST"

echo
echo "================================================="
echo "MTR TCP/443"
echo "================================================="

timeout 60 mtr --tcp --port 443 -rwzc 10 "$HOST"

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