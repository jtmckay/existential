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
# the whole workspace, reach the gateway and run whatever is installed in it, so an empty password is a
# real exposure, not just a broken login. Verify root really is gated behind
# it (302 to /login, not a 200 straight into the IDE) rather than trusting the
# flag was honored.
env_var_set "code-server password" CODE_SERVER_PASSWORD
probe_service "code-server auth gate" code-server 8080 / 302

# entrypoint.sh symlinks the `hermes` command in the integrated terminal to
# /opt/hermes/hermes-cli.sh, which is a read-only bind of automation/lib/. A
# missing source is the one failure mode that stays silent: docker materialises
# an empty directory for it, the `-x` guard in entrypoint.sh then fails quietly,
# and the terminal just has no `hermes`. Read-only: check the mount sources on
# disk rather than reaching into the container.
for _src in automation/lib/hermes-cli.sh automation/lib/hermes.sh; do
    if [ ! -f "/repo/${_src}" ]; then
        fail "code-server ${_src} mounted" "/repo/${_src} is missing" \
             "The compose file binds it read-only into /opt/hermes — restore it and recreate the container"
    elif [ "${_src}" = "automation/lib/hermes-cli.sh" ] && [ ! -x "/repo/${_src}" ]; then
        fail "code-server ${_src} mounted" "/repo/${_src} is not executable" \
             "entrypoint.sh only links it onto PATH when it is: chmod 755 ${_src}"
    else
        ok "code-server ${_src} mounted"
    fi
done

finish
