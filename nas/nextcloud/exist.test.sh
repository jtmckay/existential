#!/usr/bin/env bash
# exist.test.sh — validate that nextcloud is operational.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "nextcloud" EXIST_IS_NAS_NEXTCLOUD
skip_if_disabled

# nextcloud serves on :80. /status.php returns JSON with installed/version info.
probe_service "nextcloud /status.php" nextcloud 80 /status.php 200
tcp_probe     "nextcloud-db:3306"     nextcloud-db 3306

finish
