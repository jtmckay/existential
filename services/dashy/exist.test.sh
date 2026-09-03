#!/usr/bin/env bash
# exist.test.sh — validate that dashy is operational.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "dashy" EXIST_IS_SERVICES_DASHY
skip_if_disabled

# dashy serves the built Vue SPA on :8080 regardless of whether its config
# loaded: config-validator.js wraps the read+parse in try/catch and only logs
# a warning on failure (services/utils/config-validator.js), and /healthz is a
# hardcoded 200 registered before any of that runs (services/app.js:226). So
# neither the image's own healthcheck nor a plain "/" probe can tell a working
# dashboard from a broken config mount — verified against lissy93/dashy:4.5.0:
# with conf.yml unreadable to the container's uid, / and /healthz both kept
# answering 200 while the dashboard silently had no tiles.
probe_service "dashy UI" dashy 8080 / 200

# The config dashy actually reads is bind-mounted read-only at
# /app/user-data/conf.yml, and dashy serves that exact file back verbatim via
# express.static at /conf.yml (services/app.js). That route is the one place
# to prove the CONTAINER can read the mount — /conf.yml 404s if it can't
# (permission drift, a bad :Z SELinux label), which is exactly the failure
# the checks below need to catch.
probe_service "dashy serves conf.yml" dashy 8080 /conf.yml 200

_CONF="/repo/services/dashy/dashy-conf.yml"
file_present "dashy-conf.yml present" "$_CONF"

# dashy-conf.yml is regenerated on every ./existential.sh run precisely so its
# URLs can't go stale. Check what dashy is actually SERVING, not the host
# copy — a container that hasn't picked up a re-render (e.g. still running
# against an old bind after a rename) would pass a host-file check and fail
# this one.
_SERVED=$(curl -sS --max-time 5 "http://dashy:8080/conf.yml" 2>/dev/null || true)

if [ -z "$_SERVED" ]; then
    skip "dashy-conf.yml placeholders resolved" "could not fetch http://dashy:8080/conf.yml"
    skip "dashy-conf.yml matches EXIST_DOMAIN"   "could not fetch http://dashy:8080/conf.yml"
elif printf '%s' "$_SERVED" | grep -q 'EXIST_DOMAIN'; then
    fail "dashy-conf.yml placeholders resolved" \
         "literal EXIST_DOMAIN token left in the config dashy is serving" \
         "Re-run ./existential.sh — the render failed to substitute EXIST_DOMAIN"
else
    ok "dashy-conf.yml placeholders resolved"

    _dom="${EXIST_DOMAIN:-x.internal}"
    if printf '%s' "$_SERVED" | grep -q "\.${_dom}"; then
        ok "dashy-conf.yml matches EXIST_DOMAIN (${_dom})"
    else
        fail "dashy-conf.yml matches EXIST_DOMAIN (${_dom})" \
             "no URL in the config dashy is serving uses .${_dom} — stale mount or stale render" \
             "Run ./existential.sh to regenerate it, then: docker compose up -d dashy"
    fi
fi

finish
