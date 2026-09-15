#!/usr/bin/env bash
# exist.test.sh — validate that nextcloud is operational.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "nextcloud" EXIST_IS_NAS_NEXTCLOUD
skip_if_disabled
load_env_exist

# nextcloud serves on :80. /status.php returns JSON with installed/version info.
probe_service "nextcloud /status.php" nextcloud 80 /status.php 200
tcp_probe     "nextcloud-db:3306"     nextcloud-db 3306

# nextcloud-redis backs file locking and PHP sessions unconditionally (no
# blank-key no-op guard like the S3 vars have), so a dead or mis-authenticating
# redis is a real outage, not a degraded mode. /status.php stays 200 through it
# — it doesn't probe locking — so this is the only thing that catches it.
tcp_probe "nextcloud-redis:6379 (locking/session)" nextcloud-redis 6379

# Port open is not port usable: a re-rendered NEXTCLOUD_REDIS_PASSWORD that
# reached only one of the two containers looks identical until AUTH. Raw
# protocol, so this doesn't depend on redis-cli being in adhoc — send
# AUTH <pass> then PING and expect +PONG anywhere in the response.
REDIS_PASS="${NEXTCLOUD_REDIS_PASSWORD:-}"
if [ -z "$REDIS_PASS" ]; then
    warn "nextcloud-redis password configured" \
         "NEXTCLOUD_REDIS_PASSWORD is empty" \
         "Set it in nas/nextcloud/.env and restart nextcloud-redis"
else
    RESP=$(printf '*2\r\n$4\r\nAUTH\r\n$%d\r\n%s\r\n*1\r\n$4\r\nPING\r\n' \
                  "${#REDIS_PASS}" "$REDIS_PASS" \
            | timeout 5 bash -c 'cat >&3; cat <&3' 3<>/dev/tcp/nextcloud-redis/6379 2>/dev/null || true)
    if printf '%s' "$RESP" | grep -q '+PONG'; then
        ok "nextcloud-redis AUTH + PING"
    elif printf '%s' "$RESP" | grep -q '\-WRONGPASS\|\-ERR invalid password'; then
        fail "nextcloud-redis AUTH + PING" "redis rejected NEXTCLOUD_REDIS_PASSWORD" \
             "Re-mint NEXTCLOUD_REDIS_PASSWORD in nas/nextcloud/.env, then recreate both containers"
    else
        fail "nextcloud-redis AUTH + PING" "unexpected response (got $(printf '%s' "$RESP" | head -c 60))" \
             "docker logs nextcloud-redis"
    fi
fi

# A reachable port is not a usable database: mysql_install_db runs once, so a
# re-render that regenerates NEXTCLOUD_SQL_* leaves the app locked out of its
# own volume. Nextcloud reports that only as a 503 on /status.php.
mysql_auth_probe "nextcloud-db auth" nextcloud-db 3306 \
                 "${NEXTCLOUD_SQL_USER:-}" "${NEXTCLOUD_SQL_PASSWORD:-}" nextcloud

# A 200 on /status.php is NOT proof of a working instance: an *uninstalled*
# nextcloud serves the setup wizard with the same 200 and reports
# "installed":false. That is what a failed auto-install looks like — most often
# a data dir that was not EMPTY at first start: the image's entrypoint.sh only
# rsyncs (and chowns to www-data) a persisted dir — config/data/custom_apps/
# themes — while `directory_empty` sees it as empty, so anything already in
# volumes/nextcloud_data (a stray file, a leftover .gitkeep) makes install skip
# that dir's ownership fix entirely.
STATUS=$(curl -sS --max-time 10 "http://nextcloud:80/status.php" 2>/dev/null || true)
case "$STATUS" in
    *'"installed":true'*)
        ok "nextcloud installed" ;;
    *'"installed":false'*)
        fail "nextcloud installed" "$STATUS" \
             "auto-install failed. Check 'docker logs nextcloud'. 'Cannot create or write into the data directory' means volumes/nextcloud_data was not empty at first start — empty it and recreate. No install attempt at all means /var/www/html/version.php survived from a previous failure, so the entrypoint thinks it is already installed: 'docker exec nextcloud rm -f /var/www/html/version.php && docker restart nextcloud'" ;;
    *)
        fail "nextcloud installed" "${STATUS:-<no response>}" \
             "/status.php did not return the expected JSON" ;;
esac

finish
