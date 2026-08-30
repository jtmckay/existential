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

# A reachable port is not a usable database: mysql_install_db runs once, so a
# re-render that regenerates NEXTCLOUD_SQL_* leaves the app locked out of its
# own volume. Nextcloud reports that only as a 503 on /status.php.
mysql_auth_probe "nextcloud-db auth" nextcloud-db 3306 \
                 "${NEXTCLOUD_SQL_USER:-}" "${NEXTCLOUD_SQL_PASSWORD:-}" nextcloud

# A 200 on /status.php is NOT proof of a working instance: an *uninstalled*
# nextcloud serves the setup wizard with the same 200 and reports
# "installed":false. That is what a failed auto-install looks like — most often
# a data dir the entrypoint could not chown to www-data (see exist.initial.sh).
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
