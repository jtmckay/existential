#!/usr/bin/env bash
# exist.test.sh — validate that portainer is operational.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "portainer" EXIST_IS_HOSTING_PORTAINER
skip_if_disabled

# Portainer serves an HTTPS UI on :9443 with a self-signed cert (so -k).
# Caddy fronts portainer.<domain> -> https://portainer:9443; the caddy probe
# below tests that routing leg without needing -k itself (probe_caddy already
# does so for caddy's own <domain> cert).
#
# /api/status answers before portainer ever touches docker.sock or the admin
# password file — it proves only that the HTTPS server accepted a connection,
# not that anyone can log in or that portainer can actually manage the daemon
# it exists for. (A portainer given no docker.sock at all doesn't even get this
# far — verified it refuses to start with a fatal "Unable to locate Unix socket
# or named pipe", which the host container-state gate already catches as a
# crash loop.) What that gate does NOT catch is portainer running fine while
# the two things below are silently broken.
http_probe "portainer /api/status (direct)" \
           "https://portainer:9443/api/status" 200 5 -k
probe_caddy "portainer /api/status" portainer /api/status 200

# The seeded-admin pipeline: templates.sh renders portainer_password.txt from
# EXIST_PASSWORD, the file is bind-mounted read-only, and --admin-password-file
# feeds it to the distroless entrypoint on first boot only (verified via
# container logs: every boot after the first logs "instance already has an
# administrator user defined, skipping admin password related flags" and never
# rereads the file). /api/status can't see any of that breaking — log in with
# the documented credentials for real.
#
# A login failure here is NOT necessarily the service being broken: it is also
# what a deliberate password change via the UI looks like (expected — see the
# one-time-seed note in docker-compose.exist.yml), so this warns rather than
# fails and says so.
load_env_exist
_auth_resp=$(curl -sS -k --max-time 5 -X POST "https://portainer:9443/api/auth" \
                  -H "Content-Type: application/json" \
                  -d "{\"username\":\"admin\",\"password\":\"${EXIST_PASSWORD:-}\"}" 2>/dev/null || true)
_jwt=$(printf '%s' "$_auth_resp" | jq -r '.jwt // empty' 2>/dev/null || true)
if [ -z "$_jwt" ]; then
    warn "portainer admin login (EXIST_PASSWORD)" \
         "POST /api/auth as admin/\$EXIST_PASSWORD did not return a jwt: ${_auth_resp:-<no response>}" \
         "Expected if the password was changed via the UI after first boot (the seed file is then permanently ignored — see docker-compose.exist.yml). Otherwise check: docker logs portainer"
else
    ok "portainer admin login (EXIST_PASSWORD)"

    # The actual reason this container exists: can it manage the local Docker
    # environment? Status is portainer's own live read on that connection (1 =
    # up), refreshed each environment snapshot — not just "the endpoint object
    # exists in the DB". Verified end-to-end separately: authenticating this way
    # and driving POST .../docker/containers/create through this same API path
    # created a real container on the host.
    _status=$(curl -sS -k --max-time 5 "https://portainer:9443/api/endpoints/1" \
                    -H "Authorization: Bearer ${_jwt}" 2>/dev/null \
              | jq -r '.Status // empty' 2>/dev/null || true)
    if [ "$_status" = "1" ]; then
        ok "portainer local Docker endpoint up"
    else
        fail "portainer local Docker endpoint up" \
             "GET /api/endpoints/1 Status=${_status:-<none>} (expected 1)" \
             "portainer is up but can't reach docker.sock. Check the socket mount and that it's still readable: docker logs portainer"
    fi
fi

finish
