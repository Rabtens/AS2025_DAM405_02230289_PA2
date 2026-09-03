#!/usr/bin/env bash
# switch_traffic.sh — perform the blue-green cutover for one release.
#
# Flow:
#   1. Deploy the new image into the *idle* slot only (traffic still on old slot).
#   2. Run the smoke test against the idle slot directly (bypassing the proxy).
#   3. If it passes, flip deployment/nginx.conf to point at the idle slot and
#      reload nginx — this is the actual cutover, and it is atomic from the
#      client's point of view (no dropped connections, no restart).
#   4. Keep the old slot running (do not remove it) so step 5 (rollback) is
#      just re-flipping the config back.
#
# Usage: ./deployment/switch_traffic.sh <blue|green>   # slot to make live

set -euo pipefail
NEW_LIVE_SLOT="${1:?Usage: switch_traffic.sh <blue|green>}"
NGINX_CONF="deployment/nginx.conf"

if [[ "$NEW_LIVE_SLOT" != "blue" && "$NEW_LIVE_SLOT" != "green" ]]; then
  echo "Slot must be 'blue' or 'green'"; exit 1
fi

echo "== 1/3: Smoke-testing wine-api-${NEW_LIVE_SLOT} directly (pre-cutover) =="
docker compose exec -T "app-${NEW_LIVE_SLOT}" python -c \
  "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health').status==200 else 1)"

echo "== 2/3: Flipping nginx upstream to wine-api-${NEW_LIVE_SLOT} =="
sed -i.bak -E "s/server wine-api-(blue|green):8000;/server wine-api-${NEW_LIVE_SLOT}:8000;/" "$NGINX_CONF"
docker compose exec proxy nginx -s reload

echo "== 3/3: Post-cutover smoke test through the proxy =="
python tests/smoke_test.py --host http://localhost:8080

echo "Cutover complete. Live slot is now: ${NEW_LIVE_SLOT}"
echo "Previous slot is left running for instant rollback: ./deployment/rollback.sh"
