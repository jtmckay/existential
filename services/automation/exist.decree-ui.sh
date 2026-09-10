#!/usr/bin/env bash
# decree — generate a Lowcoder control panel for decree webhook endpoints.
#
# Reads services/automation/webhook/config.yml, authenticates with Lowcoder,
# and creates a new app named "Decree Routines YYYYMMDD_HHMMSS".
# Each run creates a fresh app — re-run freely without losing previous ones.
#
# Run via: ./existential.sh run automation decree-ui
# Runs in existential-adhoc (needs exist network access to lowcoder-api-service).

set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/src/utils/adhoc.sh"
adhoc_self_elevate "${BASH_SOURCE[0]}"

tsx /repo/services/automation/src/decree-ui.ts
