#!/usr/bin/env bash
# exist.test.sh — validate that minio is operational.
#
# See CLAUDE.md "Service test scripts" for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "minio" EXIST_IS_NAS_MINIO
skip_if_disabled

# MinIO S3 API on :9000 (caddy: minio-api.<domain> -> minio:9000),
# console on :9001 (caddy: minio.<domain> -> minio:9001).
# /minio/health/live is unauthenticated.
http_probe "minio S3 /minio/health/live (direct)" "http://minio:9000/minio/health/live" 200
probe_caddy "minio S3 /minio/health/live" minio-api /minio/health/live 200

http_probe_any "minio console (direct)" "http://minio:9001/" "^(200|301|302|307)$"
probe_caddy_any "minio console" minio / "^(200|301|302|307)$"

finish
