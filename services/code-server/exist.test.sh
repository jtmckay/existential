#!/usr/bin/env bash
# exist.test.sh — validate that code-server is fully operational.
#
# See .claude/reference/testing.md for the convention.
# Run via: ./existential.sh run code-server test  (or: ./existential.sh test)

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "code-server" EXIST_IS_SERVICES_CODE_SERVER
skip_if_disabled

# /healthz is unauthenticated and answers 200 as soon as the HTTP server is up
# (verified against v4.135.0: a plain curl with no cookie gets 200 from
# /healthz, vs. a 302-to-/login from / and a 401 from an authenticated route
# like /vscode-remote-resource) — the real "is the process alive" signal, and
# what the container's own healthcheck now uses too (docker-compose.exist.yml).
probe_service "code-server /healthz" code-server 8080 /healthz 200

# CODE_SERVER_PASSWORD is what entrypoint.sh's `--auth password` actually
# checks against ($PASSWORD env). A bare shell in this container can read/write
# the whole workspace and run the installed AI CLIs, so an empty password is a
# real exposure, not just a broken login. Verify root really is gated behind
# it (302 to /login, not a 200 straight into the IDE) rather than trusting the
# flag was honored.
env_var_set "code-server password" CODE_SERVER_PASSWORD
probe_service "code-server auth gate" code-server 8080 / 302

# entrypoint.sh copies opencode.exist.json into workspace/opencode.json only
# once (if it's already there, it's left alone so user edits inside the IDE
# survive a restart) — so an edit to services/code-server/opencode.json after
# that first copy never reaches the running container; it silently keeps
# using the stale profile. Read-only: compare the two rendered files instead
# of touching either.
_ref="/repo/services/code-server/opencode.json"
_ws="/repo/workspace/opencode.json"
if [ ! -f "$_ws" ]; then
    skip "code-server opencode.json in sync" "workspace/opencode.json not created yet — container hasn't started"
elif [ ! -f "$_ref" ]; then
    skip "code-server opencode.json in sync" "$_ref missing — run ./existential.sh to render it"
elif cmp -s "$_ref" "$_ws"; then
    ok "code-server opencode.json in sync"
else
    warn "code-server opencode.json in sync" \
         "workspace/opencode.json differs from the rendered services/code-server/opencode.json" \
         "It's a one-time copy on first container start, not a restart — copy by hand: cp services/code-server/opencode.json workspace/opencode.json"
fi

finish
