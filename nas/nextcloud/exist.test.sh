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

finish
