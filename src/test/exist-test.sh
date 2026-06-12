#!/usr/bin/env bash
# exist-test.sh — shared helpers for per-service exist.test.sh scripts.
#
# Usage at the top of every <category>/<slug>/exist.test.sh:
#
#     #!/usr/bin/env bash
#     set -euo pipefail
#     . "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
#     exist_self_elevate              # re-execs in existential-adhoc if needed
#     exist_test_init "<slug>" EXIST_IS_<CATEGORY>_<SLUG>
#     skip_if_disabled
#
#     http_probe "<container>:<port>"  "http://<container>:<port>/health"
#     ...
#
#     finish
#
# Rules (from CLAUDE.md "Service test scripts"):
#   - Read-only. No stacking state. Use HTTP probes / log scans / file inspects.
#     If a write is unavoidable, clean up in a trap and verify cleanup ran.
#   - Service-scoped. Don't cascade into testing dependencies — flag them.
#   - Exit non-zero on failure.
#   - Skip cleanly when EXIST_IS_<CATEGORY>_<SLUG> is not "true".

# ── State ────────────────────────────────────────────────────────────────────
WARNINGS=0
FAILURES=0
_SLUG=""
_ENABLE_VAR=""

# ── Self-elevate into existential-adhoc ──────────────────────────────────────
# Re-execs the calling exist.test.sh inside existential-adhoc when invoked on
# host (so container DNS resolves and /repo is mounted). No-op when already in
# the container (IN_CONTAINER=1). Must be called from the test script itself —
# uses BASH_SOURCE[1] to find the caller's path.
exist_self_elevate() {
    [ -n "${IN_CONTAINER:-}" ] && return 0
    local script repo in_repo_path
    script="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)/$(basename "${BASH_SOURCE[1]}")"
    repo="$(cd "$(dirname "$script")/../.." && pwd)"
    in_repo_path="/repo${script#"$repo"}"
    exec docker compose -f "${repo}/existential-compose.yml" run --rm \
        --entrypoint "" existential-adhoc bash "$in_repo_path"
}

# ── Identity ─────────────────────────────────────────────────────────────────
# Call once after self-elevate (so the banner only prints in the runtime that
# will actually do the work).
exist_test_init() {
    _SLUG="$1"
    _ENABLE_VAR="$2"
    printf '\n=== %s ===\n' "$_SLUG"
}

# ── .env loading ─────────────────────────────────────────────────────────────
_env_loaded=0
load_env_exist() {
    [ "$_env_loaded" = "1" ] && return 0
    if [ -f /repo/.env.shared ]; then
        set -o allexport
        # shellcheck disable=SC1091
        . /repo/.env.shared
        set +o allexport
    fi
    if [ -f /repo/.env ]; then
        set -o allexport
        # shellcheck disable=SC1091
        . /repo/.env
        set +o allexport
    fi
    _env_loaded=1
}

skip_if_disabled() {
    # In a sidecar the service is always enabled — the sidecar wouldn't exist otherwise.
    [ "${DECREE_SIDECAR:-}" = "true" ] && return 0
    load_env_exist
    local val="${!_ENABLE_VAR:-false}"
    if [ "$val" != "true" ]; then
        printf '[%s] skipped — %s is not true (or not set)\n' "$_SLUG" "$_ENABLE_VAR"
        exit 0
    fi
}

# ── Output ───────────────────────────────────────────────────────────────────
_pad() { printf '[%s] %-44s' "$_SLUG" "$1"; }

ok()   { _pad "$1"; printf 'OK\n'; }

fail() {
    _pad "$1"; printf 'FAIL\n'
    [ -n "${2:-}" ] && printf '        observed: %s\n' "$2"
    [ -n "${3:-}" ] && printf '        fix:      %s\n' "$3"
    FAILURES=$((FAILURES + 1))
}

warn() {
    _pad "$1"; printf 'WARN\n'
    [ -n "${2:-}" ] && printf '        observed: %s\n' "$2"
    [ -n "${3:-}" ] && printf '        fix:      %s\n' "$3"
    WARNINGS=$((WARNINGS + 1))
}

# ── Probes ───────────────────────────────────────────────────────────────────

# Fetch the HTTP status code for URL, retrying while the service is still
# starting — 000 (not accepting connections yet) or 503 (up but not ready,
# e.g. Loki replaying its WAL). Real errors (404/500/…) return immediately.
# Container liveness is already proven by the host container-health gate before
# tests run, so a lingering warming-up code here means "warming up", not "down".
# Budget: EXIST_PROBE_RETRIES (default 8) attempts, 2s apart (~16s for slow starts).
# Warming-up codes: EXIST_PROBE_RETRY_CODES (default "000 503"). A probe whose
# readiness endpoint signals not-ready differently can widen the set, e.g.
# promtail's /ready emits a transient 500 on cold start: EXIST_PROBE_RETRY_CODES="000 500 503".
_probe_code() {
    local url="$1" timeout="$2"; shift 2
    local code attempts=0 max="${EXIST_PROBE_RETRIES:-8}"
    local retry_codes=" ${EXIST_PROBE_RETRY_CODES:-000 503} "
    while :; do
        # curl -w prints "000" to stdout on connection failure (and exits non-zero,
        # which $() swallows) — so no "|| echo 000" fallback, which would yield
        # "000000". Normalize an empty capture (curl produced nothing) to "000".
        code=$(curl -sS -o /dev/null -w "%{http_code}" --max-time "$timeout" "$@" "$url" 2>/dev/null)
        code=${code:-000}
        # Stop as soon as we see a code outside the warming-up set.
        case "$retry_codes" in *" $code "*) ;; *) break ;; esac
        attempts=$((attempts + 1))
        [ "$attempts" -ge "$max" ] && break
        sleep 2
    done
    echo "$code"
}

# http_probe NAME URL [EXPECT_STATUS=200] [TIMEOUT=5] [CURL_ARGS...]
# Extra curl args (-H, -k, etc.) come after timeout.
http_probe() {
    local name="$1" url="$2" expect="${3:-200}" timeout="${4:-5}"
    shift 4 2>/dev/null || shift $#
    local code
    code=$(_probe_code "$url" "$timeout" "$@")
    if [ "$code" = "$expect" ]; then
        ok "$name"
    elif [ "$code" = "000" ]; then
        fail "$name" "no response from $url within ${timeout}s" \
             "Container not running? Check: docker ps | grep ${_SLUG}; logs: docker logs <container>"
    else
        fail "$name" "HTTP $code from $url (expected $expect)" \
             "Check logs: docker logs <container>"
    fi
}

# http_probe_any NAME URL EXPECT_REGEX [TIMEOUT=5] [CURL_ARGS...]
# Pass if status code matches the regex (e.g. "^(200|302|401)$" for services that
# require auth at the root URL).
http_probe_any() {
    local name="$1" url="$2" pattern="$3" timeout="${4:-5}"
    shift 4 2>/dev/null || shift $#
    local code
    code=$(_probe_code "$url" "$timeout" "$@")
    if [[ "$code" =~ $pattern ]]; then
        ok "$name"
    elif [ "$code" = "000" ]; then
        fail "$name" "no response from $url within ${timeout}s" \
             "Container not running? Check: docker ps | grep ${_SLUG}; logs: docker logs <container>"
    else
        fail "$name" "HTTP $code from $url (expected match /$pattern/)" \
             "Check logs: docker logs <container>"
    fi
}

# probe_service NAME HOSTNAME PORT [PATH=/] [EXPECT=200] [TIMEOUT=5]
#
# Probes the service through every available path so a failure clearly
# attributes to the right layer:
#
#   1. Container DNS    : http://<HOSTNAME>:<PORT><PATH>
#   2. piHole DNS       : dig @pihole <HOSTNAME>.internal           (if pihole enabled)
#   3. LAN via caddy    : https://<HOSTNAME>.internal<PATH>         (if caddy enabled)
#   4. Public via caddy : https://<HOSTNAME>.<EXIST_PUBLIC_DOMAIN><PATH>
#                                                                   (if EXIST_PUBLIC_DOMAIN set)
#
# HOSTNAME is the bare front-of-hostname — used both as the Docker DNS name
# and as the `.internal` / public subdomain (i.e. `<HOSTNAME>.internal`).
# For multi-container services pass each container in turn (e.g. hermes-agent,
# hermes-dashboard).
#
# The caddy probe uses `curl --connect-to <host>:443:caddy:443` so it tests
# caddy's routing without depending on this adhoc container's resolver chain.
# The piHole probe (layer 2) is the separate, explicit check that piHole has
# the right A-record — so "pihole down/misconfigured" is distinguishable from
# "caddy misrouting" is distinguishable from "container down".
#
# TLS uses -k: caddy's .internal CA isn't trusted inside adhoc, and a public
# ACME cert may not yet be issued — both are separate concerns from routing.
probe_service() {
    local name="$1" hostname="$2" port="$3" path="${4:-/}" expect="${5:-200}" timeout="${6:-5}"
    _probe_service_impl exact "$name" "$hostname" "$port" "$path" "$expect" "$timeout"
}

# probe_service_any NAME HOSTNAME PORT [PATH=/] [PATTERN=^200$] [TIMEOUT=5]
# Same as probe_service but EXPECT is a regex (e.g. "^(200|302|401)$").
probe_service_any() {
    local name="$1" hostname="$2" port="$3" path="${4:-/}" pattern="${5:-^200$}" timeout="${6:-5}"
    _probe_service_impl regex "$name" "$hostname" "$port" "$path" "$pattern" "$timeout"
}

# probe_pihole NAME HOST [TIMEOUT=3]
#
# Surfaces pihole-layer issues separately from caddy / container issues.
# Queries pihole directly (`dig @pihole +short <HOST>.internal`) and checks
# the answer matches EXIST_LOCAL_HOST_IP — so a missing record, the wrong
# LOCAL/PEER line being active, or pihole itself being down all surface as
# distinct, actionable failures.
#
# Skips cleanly when pihole isn't enabled on this host (EXIST_IS_HOSTING_PIHOLE
# is not true) — then there's nothing local to probe.
probe_pihole() {
    local name="$1" host="$2" timeout="${3:-3}"
    load_env_exist
    [ "${EXIST_IS_HOSTING_PIHOLE:-false}" = "true" ] || return 0

    if ! command -v dig >/dev/null 2>&1; then
        warn "${name} via ${host}.internal (pihole DNS)" \
             "dig not installed in this container — DNS layer not verified" \
             "Rebuild existential-adhoc: docker compose -f existential-compose.yml build existential-adhoc"
        return 0
    fi

    local expected="${EXIST_LOCAL_HOST_IP:-}"
    local answer
    answer=$(dig @pihole +short +time="$timeout" +tries=1 "${host}.internal" 2>/dev/null | head -1 || true)

    if [ -z "$answer" ]; then
        fail "${name} via ${host}.internal (pihole DNS)" \
             "pihole returned no A-record for ${host}.internal" \
             "Add a record to hosting/pihole/docker-compose.yml FTLCONF_dns_hosts pointing ${host}.internal at \${EXIST_LOCAL_HOST_IP}, then: docker compose -f hosting/pihole/docker-compose.yml restart pihole"
    elif [ -z "$expected" ]; then
        warn "${name} via ${host}.internal (pihole DNS)" \
             "pihole answered ${answer} but EXIST_LOCAL_HOST_IP is empty — can't compare" \
             "Set EXIST_LOCAL_HOST_IP in .env.shared and re-run ./existential.sh"
    elif [ "$answer" = "$expected" ]; then
        ok "${name} via ${host}.internal (pihole DNS)"
    else
        fail "${name} via ${host}.internal (pihole DNS)" \
             "pihole answered ${answer}, expected ${expected}" \
             "The LOCAL/PEER record for ${host}.internal in hosting/pihole/docker-compose.yml may be on the wrong line — flip the active record to point at LOCAL_HOST_IP, then restart pihole."
    fi
}

# probe_caddy NAME HOST [PATH=/] [EXPECT=200] [TIMEOUT=5]
# Probes the caddy-fronted paths for HOST — piHole DNS, .internal via caddy,
# and (if EXIST_PUBLIC_DOMAIN is set) public via caddy. Use when the direct
# container name differs from the caddy block name (e.g. caddy routes
# librechat.internal -> librechat-client:80), so direct + caddy can't share
# a single hostname. Caller pairs this with their own http_probe for the
# direct leg.
probe_caddy() {
    # Skip Caddy routing checks inside a decree sidecar — the sidecar only needs
    # to confirm the service itself is up, not the full routing stack.
    [ "${DECREE_SIDECAR:-}" = "true" ] && return 0
    local name="$1" host="$2" path="${3:-/}" expect="${4:-200}" timeout="${5:-5}"
    _probe_caddy_paths exact "$name" "$host" "$path" "$expect" "$timeout"
}

# probe_caddy_any NAME HOST [PATH=/] [PATTERN=^200$] [TIMEOUT=5]
probe_caddy_any() {
    [ "${DECREE_SIDECAR:-}" = "true" ] && return 0
    local name="$1" host="$2" path="${3:-/}" pattern="${4:-^200$}" timeout="${5:-5}"
    _probe_caddy_paths regex "$name" "$host" "$path" "$pattern" "$timeout"
}

_probe_service_impl() {
    local mode="$1" name="$2" hostname="$3" port="$4" path="$5" expect="$6" timeout="$7"

    # 1. Direct via container DNS
    if [ "$mode" = "regex" ]; then
        http_probe_any "${name} via ${hostname}:${port}" \
                       "http://${hostname}:${port}${path}" "$expect" "$timeout"
    else
        http_probe "${name} via ${hostname}:${port}" \
                   "http://${hostname}:${port}${path}" "$expect" "$timeout"
    fi

    # 2 + 3. .internal + public via caddy
    _probe_caddy_paths "$mode" "$name" "$hostname" "$path" "$expect" "$timeout"
}

_probe_caddy_paths() {
    local mode="$1" name="$2" host="$3" path="$4" expect="$5" timeout="$6"
    load_env_exist
    [ "${EXIST_IS_HOSTING_CADDY:-false}" = "true" ] || return 0

    # Pihole layer — confirms <host>.internal resolves to the right IP. Skipped
    # internally if pihole isn't enabled on this host.
    probe_pihole "$name" "$host"

    _probe_via_caddy "$mode" "${name} via ${host}.internal" \
                     "${host}.internal" "$path" "$expect" "$timeout"

    # Public domain — real DNS (not pihole), so no pihole probe for this leg.
    if [ -n "${EXIST_PUBLIC_DOMAIN:-}" ]; then
        _probe_via_caddy "$mode" "${name} via ${host}.${EXIST_PUBLIC_DOMAIN}" \
                         "${host}.${EXIST_PUBLIC_DOMAIN}" "$path" "$expect" "$timeout"
    fi
}

_probe_via_caddy() {
    local mode="$1" name="$2" host="$3" path="$4" expect="$5" timeout="$6"
    local url="https://${host}${path}"
    local code
    code=$(curl -sS -k -o /dev/null -w "%{http_code}" --max-time "$timeout" \
                --connect-to "${host}:443:caddy:443" "$url" 2>/dev/null || echo "000")

    local pass=0
    if [ "$mode" = "regex" ]; then
        [[ "$code" =~ $expect ]] && pass=1
    else
        [ "$code" = "$expect" ] && pass=1
    fi

    if [ "$pass" = "1" ]; then
        ok "$name"
    elif [ "$code" = "000" ]; then
        fail "$name" "no response via caddy:443 within ${timeout}s" \
             "Is caddy up? docker ps | grep caddy; docker logs caddy | tail -50"
    elif [ "$code" = "502" ] || [ "$code" = "503" ]; then
        fail "$name" "caddy returned $code — backend unreachable" \
             "Either the ${_SLUG} container is down, or the Caddyfile block for ${host} is missing/pointing at the wrong backend. Check: grep -A3 '^${host}' /repo/hosting/caddy/Caddyfile"
    else
        fail "$name" "HTTP $code via caddy (expected $expect)" \
             "Caddy reached the backend but the status differs from the direct probe — likely a scheme/host-aware redirect or auth gate. Compare the direct vs caddy lines above; if intentional, switch this call to probe_service_any."
    fi
}

# tcp_probe NAME HOST PORT [TIMEOUT=3]
tcp_probe() {
    local name="$1" host="$2" port="$3" timeout="${4:-3}"
    if timeout "$timeout" bash -c "</dev/tcp/${host}/${port}" 2>/dev/null; then
        ok "$name"
    else
        fail "$name" "no TCP connect to ${host}:${port} within ${timeout}s" \
             "Container not running or not listening. Check: docker ps | grep ${host}"
    fi
}

# env_var_set NAME [VAR_NAME=NAME]
env_var_set() {
    local name="${1}" var="${2:-$1}"
    load_env_exist
    if [ -n "${!var:-}" ]; then
        ok "env ${var} set"
    else
        fail "env ${var} set" "${var} is empty or unset" \
             "Set ${var} in .env.shared (global) or service .env.exist and re-run ./existential.sh"
    fi
}

# file_present NAME PATH
file_present() {
    local name="$1" path="$2"
    if [ -e "$path" ]; then
        ok "$name"
    else
        fail "$name" "$path does not exist" \
             "Run ./existential.sh to render templates, or check the path"
    fi
}

# ── Summary ──────────────────────────────────────────────────────────────────
finish() {
    if [ "$FAILURES" -gt 0 ]; then
        printf '[%s] %d failure(s), %d warning(s)\n' "$_SLUG" "$FAILURES" "$WARNINGS"
        exit 1
    elif [ "$WARNINGS" -gt 0 ]; then
        printf '[%s] ok (%d warning(s))\n' "$_SLUG" "$WARNINGS"
        exit 0
    else
        printf '[%s] ok\n' "$_SLUG"
        exit 0
    fi
}
