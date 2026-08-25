#!/usr/bin/env bash
# exist.test.sh — validate that dashy is operational.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "dashy" EXIST_IS_SERVICES_DASHY
skip_if_disabled

# dashy serves the static dashboard on :8080.
probe_service "dashy UI" dashy 8080 / 200

# The config file is mounted at /app/user-data/conf.yml. If it's not readable
# (typo / bad mount), dashy still serves but shows the default landing page.
_CONF="/repo/services/dashy/dashy-conf.yml"
file_present "dashy-conf.yml present" "$_CONF"

# dashy-conf.yml is regenerated on every ./existential.sh run precisely so its
# URLs can't go stale. These checks make that guarantee observable: a config
# baked against an old EXIST_DOMAIN points every tile at a domain that no longer
# resolves, and dashy will serve it without complaint.
if [ -f "$_CONF" ]; then
    if grep -q 'EXIST_DOMAIN' "$_CONF"; then
        fail "dashy-conf.yml placeholders resolved" \
             "literal EXIST_DOMAIN token left in $_CONF" \
             "Re-run ./existential.sh — the render failed to substitute EXIST_DOMAIN"
    else
        ok "dashy-conf.yml placeholders resolved"
    fi

    _dom="${EXIST_DOMAIN:-x.internal}"
    if grep -q "\.${_dom}" "$_CONF"; then
        ok "dashy-conf.yml matches EXIST_DOMAIN (${_dom})"
    else
        fail "dashy-conf.yml matches EXIST_DOMAIN (${_dom})" \
             "no URL in $_CONF uses .${_dom} — the config is stale" \
             "Run ./existential.sh (no --force needed) to regenerate it"
    fi
fi

finish
