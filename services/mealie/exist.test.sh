#!/usr/bin/env bash
# exist.test.sh — validate that mealie is operational.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "mealie" EXIST_IS_SERVICES_MEALIE
skip_if_disabled
load_env_exist

# mealie serves the UI + API on :9000. /api/app/about is unauthenticated but not
# a shallow liveness check: verified against the real route (app_about.py) it
# opens a DB session and queries the `groups` table on every call — the same
# endpoint the image's own baked healthcheck.sh curls. A DOWN postgres or a bad
# POSTGRES_* value fails this, not just a dead mealie process.
probe_service "mealie /api/app/about" mealie 9000 /api/app/about 200

# tcp_probe, not probe_service: 5432 speaks the postgres wire protocol, not
# HTTP, and there is no Caddy vhost for it.
tcp_probe "mealie-postgres:5432" mealie-postgres 5432

# ...and that the rendered password still authenticates. A postgres image
# bootstraps its role/password ONCE against an empty data dir — after that,
# POSTGRES_PASSWORD in compose is inert, so a re-render that regenerates
# MEALIE_POSTGRES_PASSWORD silently locks mealie out of its existing volume
# (the /api/app/about probe above would also start failing, but this pins the
# cause to credentials rather than "something about postgres is wrong").
pg_auth_probe "mealie-postgres auth" mealie-postgres 5432 \
              "${MEALIE_POSTGRES_USER:-}" "${MEALIE_POSTGRES_PASSWORD:-}" mealie

finish
