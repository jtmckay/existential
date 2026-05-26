#!/usr/bin/env bash
# exist.test.sh — validate that the decree stack is operational.
#
# Covers decree, decree-backup, and decree-webhook. decree and decree-backup
# are daemons (no HTTP listener); the webhook fronts both indirectly via the
# shared inbox. A working /healthz on the webhook is the cleanest available
# liveness signal without poking docker socket / writing to the inbox.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/lib" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "decree" EXIST_IS_SERVICES_DECREE
skip_if_disabled

load_env_exist

# ── 1. Webhook health ────────────────────────────────────────────────────────

WEBHOOK_PORT="${DECREE_WEBHOOK_PORT:-3000}"
probe_service "decree-webhook /healthz" decree-webhook "${WEBHOOK_PORT}" /healthz 200

# ── 2. Working tree mounts (decree reads from /work/.decree) ─────────────────

file_present "automations/config.yml"            "/repo/automations/config.yml"
file_present "automations/inbox/ present"        "/repo/automations/inbox"
file_present "automations/runs/ present"         "/repo/automations/runs"

# ── 3. decree-backup has its own working tree ────────────────────────────────

file_present "decree-backup/config.yml"          "/repo/services/decree/decree-backup/config.yml"
file_present "decree-backup/cron/ present"       "/repo/services/decree/decree-backup/cron"

finish
