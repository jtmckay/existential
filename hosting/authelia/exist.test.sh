#!/usr/bin/env bash
# exist.test.sh — validate that authelia is operational.
#
# See CLAUDE.md "Service test scripts" for the convention. Read-only.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "authelia" EXIST_IS_HOSTING_AUTHELIA
skip_if_disabled

# Authelia serves the portal + API on :9091. /api/health is unauthenticated and
# returns 200 once the server is up and its config validated.
probe_service "authelia /api/health" authelia 9091 /api/health 200

# The file backend needs a generated user DB (see exist.initial.sh). Flag the
# common misconfig where the container is up but no user was minted.
if [[ ! -f "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/users_database.yml" ]]; then
    fail "authelia users_database.yml" \
        "observed: hosting/authelia/users_database.yml missing" \
        "fix: ./existential.sh run (runs exist.initial.sh to mint the initial user)"
fi

finish
