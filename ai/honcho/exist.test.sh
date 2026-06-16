#!/usr/bin/env bash
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "honcho" EXIST_IS_AI_HONCHO
skip_if_disabled

probe_caddy "honcho" "honcho:8000"

# FastAPI health endpoint
http_probe "honcho /health" "http://honcho:8000/health"

# Postgres is healthy (honcho depends_on it, but confirm independently)
probe_service "honcho-postgres" honcho-postgres 5432

finish
