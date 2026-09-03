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

# redis is nas/redis, a separate toggleable service — REDIS_HOST=redis in the
# compose environment is unconditional (no blank-key no-op guard like the S3
# vars have), so a disabled or dead redis is a real outage for nextcloud's file
# locking and PHP sessions, not a degraded mode. /status.php stays 200 through
# it (it doesn't probe locking), so this is the only thing that catches it.
# Service-scoped: just flags the dependency — redis's own exist.test.sh does
# the AUTH+PING check.
tcp_probe "redis:6379 (nextcloud locking/session)" redis 6379

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
