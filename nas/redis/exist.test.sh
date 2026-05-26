#!/usr/bin/env bash
# exist.test.sh — validate that redis is operational.
#
# Read-only: PING is the standard liveness command and changes no state.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/lib" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "redis" EXIST_IS_NAS_REDIS
skip_if_disabled

load_env_exist

tcp_probe "redis:6379" redis 6379

# AUTH + PING via raw protocol — avoids depending on redis-cli being in adhoc.
PASS="${EXIST_REDIS_PASSWORD:-}"
if [ -z "$PASS" ]; then
    warn "redis password configured" \
         "EXIST_REDIS_PASSWORD is empty" \
         "Set EXIST_REDIS_PASSWORD in .env.exist and re-run ./existential.sh"
    finish
fi

# Send AUTH <pass>\r\nPING\r\n; expect +PONG anywhere in the response.
RESP=$(printf '*2\r\n$4\r\nAUTH\r\n$%d\r\n%s\r\n*1\r\n$4\r\nPING\r\n' "${#PASS}" "$PASS" \
        | timeout 5 bash -c 'cat >&3; cat <&3' 3<>/dev/tcp/redis/6379 2>/dev/null || true)

if printf '%s' "$RESP" | grep -q '+PONG'; then
    ok "redis AUTH + PING"
elif printf '%s' "$RESP" | grep -q '\-WRONGPASS\|\-ERR invalid password'; then
    fail "redis AUTH + PING" "redis rejected EXIST_REDIS_PASSWORD" \
         "Re-mint EXIST_REDIS_PASSWORD in .env.exist; restart redis"
else
    fail "redis AUTH + PING" "unexpected response (got $(printf '%s' "$RESP" | head -c 60))" \
         "docker logs redis"
fi

finish
