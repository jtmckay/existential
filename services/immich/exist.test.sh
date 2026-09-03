#!/usr/bin/env bash
# exist.test.sh — validate that immich is operational.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "immich" EXIST_IS_SERVICES_IMMICH
skip_if_disabled

# immich-server's /api/server/ping returns {"res":"pong"} when healthy.
# Caddy routes immich.<domain> -> immich-server:2283.
http_probe "immich-server /api/server/ping (direct)" \
           "http://immich-server:2283/api/server/ping" 200
probe_caddy "immich-server /api/server/ping" immich /api/server/ping 200

# Container_name shape differs between the template (immich-server) and the
# upstream-style rendered compose (immich_server). The upstream-style version
# uses underscores when env_file sets COMPOSE_PROJECT_NAME=immich.
# We only check the conventional dash form — that's what the project uses.

# immich-machine-learning is a separate container nothing else here probes,
# and nothing depends_on it. immich-server calls it lazily, per job (CLIP
# embedding, face detection, OCR) — with it dead, /api/server/ping above
# stays a clean 200 and smart search / facial recognition / OCR just fail one
# job at a time with "fetch failed" in the server's logs (reproduced by
# pointing a test server at a nonexistent ML host). No Caddy route either —
# internal-only. GET /ping is what its own healthcheck.py polls.
http_probe "immich-machine-learning /ping (direct)" \
           "http://immich-machine-learning:3003/ping" 200

# immich-postgres — prove the rendered credentials actually authenticate
# (not just that the port is open; see pg_auth_probe's own header comment
# in exist-test.sh for why TCP, not the container's trust-auth socket).
pg_auth_probe "immich-postgres auth" immich-postgres 5432 \
              "${DB_USERNAME:-}" "${DB_PASSWORD:-}" "${DB_DATABASE_NAME:-immich}"

# The whole reason immich-postgres isn't a stock postgres/pgvector image:
# InitialMigration.js runs `CREATE EXTENSION vchord` and indexes smart-search
# / face embeddings `USING vchordrq` (immich-server dist/utils/database.js) —
# an access method plain pgvector doesn't ship. A bare TCP or pg_isready
# probe can't tell "right image, migrated" from "wrong image, still
# accepting connections"; only a live query of pg_extension can.
_vchord=$(PGPASSWORD="${DB_PASSWORD:-}" PGCONNECT_TIMEOUT=5 \
          psql -h immich-postgres -p 5432 -U "${DB_USERNAME:-}" -d "${DB_DATABASE_NAME:-immich}" -tAc \
          "select 1 from pg_extension where extname = 'vchord'" 2>/dev/null || echo "")
if [ "$_vchord" = "1" ]; then
    ok "immich-postgres vchord extension"
elif [ -z "$_vchord" ]; then
    skip "immich-postgres vchord extension" "could not query pg_extension — see the auth probe above"
else
    fail "immich-postgres vchord extension" "pg_extension has no 'vchord' row" \
         "Wrong postgres image (needs ghcr.io/immich-app/postgres:*-vectorchord*), or InitialMigration hasn't run yet — check: docker logs immich-server | grep -i migration"
fi

# immich-redis — job queue for the background workers (imports, thumbnails).
tcp_probe "immich-redis:6379" immich-redis 6379

finish
