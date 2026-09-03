#!/usr/bin/env bash
# rollback.sh — instant rollback to the previously-live slot.
#
# Because the old slot is never torn down during a blue-green cutover
# (see switch_traffic.sh), rollback does not involve rebuilding or
# redeploying anything. It is the same config flip in reverse, so it
# completes in the time it takes nginx to reload (sub-second).
#
# Usage: ./deployment/rollback.sh <blue|green>   # slot to revert to

set -euo pipefail
REVERT_TO_SLOT="${1:?Usage: rollback.sh <blue|green>}"
NGINX_CONF="deployment/nginx.conf"

echo "== Rolling back: pointing nginx upstream back to wine-api-${REVERT_TO_SLOT} =="
sed -i.bak -E "s/server wine-api-(blue|green):8000;/server wine-api-${REVERT_TO_SLOT}:8000;/" "$NGINX_CONF"
docker compose exec proxy nginx -s reload

echo "== Verifying rollback =="
python tests/smoke_test.py --host http://localhost:8080

echo "Rollback complete. Live slot is now: ${REVERT_TO_SLOT}"
