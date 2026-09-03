#!/usr/bin/env bash
# exist.test.sh — validate that collabora is operational.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "collabora" EXIST_IS_NAS_COLLABORA
skip_if_disabled
load_env_exist

# Collabora Online (code) listens on :9980. /hosting/discovery is the standard
# WOPI host discovery endpoint and is unauthenticated.
probe_service "collabora /hosting/discovery" collabora 9980 /hosting/discovery 200

# Every action URL in the discovery XML embeds `server_name` verbatim (coolwsd's
# initializeEnvOptions() maps the env var straight to the server_name config key —
# wsd/COOLWSD.cpp). If EXIST_DOMAIN drifted from what Caddy/DNS actually serve, or
# COLLABORA_DOMAIN was set but not re-rendered, the container itself answers fine
# while every urlsrc points at the wrong host and Nextcloud's iframe silently
# fails to load. Confirm the two agree.
_want_domain="${COLLABORA_DOMAIN:-collabora.${EXIST_DOMAIN:-}}"
if [ -n "$_want_domain" ]; then
    _discovery=$(curl -sS --max-time 5 "http://collabora:9980/hosting/discovery" 2>/dev/null || true)
    case "$_discovery" in
        *"$_want_domain"*)
            ok "discovery advertises ${_want_domain}"
            ;;
        *)
            fail "discovery advertises ${_want_domain}" \
                 "no urlsrc in /hosting/discovery names ${_want_domain}" \
                 "Check COLLABORA_DOMAIN/EXIST_DOMAIN and the server_name env in docker-compose.yml, then: docker compose up -d --force-recreate collabora"
            ;;
    esac
else
    skip "discovery advertises the right domain" "EXIST_DOMAIN is unset"
fi

# Admin console (username/password env -> admin_console.username/password,
# same initializeEnvOptions() mapping) is enabled by default in coolwsd.xml.
# Blank creds don't open it up — coolwsd just 401s every request — but they do
# leave it permanently unusable with no obvious symptom short of trying to log in.
env_var_set "collabora admin username" COLLABORA_USERNAME
env_var_set "collabora admin password" COLLABORA_PASSWORD

finish
