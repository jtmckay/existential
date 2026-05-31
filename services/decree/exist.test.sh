#!/usr/bin/env bash
# exist.test.sh — validate that the decree stack is operational.
#
# Covers decree and decree-webhook. decree is a daemon (no HTTP listener);
# the webhook fronts it via the shared inbox. A working /healthz on the
# webhook is the cleanest available liveness signal without poking docker
# socket / writing to the inbox.
#
# Per-service decree sidecars (mealie-decree, portainer-decree, etc.) are
# validated by their respective service's exist.test.sh, not here.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "decree" EXIST_IS_SERVICES_DECREE
skip_if_disabled

load_env_exist

# ── 1. Webhook health ────────────────────────────────────────────────────────

WEBHOOK_PORT="${DECREE_WEBHOOK_PORT:-3000}"
probe_service "decree-webhook /healthz" decree-webhook "${WEBHOOK_PORT}" /healthz 200

# ── 2. Main decree working tree mounts ───────────────────────────────────────

file_present "decree/config.yml"                 "/repo/services/decree/decree/config.yml"
file_present "automations/runs/ present"         "/repo/automations/runs"
file_present "automations/shared_routines/ present"     "/repo/automations/shared_routines"
file_present "automations/lib/ present"          "/repo/automations/lib"

finish
