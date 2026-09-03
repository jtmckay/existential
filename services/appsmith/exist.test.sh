#!/usr/bin/env bash
# exist.test.sh — validate that appsmith is operational.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "appsmith" EXIST_IS_SERVICES_APPSMITH
skip_if_disabled

# Appsmith CE serves the UI on :80 via its bundled Caddy (the "editor" process
# in `supervisorctl status` — not nginx). This is Caddy's static SPA shell,
# which answers 200 the instant Caddy itself is up — verified against a real
# boot: it stayed 200 across the whole ~50s window the backend was still
# starting. It proves the container is reachable, nothing about the backend
# or the three embedded datastores underneath it.
probe_service_any "appsmith UI"             appsmith 80 /                  "^(200|301|302|307)$"

# 200, not 401: this endpoint never rejects an unauthenticated caller — it
# answers with the anonymous user
#   {"responseMeta":{"status":200,...},"data":{"email":"anonymousUser",
#    "isAnonymous":true,"isEmptyInstance":true,...}}
# so the old 401 expectation could not have passed against any appsmith. It went
# unnoticed because this quest kept failing at the container-health gate before
# the service tests ran.
#
# This is also the one check here that actually exercises the backend and its
# two required embedded datastores, not just Caddy. Verified directly against
# a running container:
#   - During boot, Caddy proxies this path to the Java backend on :8080 and
#     gets 502 until the backend is listening (~50s on a fresh install) — the
#     UI probe above stays 200 throughout, so this is what separates "still
#     booting" from actually serving.
#   - `supervisorctl stop mongodb` (or `redis`) makes this endpoint 500 within
#     seconds. Appsmith's own baked HEALTHCHECK does NOT catch either: its
#     script (/opt/appsmith/healthcheck.sh) only checks that the
#     editor/rts/backend supervisor processes are RUNNING plus a plain GET to
#     "/" — the branches that look like they ping mongo/redis and curl the
#     backend's own /api/v1/health match on process names "mongo"/"redis"/
#     "server", which is not what supervisord actually calls them
#     ("mongodb"/"redis"/"backend"), so those branches never run. `docker
#     inspect` reported "healthy" the entire time mongo was down in testing.
#     This probe is the real signal for both databases.
#   - `supervisorctl stop postgres` does NOT affect this endpoint — Postgres
#     only backs the optional "mockdb" sample datasource, queried lazily, so
#     there is no cheap read-only way to probe it from outside. A dead mockdb
#     Postgres is a real gap this suite does not cover.
probe_service     "appsmith /api/v1/users/me" appsmith 80 /api/v1/users/me 200

# APPSMITH_ADMIN_EMAILS backs the real `admin.emails` Spring property (grants
# instance-admin on signup) but is easy to leave silently unwired — this
# service's docker-compose.exist.yml had no environment:/env_file: entry for
# it at all until this review, so the value rendered into .env.exist never
# reached the container. Catches that class of regression again.
env_var_set "appsmith admin email" APPSMITH_ADMIN_EMAILS

finish
