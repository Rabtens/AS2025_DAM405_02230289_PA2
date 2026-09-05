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
# Must match the host port the proxy is published on (see PROXY_PORT in docker-compose.yml).
PROXY_URL="${PROXY_URL:-http://localhost:8080}"
PYTHON="${PYTHON:-python3}"
# Rewrite the upstream line in place, preserving the file's inode.
#
# NOTE: `sed -i` must NOT be used here. It writes a temporary file and renames
# it over the target, which allocates a new inode. deployment/nginx.conf is
# bind-mounted as a *single file* into the proxy container, so the container
# would go on reading the original inode: the config on disk would look
# switched while nginx kept serving the old slot -- a cutover that silently
# does nothing. Truncate-and-rewrite (`> "$file"`) keeps the same inode and is
# therefore visible inside the container.
rewrite_upstream() {
  local slot="$1" file="$2" tmp
  tmp="$(mktemp)"
  # '@' delimiter: the pattern contains '|' for the blue/green alternation.
  sed -E "s@^([[:space:]]*)server wine-api-(blue|green):8000;.*@\\1server wine-api-${slot}:8000;   # <- currently live slot@" \
      "$file" > "$tmp"
  cat "$tmp" > "$file"          # truncate + rewrite: same inode, mount stays valid
  rm -f "$tmp"
}


echo "== Rolling back: pointing nginx upstream back to wine-api-${REVERT_TO_SLOT} =="
rewrite_upstream "$REVERT_TO_SLOT" "$NGINX_CONF"
docker compose exec -T proxy nginx -t
docker compose exec -T proxy nginx -s reload

echo "== Verifying rollback =="
"$PYTHON" tests/smoke_test.py --host "$PROXY_URL"

echo "Rollback complete. Live slot is now: ${REVERT_TO_SLOT}"
