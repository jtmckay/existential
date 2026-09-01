#!/usr/bin/env bash
# exist.test.sh — validate that appsmith is operational.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "appsmith" EXIST_IS_SERVICES_APPSMITH
skip_if_disabled

# Appsmith CE serves the UI on :80 via its embedded nginx.
probe_service_any "appsmith UI"             appsmith 80 /                  "^(200|301|302|307)$"

# 200, not 401: this endpoint never rejects an unauthenticated caller — it
# answers with the anonymous user
#   {"responseMeta":{"status":200,...},"data":{"email":"anonymousUser",
#    "isAnonymous":true,"isEmptyInstance":true,...}}
# so the old 401 expectation could not have passed against any appsmith. It went
# unnoticed because this quest kept failing at the container-health gate before
# the service tests ran.
#
# The check still earns its place, and against the failure that actually happens:
# nginx comes up minutes before the backend does, serving 502 the whole time. The
# UI probe above passes throughout that window, so this is the one assertion that
# separates "appsmith is serving" from "appsmith is still booting or dead".
probe_service     "appsmith /api/v1/users/me" appsmith 80 /api/v1/users/me 200

finish
