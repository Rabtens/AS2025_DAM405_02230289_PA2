#!/usr/bin/env bash
# capture_rollout.sh — run the blue-green cutover + rollback as a *measured*
# demonstration and write the transcript to evidence/.
#
# Unlike simply running switch_traffic.sh, this tags client traffic with a
# distinct User-Agent so requests arriving at each slot can be counted
# separately from that slot's own container HEALTHCHECK polls -- i.e. it proves
# traffic actually moved, rather than trusting the script's exit code. It also
# fires a continuous request loop across the cutover to measure downtime.
#
# Usage (from the repo root, with the stack already up):
#   PROXY_PORT=18080 PROXY_URL=http://localhost:18080 bash report/capture_rollout.sh
set -euo pipefail

PROXY_URL="${PROXY_URL:-http://localhost:8080}"
PYTHON="${PYTHON:-python3}"
OUT="evidence/blue_green_rollout_transcript.txt"
UA="dam405-demo-client"
POLL_FILE="$(mktemp)"
trap 'rm -f "$POLL_FILE"' EXIT

slotcount() { docker logs "wine-api-$1" 2>&1 | grep -c "$UA" || true; }
hit() { for _ in $(seq "$1"); do curl -s -A "$UA" -o /dev/null -w "%{http_code} " "$PROXY_URL/health"; done; echo; }

{
echo "==================================================================="
echo " DAM405 Assignment 2 — Blue-green rollout & rollback transcript"
echo " Captured: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo " Proxy:    $PROXY_URL"
echo " Method:   client traffic carries User-Agent '$UA' so it can be counted"
echo "           separately from each slot's own container HEALTHCHECK polls."
echo "==================================================================="
echo
echo "### 0. Topology — both slots run continuously; exactly one is live"
docker compose ps --format 'table {{.Name}}\t{{.Status}}'
echo
echo "### 1. BEFORE cutover — blue is live"
grep "server wine-api" deployment/nginx.conf
printf "20 client requests through the proxy: "; hit 20
B1=$(slotcount blue); G1=$(slotcount green)
echo "Requests served by each slot:   blue=$B1  green=$G1"
echo
echo "### 2. CUTOVER  ->  ./deployment/switch_traffic.sh green"
echo "    (a continuous request loop runs across the cutover to measure downtime)"
( for _ in $(seq 600); do
    curl -s -A "$UA" -o /dev/null -w "%{http_code}\n" --max-time 2 "$PROXY_URL/health"
  done > "$POLL_FILE" 2>&1 ) &
POLL=$!
./deployment/switch_traffic.sh green 2>&1
wait "$POLL"
echo
echo "Zero-downtime measurement across the cutover window:"
echo "  requests sent  : $(wc -l < "$POLL_FILE")"
echo "  HTTP 200       : $(grep -c '^200$' "$POLL_FILE" || true)"
echo "  failed/non-200 : $(grep -vc '^200$' "$POLL_FILE" || true)"
echo
echo "### 3. AFTER cutover — green is live"
grep "server wine-api" deployment/nginx.conf
B2=$(slotcount blue); G2=$(slotcount green)
echo "Requests served during the cutover window:  blue +$((B2-B1))   green +$((G2-G1))"
printf "10 more client requests: "; hit 10
B3=$(slotcount blue); G3=$(slotcount green)
echo "Of those 10:  blue +$((B3-B2))   green +$((G3-G2))   <-- all traffic now on GREEN"
echo
echo "### 4. ROLLBACK  ->  ./deployment/rollback.sh blue"
./deployment/rollback.sh blue 2>&1
echo
grep "server wine-api" deployment/nginx.conf
B4=$(slotcount blue); G4=$(slotcount green)
printf "10 more client requests: "; hit 10
B5=$(slotcount blue); G5=$(slotcount green)
echo "Of those 10:  blue +$((B5-B4))   green +$((G5-G4))   <-- traffic is back on BLUE"
echo
echo "### 5. Service healthy through the proxy after the full round trip"
curl -s "$PROXY_URL/health"; echo
echo "=== End of transcript ==="
} 2>&1 | tee "$OUT"

echo
echo "Transcript written to $OUT"
