#!/usr/bin/env bash
# decree — generate a Lowcoder control panel for decree webhook endpoints.
#
# Reads services/decree/webhook/config.yml, authenticates with Lowcoder,
# and creates a new app named "Decree Routines YYYYMMDD_HHMMSS".
# Each run creates a fresh app — re-run freely without losing previous ones.
#
# Run via: ./existential.sh run decree decree-ui
# Runs in existential-adhoc (needs exist network access to lowcoder-api-service).

set -euo pipefail

if [[ -z "${IN_CONTAINER:-}" ]]; then
    _REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    exec docker compose -f "${_REPO}/existential-compose.yml" run --rm -it \
        --entrypoint "" existential-adhoc bash "/repo/services/decree/exist.decree-ui.sh"
fi

tsx /repo/services/decree/src/decree-ui.ts
