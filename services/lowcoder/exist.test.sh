#!/usr/bin/env bash
# exist.test.sh — validate that the lowcoder stack is operational.
#
# Covers all five containers: lowcoder-frontend (user entry), lowcoder-api-service,
# lowcoder-node-service, lowcoder-mongodb, lowcoder-redis (bundled/dedicated to
# lowcoder — not the shared nas/redis, which only serves nextcloud).
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "lowcoder" EXIST_IS_SERVICES_LOWCODER
skip_if_disabled

# Caddy routes lowcoder.<domain> -> lowcoder-frontend:3000.
http_probe_any "lowcoder-frontend UI (direct)" \
               "http://lowcoder-frontend:3000/" "^(200|301|302|307)$"
probe_caddy_any "lowcoder-frontend UI" lowcoder / "^(200|301|302|307)$"

# api-service and node-service each answer "/" with a fixed JSON status string —
# the same string their own Docker healthcheck greps for (docker-compose.exist.yml).
# A generic 2xx/4xx status range (the previous check here) passes on a wedged JVM
# that still answers HTTP but never finished booting the actual app; this proves
# the real payload instead.
_lc_body_probe() {
    local name="$1" url="$2" needle="$3" timeout="${4:-5}"
    local body
    body=$(curl -sS --max-time "$timeout" "$url" 2>/dev/null || true)
    if [ -z "$body" ]; then
        fail "$name" "no response from $url within ${timeout}s" \
             "Container not running? Check: docker ps | grep ${_SLUG}; logs: docker logs <container>"
    elif [[ "$body" == *"$needle"* ]]; then
        ok "$name"
    else
        fail "$name" "response from $url did not contain '$needle'" \
             "Check logs: docker logs <container>"
    fi
}

_lc_body_probe "lowcoder-api-service health" \
               "http://lowcoder-api-service:8080/" "Lowcoder API is up and runnig"

# Not covered by any probe before this review — a dead node-service is invisible
# to a frontend/api-only test (query execution breaks, everything else stays up).
_lc_body_probe "lowcoder-node-service health" \
               "http://lowcoder-node-service:6060/" "Lowcoder Node Service is up and running"

tcp_probe "lowcoder-mongodb:27017" lowcoder-mongodb 27017
tcp_probe "lowcoder-redis:6379"    lowcoder-redis    6379

# Mongo auth probe — same reasoning as pg_auth_probe/mysql_auth_probe in
# exist-test.sh, inlined here because no shared mongo helper exists. mongo's
# MONGO_INITDB_ROOT_* only seed the root user on a genuinely empty /data/db
# (official image behavior), so a credential rotation in .env that doesn't also
# reset the volume leaves them out of step — tcp_probe above only proves the
# port is open, not that these credentials still authenticate.
#
# mongoexport (mongodb-database-tools, shipped in this image) is used as a
# real, bounded auth check: it performs a genuine authenticated read (output to
# /dev/null — nothing is written) against a collection that need not exist, so
# it exercises auth without depending on lowcoder's internal schema. mongoexport
# ignores its own URI timeout params on a dead connection and hangs, hence the
# outer `timeout`.
if [ -n "${LOWCODER_MONGO_ROOT_PASSWORD:-}" ]; then
    if timeout 10 mongoexport \
        --uri="mongodb://${LOWCODER_MONGO_ROOT_USERNAME}:${LOWCODER_MONGO_ROOT_PASSWORD}@lowcoder-mongodb/lowcoder?authSource=admin" \
        --collection=exist_test_probe --out=/dev/null >/tmp/lowcoder-mongoexport.log 2>&1; then
        ok "lowcoder-mongodb auth"
    else
        fail "lowcoder-mongodb auth" \
             "mongoexport could not authenticate as '${LOWCODER_MONGO_ROOT_USERNAME}': $(tail -1 /tmp/lowcoder-mongoexport.log 2>/dev/null)" \
             "Data volume was initialised with other credentials. Reset the server side to match .env, or recover the old value from archive/<stamp>/ — see .claude/reference/volumes.md"
    fi
else
    skip "lowcoder-mongodb auth" "LOWCODER_MONGO_ROOT_PASSWORD not set"
fi

finish
