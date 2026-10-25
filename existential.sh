#!/usr/bin/env bash
# existential.sh — thin entry point for the existential homelab stack.
#
# Detects Docker/Podman, builds existential-adhoc on first run, then hands
# off to domain scripts inside the container. All heavy lifting lives in:
#
#   src/templates.sh        — render *.exist.* templates (fzf prompts, placeholders)
#   src/quest.sh            — interactive service picker
#   src/generate-compose.ts — merge enabled services → docker-compose.yml
#   src/lib/                — general utilities (backup, rclone, etc.)
#   <service>/exist.*.sh    — service-specific setup scripts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Under sudo, `id -u` is 0: every rendered file lands root-owned at 600 and
# EXIST_PUID=0 runs every container as root. Plain root (no SUDO_USER) owns its
# files consistently and is left alone.
if [[ "$(id -u)" == 0 && -n "${SUDO_USER:-}" ]]; then
    cat >&2 <<EOF
Don't run existential.sh with sudo — files would be root-owned and containers would run as root.
  sudo usermod -aG docker "${SUDO_USER}"   # once, then log out and back in
  ./existential.sh run fix-permissions     # reclaims anything a sudo run left root-owned
EOF
    exit 1
fi

# Shared service-enablement + env helpers (SERVICE_CATEGORIES, _load_env_shared,
# service_is_enabled, _find_service_dirs, _enable_var_for) — single source of
# truth, also sourced by src/templates.sh. Guarded so test-existential.sh, which
# sources only the top half of this file via a process substitution (where
# SCRIPT_DIR is not the real path), doesn't abort here; that harness sources the
# lib itself after overriding SCRIPT_DIR.
if [[ -f "${SCRIPT_DIR}/src/utils/service-common.sh" ]]; then
    # shellcheck source=src/utils/service-common.sh
    . "${SCRIPT_DIR}/src/utils/service-common.sh"
fi

export PATH="$HOME/.local/bin:/usr/local/bin:/run/host/usr/bin:/run/host/usr/local/bin:$PATH"
export COMPOSE_IGNORE_ORPHANS=1

# Point git at the repo's committed hooks (.githooks/pre-commit blocks secrets
# from entering this public repo — see src/test/no-tracked-secrets.sh). Idempotent;
# no-op outside a git checkout. Local config, so it never fights a user override.
ensure_git_hooks() {
    git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree &>/dev/null || return 0
    [[ -d "${SCRIPT_DIR}/.githooks" ]] || return 0
    local cur
    cur="$(git -C "$SCRIPT_DIR" config --local --get core.hooksPath 2>/dev/null || true)"
    if [[ "$cur" != ".githooks" ]]; then
        git -C "$SCRIPT_DIR" config --local core.hooksPath ".githooks" \
            && echo "Installed git pre-commit secret guard (core.hooksPath=.githooks)."
    fi
}

# ensure_adhoc_built and run_adhoc live in src/utils/adhoc.sh so the service
# scripts that need them can source the same implementation instead of each
# hand-rolling a `docker compose run` — nine of them did, and all nine dropped
# the conditional --user, writing root-owned files into the repo. Guarded the
# same way service-common.sh is, for test-existential.sh's process substitution.
if [[ -f "${SCRIPT_DIR}/src/utils/adhoc.sh" ]]; then
    # shellcheck source=src/utils/adhoc.sh
    . "${SCRIPT_DIR}/src/utils/adhoc.sh"
fi

# Record the host's uid/gid in .env.shared so compose can run every container as
# the host user (EXIST_PUID/EXIST_PGID, referenced as ${EXIST_PUID:-1000} in service
# compose files). This keeps bind-mount files owned by — and deletable by — whoever
# runs the stack, on any host, not just the 1000:1000 default. Set-if-missing so a
# manual override in .env.shared is respected; mergeEnv carries them into the master .env.
_ensure_host_ids() {
    local f="${SCRIPT_DIR}/.env.shared"
    [[ -f "$f" ]] || return 0
    grep -q '^EXIST_PUID=' "$f" || printf 'EXIST_PUID=%s\n' "$(id -u)" >> "$f"
    grep -q '^EXIST_PGID=' "$f" || printf 'EXIST_PGID=%s\n' "$(id -g)" >> "$f"
}

# Make `https://<slug>.<domain>` resolve with no setup at all.
#
# EXIST_DOMAIN defaults to EXIST_NIP_DOMAIN — `<host-ip-with-dashes>.nip.io`,
# public wildcard DNS that maps the name straight back to that IP. It needs the
# host IP to derive from, and that used to be a prompt the user could leave blank,
# in which case the domain silently fell back to `x.internal` — which nothing
# resolves without pihole. That turned "does it work in a browser" into a DNS
# question on the very first run.
#
# So detect the IP the same way EXIST_PUID/PGID are detected.

# The address of this machine, preferring its tailnet address. Only the Caddy
# add-on uses it (Core is served on the tailnet *name*, _tailscale_serve_core).
#
# The LAN address below works on its own, but when Tailscale is up its 100.64.0.0/10 address is the better answer: it reaches
# every device enrolled rather than only this LAN, and it survives the machine moving
# networks. `<ts-ip-with-dashes>.nip.io` then gives WILDCARD DNS for an address
# that is only routable inside the tailnet — private by construction, with no
# tailnet DNS config at all.
#
# Note it is the tailnet *IP* we want, never the MagicDNS name: MagicDNS
# resolves exact node names ONLY, so `<slug>.<node>.ts.net` is NXDOMAIN and the
# whole `<slug>.<domain>` convention collapses. nip.io is what supplies the
# wildcard; tailscale supplies the reachability.
#
# Without tailscale, fall back to the source address the kernel would use to
# reach the internet — the LAN address of whichever interface carries traffic.
#
# This MUST run on the host. templates.sh, which needs the value, runs inside the
# adhoc container, where the same commands answer for the container. So detect
# here and pass it in as EXIST_DETECTED_HOST_IP; the EXIST_HOST_IP placeholder in
# .env.exist.shared picks it up, and EXIST_NIP_DOMAIN — resolved straight after —
# finally has a real IP to build a domain from.
_detect_host_ip() {
    local ip
    if command -v tailscale >/dev/null 2>&1; then
        ip=$(tailscale ip -4 2>/dev/null | head -1 | tr -d '[:space:]')
        # 100.64.0.0/10 — anything else means tailscale is installed but down.
        [[ "$ip" =~ ^100\.([6-9][0-9]|1[0-1][0-9]|12[0-7])\.[0-9]+\.[0-9]+$ ]] && { printf '%s' "$ip"; return 0; }
    fi
    ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || ip=""
    printf '%s' "$ip"
}

# Retry host detection when it previously came up empty.
#
# A key that is MISSING from .env.shared is not this function's problem: the
# reconciler in src/templates.sh (_reconcile_env_keys) appends any key the
# template has and the rendered file lacks, and it resolves EXIST_HOST_IP and
# EXIST_NIP_DOMAIN on the way through. What is left here is the other case —
# the key exists but is blank because detection failed on an earlier run (no
# tailscale, no default route yet, first boot before the network was up).
#
# Both values are only ever FILLED IN, never overwritten: a user who typed a real
# domain, or who deliberately wants .internal with pihole, keeps it.
_ensure_host_access() {
    local f="${SCRIPT_DIR}/.env.shared"
    [[ -f "$f" ]] || return 0

    local ip
    ip=$(grep -m1 '^EXIST_LOCAL_HOST_IP=' "$f" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]')
    if [[ -z "$ip" ]] && grep -q '^EXIST_LOCAL_HOST_IP=' "$f"; then
        ip="$(_detect_host_ip)"
        if [[ -n "$ip" ]]; then
            sed -i "s|^EXIST_LOCAL_HOST_IP=.*|EXIST_LOCAL_HOST_IP=${ip}|" "$f"
            if [[ "$ip" =~ ^100\.([6-9][0-9]|1[0-1][0-9]|12[0-7])\. ]]; then
                echo "Detected tailnet IP: ${ip} (reachable from every device on your tailnet)"
            else
                echo "Detected LAN IP: ${ip} (reachable from devices on this network)"
            fi
        fi
    fi

    local domain
    domain=$(grep -m1 '^EXIST_DOMAIN=' "$f" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]')
    if [[ -z "$domain" && -n "$ip" ]] && grep -q '^EXIST_DOMAIN=' "$f"; then
        domain="${ip//./-}.nip.io"
        sed -i "s|^EXIST_DOMAIN=.*|EXIST_DOMAIN=${domain}|" "$f"
        echo "Set EXIST_DOMAIN=${domain} (public wildcard DNS — every <slug>.<domain> resolves to ${ip}, no pihole needed)"
    fi
}

# ── Core over Tailscale ───────────────────────────────────────────────────────
#
# Core's two web apps need a certificate every device already trusts: the editor
# webviews in code-server won't run behind a warning, and the ntfy phone app won't
# connect to one. `tailscale serve` terminates TLS with a Let's Encrypt cert for
# this machine's tailnet name and proxies to the loopback ports the templates
# publish. tailscaled keeps a `--bg` config across reboots, and setting a port
# again replaces its handler, so a re-run never stacks a second one.
#
# Never sudo, never fail: whatever is missing is printed as the next step and the
# run carries on. EXIST_TAILNET_NAME is only ever filled in, like EXIST_DOMAIN.
_tailscale_serve_core() {
    local f="${SCRIPT_DIR}/.env.shared" s port target status name serving out
    local -a serves=()
    grep -q '^EXIST_IS_SERVICES_CODE_SERVER=true' "$f" 2>/dev/null && serves+=("443 http://127.0.0.1:42080")
    grep -q '^EXIST_IS_SERVICES_NTFY=true' "$f" 2>/dev/null && serves+=("8443 http://127.0.0.1:44680")
    [[ ${#serves[@]} -gt 0 ]] || return 0

    echo ""
    if ! command -v tailscale >/dev/null 2>&1; then
        echo "  ⚠  Core needs Tailscale, and it isn't installed on this host."
        echo "     Install it and log in, here and on every device that should reach Core:"
        echo "       https://tailscale.com/download"
        echo "     then re-run ./existential.sh. Without Tailscale, the Caddy add-on serves"
        echo "     https://<slug>.<domain> instead:  ./existential.sh quest  →  Network"
        return 0
    fi

    status=$(tailscale status --json 2>/dev/null | tr -d ' \t\n') || true
    if [[ "$status" != *'"BackendState":"Running"'* ]]; then
        echo "  ⚠  Tailscale is installed but not logged in. Log in (sudo tailscale up),"
        echo "     then re-run ./existential.sh to serve Core over HTTPS."
        return 0
    fi
    name=$(sed 's/.*"Self":{//' <<<"$status" | grep -o '"DNSName":"[^"]*"' | head -1 | cut -d'"' -f4) || true
    name="${name%.}"

    # CertDomains lists this node's name only once MagicDNS and HTTPS are both on.
    if [[ -z "$name" || "$status" != *"\"CertDomains\":[\"${name}\""* ]] ||
        ! serving=$(timeout 10 tailscale serve status --json </dev/null 2>&1); then
        _tailscale_serve_steps "${serving:-}"
        return 0
    fi
    serving=$(tr -d ' \t\n' <<<"$serving")

    for s in "${serves[@]}"; do
        port="${s%% *}" target="${s#* }"
        [[ "$serving" == *"\"${name}:${port}\":{\"Handlers\":{\"/\":{\"Proxy\":\"${target}\""* ]] && continue
        if ! out=$(timeout 30 tailscale serve --bg --https="$port" "$target" </dev/null 2>&1); then
            _tailscale_serve_steps "$out"
            return 0
        fi
    done

    if grep -q '^EXIST_TAILNET_NAME=$' "$f"; then
        sed -i "s|^EXIST_TAILNET_NAME=$|EXIST_TAILNET_NAME=${name}|" "$f"
    fi
    echo "Core is served over Tailscale (HTTPS, trusted on every device in your tailnet):"
    [[ " ${serves[*]} " == *" 443 "* ]] && echo "  code-server  https://${name}"
    [[ " ${serves[*]} " == *" 8443 "* ]] && echo "  ntfy         https://${name}:8443"
    return 0
}

_tailscale_serve_steps() {
    echo "  ⚠  Tailscale can't serve Core over HTTPS yet. Do this once, then re-run ./existential.sh:"
    [[ -n "$1" ]] && head -3 <<<"$1" | sed "s/^/       /"
    echo "     1. https://login.tailscale.com/admin/dns: turn on MagicDNS and HTTPS Certificates."
    echo "     2. Let your user configure serve (this script never runs sudo):"
    echo "          sudo tailscale set --operator=\$USER"
}

# ── Back after a reboot ───────────────────────────────────────────────────────
#
# Every service is `restart: unless-stopped`, which brings it back whenever the
# container engine starts, so the stack runs from boot until stopped by hand
# exactly when the engine starts at boot. Docker from its packages does
# (docker.service is enabled on install). Rootless Podman does not restart those
# containers at all except through its user unit, podman-restart.service, and a
# user unit runs at boot only with linger on. Both are the user's own to switch
# on, so this does it. Anything that needs root is printed, never run.
_start_on_boot() {
    # No systemd (macOS, WSL without it): the engine's own settings decide.
    command -v systemctl >/dev/null 2>&1 || return 0
    adhoc_detect_runtime
    local me; me="$(id -un)"
    if [[ "$DOCKER_CMD" == podman ]] && ${ROOTLESS_PODMAN:-false}; then
        systemctl --user -q is-enabled podman-restart.service 2>/dev/null \
            || systemctl --user -q enable podman-restart.service 2>/dev/null \
            || echo "  ⚠  Podman won't restart the stack at boot. Once: systemctl --user enable podman-restart.service"
        [[ "$(loginctl show-user "$me" -p Linger --value 2>/dev/null)" == yes ]] \
            || loginctl enable-linger "$me" 2>/dev/null \
            || echo "  ⚠  Your user services won't start until you log in. Once: sudo loginctl enable-linger ${me}"
    elif [[ "$DOCKER_CMD" == podman ]]; then
        systemctl -q is-enabled podman-restart.service 2>/dev/null \
            || echo "  ⚠  Podman won't restart the stack at boot. Once: sudo systemctl enable podman-restart.service"
    elif [[ "$($DOCKER_CMD info --format '{{.OperatingSystem}}' 2>/dev/null)" == *"Docker Desktop"* ]]; then
        # No docker.service to check: Desktop starts at sign-in if its own setting says so.
        :
    else
        systemctl -q is-enabled docker.service 2>/dev/null \
            || echo "  ⚠  Docker doesn't start at boot, so the stack won't either. Once: sudo systemctl enable docker"
    fi
    return 0
}

# ── Service enablement ────────────────────────────────────────────────────────
# SERVICE_CATEGORIES, _load_env_shared, _reload_env_shared, _enable_var_for,
# service_is_enabled, and _find_service_dirs come from src/utils/service-common.sh
# (sourced near the top). The helpers below are specific to this entry point.

# True when the user has enabled ANYTHING beyond what ships enabled by default.
#
# Compared against .env.exist.shared rather than "is any flag true?": a flag
# that is true in both is a default, not a choice. Nothing ships enabled today
# (Caddy did once), so this only matters if that ever changes.
_has_any_enabled() {
    local tmpl="${SCRIPT_DIR}/.env.exist.shared" k v
    [[ -f "${SCRIPT_DIR}/.env.shared" ]] || return 1
    while IFS='=' read -r k v || [[ -n "$k" ]]; do
        k="${k%%#*}"; k="${k// /}"
        [[ "$k" =~ ^EXIST_IS_ ]] || continue
        v="${v%%#*}"; v="${v// /}"
        [[ "$v" == "true" ]] || continue
        grep -qE "^${k}=true([[:space:]]*#.*)?\$" "$tmpl" 2>/dev/null || return 0
    done < "${SCRIPT_DIR}/.env.shared"
    return 1
}

# ── Access warning ─────────────────────────────────────────────────────────────

_warn_if_no_gateway() {
    _load_env_shared
    local caddy_on pihole_on domain needs_pihole=false needs_tailnet_fix=false
    caddy_on=$(grep '^EXIST_IS_HOSTING_CADDY=' "${SCRIPT_DIR}/.env.shared" 2>/dev/null | cut -d= -f2-)
    pihole_on=$(grep '^EXIST_IS_HOSTING_PIHOLE=' "${SCRIPT_DIR}/.env.shared" 2>/dev/null | cut -d= -f2-)
    domain=$(grep '^EXIST_DOMAIN=' "${SCRIPT_DIR}/.env.shared" 2>/dev/null | cut -d= -f2-)

    # A *.nip.io domain resolves itself from public DNS, and a domain the user
    # owns resolves from their own records — pihole is an upgrade there, not a
    # requirement. Only a made-up TLD (.internal) actually needs it.
    #
    # A tailnet MagicDNS name is the trap worth naming: it resolves the node
    # itself, so `EXIST_DOMAIN=<node>.ts.net` looks right and then every
    # `<slug>.` under it is NXDOMAIN. There is no wildcard under a node name.
    case "$domain" in
        *.ts.net) needs_tailnet_fix=true ;;
        *.internal|"") needs_pihole=true ;;
    esac

    if [[ "${caddy_on:-false}" != "true" ]]; then
        # Core is reached over Tailscale (_tailscale_serve_core); only an add-on
        # with a web UI needs Caddy, or its own ports: block uncommented.
        grep -E '^EXIST_IS_[A-Z_]+=true' "${SCRIPT_DIR}/.env.shared" 2>/dev/null \
            | grep -qvE '^EXIST_IS_SERVICES_(CODE_SERVER|AUTOMATION|NTFY)=' || return 0
        echo ""
        echo "  ⚠  Caddy is disabled, so add-ons outside Core have no https://<slug>.<domain>"
        echo "     name. Enable it (./existential.sh quest  →  Network), or uncomment the"
        echo "     'ports:' block in that service's docker-compose.yml, then re-run:"
        echo "       ./existential.sh && docker compose up -d"
        echo ""
    elif [[ "$needs_tailnet_fix" == "true" ]]; then
        echo ""
        echo "  ⚠  EXIST_DOMAIN is '${domain}', a tailnet MagicDNS name."
        echo "     MagicDNS resolves that node name and nothing under it, so every"
        echo "     https://<slug>.${domain} is NXDOMAIN. Use the tailnet IP instead —"
        echo "     nip.io answers the wildcard, tailscale carries the traffic:"
        echo "       EXIST_DOMAIN=<your-tailnet-ip-with-dashes>.nip.io   (e.g. 100-101-102-103.nip.io)"
        echo ""
        echo "     'tailscale ip -4' prints the IP. Leave EXIST_DOMAIN blank and"
        echo "     ./existential.sh fills this in for you."
        echo ""
    elif [[ "$needs_pihole" == "true" && "${pihole_on:-false}" != "true" ]]; then
        echo ""
        echo "  ⚠  EXIST_DOMAIN is '${domain}', which nothing resolves on its own."
        echo "     Switch EXIST_DOMAIN in .env.shared to a self-resolving domain:"
        echo "       <your-tailnet-ip-with-dashes>.nip.io   (e.g. 100-101-102-103.nip.io)"
        echo "     Leave it blank and ./existential.sh derives that for you. Or, to"
        echo "     keep a made-up TLD, enable pihole (EXIST_IS_HOSTING_PIHOLE=true)"
        echo "     or add /etc/hosts entries."
        echo ""
    fi
}

# ── Reset pre-flight ──────────────────────────────────────────────────────────

# `reset` archives docker-compose.yml along with every other rendered file, so a
# stack left running outlives the only file that can cleanly stop it: the
# containers keep going and `docker compose down` then has nothing to read, which
# turns "stop the stack" into hunting container names by hand. The next
# `./existential.sh` also renders fresh secrets, which those still-running
# containers — and their already-initialised volumes — will reject.
#
# So offer to bring it down first. This is a plain `down`: containers and the
# network, never `-v`. Reset does not touch volumes and neither does this.
#
# Host-side on purpose. `reset` itself runs inside existential-adhoc, which has
# no docker socket and so cannot see a running container, let alone stop one.
_offer_stack_down() {
    # Detect here, not at source time: this file is also run INSIDE the adhoc
    # container (src/test/unit/test-existential.sh drives its CLI there), where
    # there is no docker and eager detection killed every invocation, --help
    # included.
    adhoc_detect_runtime
    local compose="${SCRIPT_DIR}/docker-compose.yml"
    [[ -f "$compose" ]] || return 0

    local -a ids=()
    mapfile -t ids < <($DOCKER_CMD compose -f "$compose" ps -q 2>/dev/null)
    # An empty `ps -q` can still yield a single empty element.
    [[ ${#ids[@]} -eq 0 || -z "${ids[0]}" ]] && return 0

    echo ""
    echo "  ⚠  ${#ids[@]} container(s) from this stack are still running."
    echo "     reset archives docker-compose.yml too, so stopping them afterwards"
    echo "     means doing it by hand — there is no compose file left to read."
    echo ""

    # No TTY (a hook, CI, a pipe): say what was skipped rather than hanging on a
    # prompt nobody can answer.
    if [[ ! -t 0 ]]; then
        echo "     Not a terminal — continuing without stopping them."
        echo "     Run 'docker compose down' first if that was not intended."
        echo ""
        return 0
    fi

    local reply
    read -rp "  Run 'docker compose down' first? [Y/n] " reply
    if [[ "${reply,,}" == "n" || "${reply,,}" == "no" ]]; then
        echo "  Leaving the stack running."
        echo ""
        return 0
    fi

    echo ""
    $DOCKER_CMD compose -f "$compose" down
    echo ""
}

# ── Dashboard pointer ─────────────────────────────────────────────────────────
# Dashy is the stack's landing page — the one URL a user needs to remember. Say
# so at the end of every render, so "where do I go now?" is never a search.

_report_dashboard() {
    local dashy_on caddy_on domain
    dashy_on=$(grep '^EXIST_IS_SERVICES_DASHY=' "${SCRIPT_DIR}/.env.shared" 2>/dev/null | cut -d= -f2-)
    [[ "${dashy_on:-false}" == "true" ]] || return 0

    caddy_on=$(grep '^EXIST_IS_HOSTING_CADDY=' "${SCRIPT_DIR}/.env.shared" 2>/dev/null | cut -d= -f2-)
    domain=$(grep '^EXIST_DOMAIN=' "${SCRIPT_DIR}/.env.shared" 2>/dev/null | cut -d= -f2-)

    echo ""
    if [[ "${caddy_on:-false}" == "true" && -n "$domain" ]]; then
        echo "  Your dashboard:  https://dashy.${domain}"
    else
        echo "  Your dashboard:  Dashy (uncomment its 'ports:' block for http://localhost:44280)"
    fi
    echo "  Every core service is linked from there."
}

# The first run asked for a username and a password, and pressing Enter at both
# is the expected answer — so say what you got and where it lives, at the end,
# where the next step (logging in) happens. The password itself is never printed.
_report_login() {
    local f="${SCRIPT_DIR}/.env.shared" user tailnet
    user=$(grep -m1 '^EXIST_USERNAME=' "$f" 2>/dev/null | cut -d= -f2-)
    echo ""
    echo "  Your login:  ${user:-<blank>}   (EXIST_USERNAME in .env.shared)"
    echo "  Password:    EXIST_PASSWORD in .env.shared"
    grep -q '^EXIST_IS_SERVICES_NTFY=true' "$f" 2>/dev/null || return 0
    tailnet=$(grep -m1 '^EXIST_TAILNET_NAME=' "$f" 2>/dev/null | cut -d= -f2-)
    echo "  ntfy's phone app: add the server https://${tailnet:-<machine>.<tailnet>.ts.net}:8443"
    echo "  and log in with both (also in services/ntfy/.env as NTFY_ADMIN_USER / NTFY_ADMIN_PASSWORD)."
}

# ── Service init scripts (exist.initial.sh) ───────────────────────────────────
# Runs on every `./existential.sh` call for each enabled service that ships
# exist.initial.sh. Scripts must be idempotent — they check for existing state
# and skip work that has already been done. No sentinel files.
#
# Only pre-startup, non-interactive work belongs here (creating files,
# applying system config). Post-startup automated work lives in decree
# migrations; interactive steps are documented as quest guides.

run_initials() {
    _load_env_shared
    local ran=0

    while IFS= read -r svc_dir; do
        service_is_enabled "$svc_dir" || continue

        local init_script="${svc_dir}/exist.initial.sh"
        local rel="${svc_dir#"$SCRIPT_DIR"/}"

        [[ -f "$init_script" ]] || continue

        echo ""
        echo "Initializing ${rel}..."
        if bash "$init_script"; then
            echo "  ✓ ${rel}"
            (( ++ran ))
        else
            local rc=$?
            echo "  ✗ ${rel}: exist.initial.sh failed (exit ${rc})" >&2
            echo "  Fix the issue and re-run \`./existential.sh\`." >&2
            return 1
        fi
    done < <(_find_service_dirs)

    if [[ $ran -gt 0 ]]; then echo ""; fi
}

# ── Run dispatch ──────────────────────────────────────────────────────────────
#
# Two shapes:
#   ./existential.sh run <utility>           — runs src/lib/<utility>.sh
#   ./existential.sh run <slug> [action]     — runs <category>/<slug>/exist.<action>.sh
#                                              action defaults to "initial"

_list_setup_actions() {
    echo "Usage: $0 run <name> [action]"
    echo ""
    echo "General utilities (src/lib/):"
    local f name
    for f in "${SCRIPT_DIR}/src/lib/"*.sh; do
        [[ -f "$f" ]] || continue
        name="${f##*/}"; name="${name%.sh}"
        echo "  $0 run ${name}"
    done
    echo ""
    echo "Service-specific (exist.*.sh):"
    while IFS= read -r svc_dir; do
        local scripts=()
        mapfile -t scripts < <(find "$svc_dir" -maxdepth 1 -name 'exist.*.sh' -type f 2>/dev/null | sort)
        [ "${#scripts[@]}" -gt 0 ] || continue
        local slug="${svc_dir##*/}"
        local s sname
        for s in "${scripts[@]}"; do
            sname="${s##*/}"; sname="${sname#exist.}"; sname="${sname%.sh}"
            if [[ "$sname" == "initial" ]]; then
                echo "  $0 run ${slug}"
            else
                echo "  $0 run ${slug} ${sname}"
            fi
        done
    done < <(_find_service_dirs)
}

_find_service_dir_for_slug() {
    local slug="$1" cat
    for cat in "${SERVICE_CATEGORIES[@]}"; do
        if [[ -d "${SCRIPT_DIR}/${cat}/${slug}" ]]; then
            echo "${SCRIPT_DIR}/${cat}/${slug}"
            return 0
        fi
    done
    return 1
}

_run_service_action() {
    local slug="$1" action="$2"; shift 2
    local svc_dir
    svc_dir="$(_find_service_dir_for_slug "$slug")" || {
        echo "Unknown run target: $slug" >&2
        echo "Run \`$0 run\` (no args) to see available actions." >&2
        return 1
    }

    local script="${svc_dir}/exist.${action}.sh"
    if [[ ! -f "$script" ]]; then
        echo "No script at ${script#"$SCRIPT_DIR"/}" >&2
        echo "" >&2
        echo "Available actions for ${slug}:" >&2
        find "$svc_dir" -maxdepth 1 -name 'exist.*.sh' -type f -printf '  %f\n' 2>/dev/null \
            | sed 's/exist\.//; s/\.sh$//' >&2
        return 1
    fi

    bash "$script" "$@"
}

_run_general_utility() {
    local name="$1"; shift
    case "$name" in
        backup-restore) bash "${SCRIPT_DIR}/src/lib/backup-restore.sh" "$@" ;;
        # Host-side: needs the Docker socket to borrow root, which adhoc lacks —
        # and reclaiming ownership of the repo from inside a container bind-mounted
        # into that same repo is exactly the thing it is repairing.
        fix-permissions) bash "${SCRIPT_DIR}/src/lib/fix-permissions.sh" "$@" ;;
        # Host-side: reads `docker stats` so it can put observed usage next to
        # the declared ceilings, and adhoc has no docker socket.
        footprint)      bash "${SCRIPT_DIR}/src/lib/footprint.sh" "$@" ;;
        *)              run_adhoc bash "/src/lib/${name}.sh" "$@" ;;
    esac
}

run_setup() {
    local first="${1:-}"

    if [[ -z "$first" ]]; then
        _list_setup_actions
        return 0
    fi

    # General utilities (src/lib/<name>.sh) take precedence and receive any
    # remaining args verbatim as flags (e.g. `run check-versions --update`).
    if [[ -f "${SCRIPT_DIR}/src/lib/${first}.sh" ]]; then
        shift
        _run_general_utility "$first" "$@"
        return $?
    fi

    # Otherwise it's a service action: `run <slug> [action] [args...]` (action →
    # initial); the args go to the action's script.
    _run_service_action "$first" "${2:-initial}" "${@:3}"
}

# ── The build, shared by the bare command and `quest` ─────────────────────────

# Render every enabled service's templates. A blank EXIST_DOMAIN /
# EXIST_LOCAL_HOST_IP is back-filled *before* rendering: render_template
# substitutes blank shared values as the empty string, and a destination is
# written once and never re-rendered, so a template that bakes a bare
# EXIST_DOMAIN token would otherwise get "" baked in permanently by the very run
# that fills the value in. No-op on a first run (no .env.shared yet);
# templates.sh fills both itself there.
_render() {
    _ensure_host_access
    run_adhoc env REPO_DIR=/repo EXIST_DETECTED_HOST_IP="$(_detect_host_ip)" bash /src/templates.sh
    _reload_env_shared
}

# Everything after rendering: ids, Tailscale, the compose file, setup scripts.
_build() {
    _ensure_host_ids
    _tailscale_serve_core
    _start_on_boot
    echo ""
    echo "Generating docker-compose.yml..."
    run_adhoc tsx /src/generate-compose.ts /repo docker-compose.yml "${SCRIPT_DIR}"
    _warn_if_no_gateway
    run_initials
    echo "Done! Next step:  docker compose up -d"
    _report_dashboard
}

# ── Usage ─────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $0 [action]

Actions:
  (none)                 Render templates for enabled services, run their setup
                         scripts, generate docker-compose.yml. Opens the quest
                         picker when nothing is enabled yet.
  quest                  Pick what to build, then the same.
  reset                  Archive every rendered file to archive/<timestamp>/ so the
                         next run renders fresh. Asks first; never touches volumes.
  run                    List every action.
  run <utility> [args]   A general utility in src/lib/ (rclone, models, footprint, ...).
  run <slug> [action] [args]
                         A service's exist.<action>.sh (action defaults to initial).
  test [name]            all (default); secrets, guards, harness, lint, typecheck,
                         decree, selfcheck, unit, integration or services; any
                         unit or integration suite by name; or a service slug.
  validate [name]        all (default), conventions or drift.
  e2e [--all|down|<pattern>...]
                         Does a fresh install come up working? Clone, render, up,
                         test, down, per quest.
EOF
}

# ── Entry point ───────────────────────────────────────────────────────────────
#
# Everything above this line is definitions, so sourcing this file hands you the
# real helpers — run_initials, service_is_enabled, _find_service_dirs — without
# dispatching a command. That is the point: callers reuse this code path instead
# of keeping a second copy of it. src/test/e2e/e2e.sh sources it to run the same
# exist.initial.sh step a real install gets, and src/templates.sh guards its
# _main the same way.
#
# `return` is only reached when sourced; an executed script falls straight
# through to the dispatch below.
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    return 0
fi

action="${1:-default}"
[[ $# -gt 0 ]] && shift || true

case "$action" in
    default)
        _is_first_run=false
        [[ ! -f "${SCRIPT_DIR}/.env.shared" ]] && _is_first_run=true

        ensure_git_hooks
        ensure_adhoc_built
        _render

        if ! _has_any_enabled; then
            echo ""
            if [[ "$_is_first_run" == "true" ]]; then
                echo "✓ Initial setup complete."
                echo ""
                echo "Launching quest to choose your services..."
            else
                echo "No services are enabled yet."
                echo "Tip: run ./existential.sh quest anytime to pick what to build."
            fi
            echo ""
            run_adhoc env REPO_DIR=/repo bash /src/quest.sh
            _render
        fi
        _build
        [[ "$_is_first_run" == "true" ]] && _report_login
        echo ""
        echo "Tip: run ./existential.sh quest to spin up more services or set up pre-baked automations."
        ;;
    reset)
        # Before anything is archived, while docker-compose.yml still exists.
        _offer_stack_down
        ensure_adhoc_built
        run_adhoc env REPO_DIR=/repo bash /src/reset.sh
        ;;
    quest)
        ensure_git_hooks
        ensure_adhoc_built
        run_adhoc env REPO_DIR=/repo bash /src/quest.sh "$@"
        _render
        _build
        ;;
    run)
        run_setup "$@"
        ;;
    test)
        case "${1:-all}" in
            all)
                _rc=0
                # Host-side guard self-test first (needs git): proves the secret
                # guards actually trip on planted secrets — a guard that silently
                # stopped working otherwise looks identical to a clean pass.
                bash "${SCRIPT_DIR}/src/test/guard-selftest.sh" || _rc=1
                # Harness self-test: proves the test plumbing (run-all aggregation,
                # container-health gate) actually surfaces failures, not just passes.
                bash "${SCRIPT_DIR}/src/test/harness-selftest.sh" || _rc=1
                # Host-side secret guard next (needs git, which adhoc lacks) — a
                # public repo must never track rendered secrets. See H-3.
                bash "${SCRIPT_DIR}/src/test/no-tracked-secrets.sh" || _rc=1
                # Static shell lint (throwaway shellcheck container). Placed with the
                # host-side checks: it needs Docker but not a running stack.
                bash "${SCRIPT_DIR}/src/test/lint-shell.sh" || _rc=1
                # The same gate for TypeScript. tsx strips types without checking
                # them, so without this `"strict": true` means nothing.
                bash "${SCRIPT_DIR}/src/test/typecheck-ts.sh" || _rc=1
                # Both decree projects, with every shipped message template.
                adhoc_detect_runtime
                run_adhoc bash /src/test/decree-check.sh || _rc=1
                # Host-side container-state gate next (adhoc has no docker socket,
                # so this is the only place daemon crash-loops are visible).
                adhoc_detect_runtime
                DOCKER_CMD="$DOCKER_CMD" bash "${SCRIPT_DIR}/src/test/integration/container-health.sh" \
                    "${SCRIPT_DIR}/docker-compose.yml" || _rc=1
                run_adhoc bash /src/test/run-all.sh all || _rc=1
                exit "$_rc"
                ;;
            secrets)     bash "${SCRIPT_DIR}/src/test/no-tracked-secrets.sh" ;;
            guards)      bash "${SCRIPT_DIR}/src/test/guard-selftest.sh" ;;
            harness)     bash "${SCRIPT_DIR}/src/test/harness-selftest.sh" ;;
            lint)        bash "${SCRIPT_DIR}/src/test/lint-shell.sh" ;;
            typecheck)   bash "${SCRIPT_DIR}/src/test/typecheck-ts.sh" ;;
            decree)      run_adhoc bash /src/test/decree-check.sh ;;
            selfcheck)   run_adhoc bash /src/test/run-all.sh selfcheck ;;
            unit)        run_adhoc bash /src/test/run-all.sh unit ;;
            integration) run_adhoc bash /src/test/run-all.sh integration ;;
            services)    run_adhoc bash /src/test/run-all.sh services ;;
            # A suite by name (src/test/{unit,integration}/test-<name>.sh), else
            # a service's exist.test.sh. No suite shares a name with a service.
            *)
                if [[ -f "${SCRIPT_DIR}/src/test/unit/test-${1}.sh" ]]; then
                    run_adhoc bash "/src/test/unit/test-${1}.sh"
                elif [[ -f "${SCRIPT_DIR}/src/test/integration/test-${1}.sh" ]]; then
                    run_adhoc bash "/src/test/integration/test-${1}.sh"
                else
                    _run_service_action "${1}" "test"
                fi
                ;;
        esac
        ;;
    validate)
        case "${1:-all}" in
            all)
                _rc=0
                echo "=== Conventions ==="
                run_adhoc tsx /src/test/unit/validate-conventions.ts /repo || _rc=1
                echo ""
                echo "=== Drift (template vs rendered) ==="
                run_adhoc tsx /src/test/unit/check-drift.ts /repo || _rc=1
                exit $_rc
                ;;
            conventions) run_adhoc tsx /src/test/unit/validate-conventions.ts /repo ;;
            drift)       run_adhoc tsx /src/test/unit/check-drift.ts /repo ;;
            *)           echo "Unknown validation: ${1:-}. Available: all, conventions, drift" >&2; exit 1 ;;
        esac
        ;;
    e2e)
        bash "${SCRIPT_DIR}/src/test/e2e/e2e.sh" "$@"
        ;;
    --help|-h|help)
        usage
        ;;
    *)
        echo "Unknown action: $action" >&2
        usage
        exit 1
        ;;
esac
