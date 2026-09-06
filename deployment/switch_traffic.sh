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
# Must match the host port the proxy is published on (see PROXY_PORT in docker-compose.yml).
PROXY_URL="${PROXY_URL:-http://localhost:8080}"
# `python` is not on PATH on every host; prefer python3.
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

# Refuse to touch nginx.conf unless the proxy is actually running.
#
# This check must come BEFORE rewrite_upstream. Otherwise the config file on
# disk gets rewritten, the `docker compose exec proxy` call then fails with a
# bare `service "proxy" is not running`, and the script exits leaving the file
# claiming one slot is live while nginx (stopped, or still serving the old
# config) says otherwise -- the same disk-vs-runtime inconsistency the inode
# bug caused.
require_proxy_running() {
  if ! docker compose ps --status running --services 2>/dev/null | grep -qx proxy; then
    local port="${PROXY_PORT:-8080}"
    cat >&2 <<EOF
ERROR: the 'proxy' service is not running, so there is no cutover to perform.
       Nothing has been changed.

Start the stack first:

  PROXY_PORT=${port} docker compose up -d

If the proxy then fails with "address already in use", host port ${port} is
taken by something else. Pick a free port and use it consistently:

  export PROXY_PORT=18080 PROXY_URL=http://localhost:18080
  docker compose up -d

Check what came up with:  docker compose ps
EOF
    exit 1
  fi
}


if [[ "$NEW_LIVE_SLOT" != "blue" && "$NEW_LIVE_SLOT" != "green" ]]; then
  echo "Slot must be 'blue' or 'green'"; exit 1
fi

require_proxy_running

echo "== 1/3: Smoke-testing wine-api-${NEW_LIVE_SLOT} directly (pre-cutover) =="
docker compose exec -T "app-${NEW_LIVE_SLOT}" python -c \
  "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health').status==200 else 1)"

echo "== 2/3: Flipping nginx upstream to wine-api-${NEW_LIVE_SLOT} =="
rewrite_upstream "$NEW_LIVE_SLOT" "$NGINX_CONF"

# Validate the config inside the container before reloading. `nginx -t`
# turns a typo into a failed release instead of a downed proxy.
docker compose exec -T proxy nginx -t
docker compose exec -T proxy nginx -s reload

echo "== 3/3: Post-cutover smoke test through the proxy =="
"$PYTHON" tests/smoke_test.py --host "$PROXY_URL"

echo "Cutover complete. Live slot is now: ${NEW_LIVE_SLOT}"
echo "Previous slot is left running for instant rollback: ./deployment/rollback.sh"
