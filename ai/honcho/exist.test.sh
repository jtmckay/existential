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

# The deriver is a separate container and nothing depends_on it, so a dead
# honcho-deriver is invisible: the API keeps answering /health and keeps
# enqueueing work that no one consumes, and the user representation quietly
# stops growing. The queue table is the only place that shows it. Read-only.
#
# One hour, not minutes: the deriver makes a real LLM call per task, so a
# genuine backlog on a small card is normal. Nothing at all consumed in an hour
# is not — the worker polls every second (30s max backoff).
#
# This probe is only honest while config.toml keeps FLUSH_ENABLED = true. With
# upstream's default (false) the deriver ignores any representation work unit
# holding under REPRESENTATION_BATCH_MAX_TOKENS, so a short finished session
# sits unprocessed forever and this warns forever about a backlog that cannot
# drain. If you turn flushing off, delete this probe with it.
_stale=$(PGPASSWORD="${HONCHO_POSTGRES_PASSWORD:-}" PGCONNECT_TIMEOUT=5 \
         psql -h honcho-postgres -p 5432 -U honcho -d honcho -tAc \
         "select count(*) from queue where processed = false
           and created_at < now() - interval '1 hour'" 2>/dev/null || echo "")
if [ -z "$_stale" ]; then
    skip "honcho-deriver consuming queue" "could not read the queue table"
elif [ "$_stale" -gt 0 ]; then
    warn "honcho-deriver consuming queue" \
         "${_stale} queue task(s) unprocessed for over an hour" \
         "honcho-deriver is not running: docker compose up -d honcho-deriver (logs: docker logs honcho-deriver)"
else
    ok "honcho-deriver consuming queue"
fi

finish
