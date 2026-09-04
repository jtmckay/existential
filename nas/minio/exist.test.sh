#!/usr/bin/env bash
# exist.test.sh — validate that minio is operational.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "minio" EXIST_IS_NAS_MINIO
skip_if_disabled

# MinIO S3 API on :9000 (caddy: minio-api.<domain> -> minio:9000),
# console on :9001 (caddy: minio.<domain> -> minio:9001).
# /minio/health/live is unauthenticated, but it proves only that the HTTP
# server is accepting connections: LivenessCheckHandler (cmd/healthcheck-
# handler.go:192-211 in the minio source) returns 200 unconditionally unless
# the request queue is over capacity -- it never checks the object layer, IAM,
# or the root credentials. A minio whose root password does not match what
# every migration/routine reads from .env would still pass both probes below.
http_probe "minio S3 /minio/health/live (direct)" "http://minio:9000/minio/health/live" 200
probe_caddy "minio S3 /minio/health/live" minio-api /minio/health/live 200

http_probe_any "minio console (direct)" "http://minio:9001/" "^(200|301|302|307)$"
probe_caddy_any "minio console" minio / "^(200|301|302|307)$"

# Root credentials actually authenticate. Uses the MC_HOST_<alias> env form
# (URL-embedded creds, no ~/.mc/config.json alias written) -- the same
# pattern automation/shared_routines/minio-service-account.sh uses. `mc ls`
# is a read-only ListBuckets call, so this proves the live .env values work
# without writing anything to the service.
if command -v mc >/dev/null 2>&1; then
    load_env_exist
    export MC_HOST_minio="http://${MINIO_ROOT_USER:-}:${MINIO_ROOT_PASSWORD:-}@minio:9000"
    if mc ls minio >/dev/null 2>&1; then
        ok "minio root credentials authenticate"
    else
        fail "minio root credentials authenticate" \
             "mc could not list buckets as MINIO_ROOT_USER" \
             "Check MINIO_ROOT_USER/MINIO_ROOT_PASSWORD in nas/minio/.env against docker logs minio"
    fi
    unset MC_HOST_minio
else
    skip "minio root credentials authenticate" "mc not installed in this container"
fi

finish
