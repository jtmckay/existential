#!/usr/bin/env bash
# exist.test.sh — validate that immich is operational.
#
# See CLAUDE.md "Service test scripts" for the convention.

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

finish
