#!/usr/bin/env bash
# exist.test.sh — validate that collabora is operational.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "collabora" EXIST_IS_NAS_COLLABORA
skip_if_disabled

# Collabora Online (code) listens on :9980. /hosting/discovery is the standard
# WOPI host discovery endpoint and is unauthenticated.
probe_service "collabora /hosting/discovery" collabora 9980 /hosting/discovery 200

finish
