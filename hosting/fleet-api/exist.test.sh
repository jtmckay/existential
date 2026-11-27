#!/usr/bin/env bash
# exist.test.sh — validate fleet-api, a GPU box's lease API.
#
# Read-only: an authenticated POST queues a lease for the host daemon to act on, so this
# probes only /healthz and that a request without the fleet secret is refused.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "fleet-api" EXIST_IS_HOSTING_FLEET_API
skip_if_disabled

API="http://fleet-api:8801"
http_probe "fleet-api /healthz" "${API}/healthz" 200
# 429 too: a request without the secret counts against decree-go-rest's failure rate limit.
http_probe_any "fleet-api refuses a lease without the fleet secret" "${API}/gpu/llm/exist-test" '^(401|429)$' 5 -X POST

finish
