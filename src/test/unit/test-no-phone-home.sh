#!/usr/bin/env bash
# test-no-phone-home.sh — every service ships with its telemetry off (migration 015).
#
# One line per upstream setting, read from the tracked template that sets it. A service
# with no setting is recorded on its docs page instead, and the nip.io lookup on the page
# that explains the default domain. The rule itself lives in .claude/reference/services.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
[[ -d "${REPO_DIR}/site/docs" ]] || REPO_DIR="/repo"

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }
# _has <name> <file> <text> — passes when <file> contains <text> verbatim, whitespace collapsed.
_has() {
    if tr -s ' \n' '  ' < "${REPO_DIR}/$2" | grep -qF -- "$3"; then _ok "$1"; else _fail "$1" "missing from $2: $3"; fi
}

# Core
_has "grafana usage stats off"       hosting/grafana/docker-compose.exist.yml  "GF_ANALYTICS_REPORTING_ENABLED=false"
_has "loki usage reporting off"      hosting/loki/loki-config.yaml             "analytics: reporting_enabled: false"
_has "alloy usage reporting off"     hosting/loki/docker-compose.exist.yml     "- --disable-reporting"
_has "code-server telemetry off"     services/code-server/entrypoint.sh        "--disable-telemetry"
_has "claude telemetry off"          services/code-server/docker-compose.exist.yml "DISABLE_TELEMETRY=1"
_has "claude error reporting off"    services/code-server/docker-compose.exist.yml "DISABLE_ERROR_REPORTING=1"
_has "opencode sharing off"          services/code-server/entrypoint.sh        'share: "disabled"'

# Add-ons
_has "nocodb telemetry off"          services/nocodb/docker-compose.exist.yml   'NC_DISABLE_TELE: "true"'
_has "appsmith telemetry off"        services/appsmith/docker-compose.exist.yml 'APPSMITH_DISABLE_TELEMETRY: "true"'
_has "appsmith intercom off"         services/appsmith/docker-compose.exist.yml 'APPSMITH_DISABLE_INTERCOM: "true"'
_has "whisperx pyannote metrics off" ai/whisperx/docker-compose.exist.yml       'PYANNOTE_METRICS_ENABLED: "false"'
_has "whisperx hf telemetry off"     ai/whisperx/docker-compose.exist.yml       'HF_HUB_DISABLE_TELEMETRY: "1"'
_has "chatterbox hf telemetry off"   ai/chatterbox/docker-compose.exist.yml     "HF_HUB_DISABLE_TELEMETRY=1"
_has "wyoming-whisper hf telemetry off" ai/wyoming-whisper/docker-compose.exist.yml 'HF_HUB_DISABLE_TELEMETRY: "1"'
_has "collabora home mode"           nas/collabora/docker-compose.exist.yml     "--o:home_mode.enable=true"
HOOK=nas/nextcloud/hooks/before-starting/03-no-phone-home.sh
_has "nextcloud update check off"    "$HOOK" "config:system:set updatechecker --type=boolean --value=false"
_has "nextcloud survey off"          "$HOOK" "app:disable survey_client"
# The image's run_path skips a hook without the exec bit.
if [[ -x "${REPO_DIR}/$HOOK" ]]; then _ok "nextcloud hook is executable"; else _fail "nextcloud hook is executable"; fi

# No setting upstream: said once, on the docs page
_has "comfyui says it cannot"        site/docs/ai/comfyui.md "upstream offers no setting to turn that off"

# Docs and the rule
_has "nip.io lookup is disclosed"    site/docs/how-it-works.md "nip.io sees your host's IP and each service name you look up"
_has "services.md records the rule"  .claude/reference/services.md "## Telemetry ships off"

[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then
    printf 'Failed: %s\n' "${FAIL_NAMES[*]}"
    exit 1
fi
