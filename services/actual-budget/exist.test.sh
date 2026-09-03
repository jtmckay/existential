#!/usr/bin/env bash
# exist.test.sh — validate that actual-budget is operational.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "actual-budget" EXIST_IS_SERVICES_ACTUAL_BUDGET
skip_if_disabled

# Actual server listens on :5006. /health is a static liveness ping — its
# handler (chunks/app-*.js: `app.get("/health", (_req,res)=>res.send({status:
# "UP"}))`) never touches the data dir or the DB, so it stays green even with a
# missing/broken /data mount. /account/needs-bootstrap instead runs a real
# `SELECT * FROM auth` against the account.sqlite in /data (account-db-*.js),
# so a bad bind mount or a corrupted account DB fails here.
probe_service "actual-budget /account/needs-bootstrap" actual-budget 5006 /account/needs-bootstrap 200

# Warn (don't fail) when the server has never had a password set. A
# not-yet-bootstrapped actual-budget answers every route above 200 forever —
# the login password is set once via the web UI's first visit or
# `./existential.sh run actual-budget setup`, and a skipped/forgotten step is
# otherwise silent. Read-only: GET only.
_bootstrap=$(curl -sS --max-time 5 "http://actual-budget:5006/account/needs-bootstrap" 2>/dev/null)
if [ -z "$_bootstrap" ]; then
    skip "actual-budget server password set" "could not reach actual-budget:5006"
elif printf '%s' "$_bootstrap" | grep -q '"bootstrapped":true'; then
    ok "actual-budget server password set"
else
    warn "actual-budget server password set" \
         "needs-bootstrap still true — no login password has ever been set" \
         "Visit https://actual-budget.\${EXIST_DOMAIN} to set one, or run: ./existential.sh run actual-budget setup"
fi

finish
