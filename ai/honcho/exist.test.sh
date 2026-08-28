#!/usr/bin/env bash
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "honcho" EXIST_IS_AI_HONCHO
skip_if_disabled
load_env_exist

# No probe_caddy: honcho is internal-only — its compose publishes no ports and
# Caddyfile.exist.Caddyfile has no honcho block, so there is no hostname to
# route. Consumers (hermes) reach it at http://honcho:8000 over Docker DNS.

# FastAPI health endpoint
http_probe "honcho /health" "http://honcho:8000/health"

# Postgres is reachable (honcho depends_on it, but confirm independently).
# tcp_probe, not probe_service: 5432 speaks the postgres wire protocol, not
# HTTP, and there is no Caddy vhost for it — an HTTP probe here can only fail.
tcp_probe "honcho-postgres:5432" honcho-postgres 5432

# ...and that the rendered password still authenticates. The role name is
# hardcoded (`honcho`), so only the password can drift — but a re-render that
# regenerates it locks honcho out of an already-initialised volume, and honcho
# then crash-loops on a StartupValidationError that never names the password.
pg_auth_probe "honcho-postgres auth" honcho-postgres 5432 \
              honcho "${HONCHO_POSTGRES_PASSWORD:-}" honcho

finish
