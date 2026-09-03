#!/usr/bin/env bash
# exist.test.sh — validate that nocodb is operational.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "nocodb" EXIST_IS_SERVICES_NOCODB
skip_if_disabled

# nocodb serves the UI + API on :8080.
probe_service_any "nocodb UI" nocodb 8080 / "^(200|301|302|307)$"

# /api/v1/health is a hardcoded {"message":"OK",...} — no DB touch at all
# (verified: stays 200 with nocodb-postgres stopped), so it can't tell a working
# install from one whose metadata DB is unreachable. /api/v1/db/meta/nocodb/info
# is unauthenticated but reads baseHasAdmin/connectToExternalDB through postgres,
# so it 400s with ERR_DATABASE_OP_FAILED the moment the DB drops (verified) and
# is what's actually worth gating on. Cold boot (fresh volumes, first-run schema
# migrations) measured ~15-16s before this answers, so the retry budget is
# widened rather than reusing the 8x2s default.
EXIST_PROBE_RETRIES=30 \
  probe_service "nocodb DB readiness" nocodb 8080 /api/v1/db/meta/nocodb/info 200

# nocodb-postgres only reads POSTGRES_USER/PASSWORD at first initdb — a later
# credential change (regenerated .env, a restored archive/) drifts silently from
# what's already on disk. A bare TCP probe can't see that; only an authenticated
# connect can.
pg_auth_probe "nocodb-postgres auth" nocodb-postgres 5432 \
              "${NOCODB_POSTGRES_USER:-}" "${NOCODB_POSTGRES_PASSWORD:-}" nocodb

finish
