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

# ── Container runtime ─────────────────────────────────────────────────────────

ROOTLESS_PODMAN=false
if podman --version &>/dev/null 2>&1; then
    DOCKER_CMD=podman
    podman info 2>/dev/null | grep -q 'rootless: true' && ROOTLESS_PODMAN=true
elif distrobox-host-exec podman --version &>/dev/null 2>&1; then
    podman() { distrobox-host-exec podman "$@"; }
    DOCKER_CMD=podman
    podman info 2>/dev/null | grep -q 'rootless: true' && ROOTLESS_PODMAN=true
elif docker --version &>/dev/null 2>&1; then
    DOCKER_CMD=docker
else
    echo "Error: neither docker nor podman found." >&2
    echo "Install Docker: https://docs.docker.com/engine/install/" >&2
    exit 1
fi

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

# Build the adhoc image if not present; all interactive setup runs inside it.
ensure_adhoc_built() {
    if ! $DOCKER_CMD image inspect existential/decree:local &>/dev/null 2>&1; then
        echo "Building existential-adhoc (first run)..."
        $DOCKER_CMD compose -f "${SCRIPT_DIR}/existential-compose.yml" build existential-adhoc
    fi
}

# Run a command inside the adhoc container (TTY-aware).
run_adhoc() {
    # `docker compose run` allocates a pseudo-TTY by default (keyed off stdout),
    # which fails with "the input device is not a TTY" when stdin isn't one — e.g.
    # a git-push pre-push hook: stdout is the terminal, stdin is git's pipe. Default
    # to -T (no TTY) and only opt into -it when BOTH ends are real TTYs.
    local tty_flags=(-T)
    [[ -t 0 && -t 1 ]] && tty_flags=(-it)
    # Rootless Podman user-namespace fix: --user uid:gid maps the process to a
    # sub-uid range, not the host user, so bind-mount writes fail. In rootless
    # Podman, container root (UID 0) already maps to the host user, so omitting
    # --user lets writes succeed. Docker Engine has no namespace remapping and
    # needs --user to produce host-owned files.
    local user_flags=(--user "$(id -u):$(id -g)")
    $ROOTLESS_PODMAN && user_flags=()
    $DOCKER_CMD compose -f "${SCRIPT_DIR}/existential-compose.yml" run --rm "${tty_flags[@]}" \
        "${user_flags[@]}" \
        --entrypoint "" existential-adhoc "$@"
}

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

# The address of this machine, preferring its tailnet address.
#
# Tailscale is a prerequisite (README / getting-started), so when it is up its
# 100.64.0.0/10 address is the better answer: it reaches every device you
# enrolled rather than only this LAN, and it survives the machine moving
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

# Upgrade path for checkouts rendered before EXIST_HOST_IP existed, and for any
# .env.shared left with a blank IP or domain. Both values are only ever FILLED
# IN, never overwritten: a user who typed a real domain, or who deliberately
# wants .internal with pihole, keeps it.
_ensure_host_access() {
    local f="${SCRIPT_DIR}/.env.shared"
    [[ -f "$f" ]] || return 0

    local ip
    ip=$(grep -m1 '^EXIST_LOCAL_HOST_IP=' "$f" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]')
    if [[ -z "$ip" ]]; then
        ip="$(_detect_host_ip)"
        if [[ -n "$ip" ]]; then
            if grep -q '^EXIST_LOCAL_HOST_IP=' "$f"; then
                sed -i "s|^EXIST_LOCAL_HOST_IP=.*|EXIST_LOCAL_HOST_IP=${ip}|" "$f"
            else
                printf 'EXIST_LOCAL_HOST_IP=%s\n' "$ip" >> "$f"
            fi
            if [[ "$ip" =~ ^100\.([6-9][0-9]|1[0-1][0-9]|12[0-7])\. ]]; then
                echo "Detected tailnet IP: ${ip} (reachable from every device on your tailnet)"
            else
                echo "Detected LAN IP: ${ip} (no tailscale — reachable from this LAN only)"
            fi
        fi
    fi

    local domain
    domain=$(grep -m1 '^EXIST_DOMAIN=' "$f" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]')
    if [[ -z "$domain" && -n "$ip" ]]; then
        domain="${ip//./-}.nip.io"
        if grep -q '^EXIST_DOMAIN=' "$f"; then
            sed -i "s|^EXIST_DOMAIN=.*|EXIST_DOMAIN=${domain}|" "$f"
        else
            printf 'EXIST_DOMAIN=%s\n' "$domain" >> "$f"
        fi
        echo "Set EXIST_DOMAIN=${domain} (public wildcard DNS — every <slug>.<domain> resolves to ${ip}, no pihole needed)"
    fi
}

# ── Service enablement ────────────────────────────────────────────────────────
# SERVICE_CATEGORIES, _load_env_shared, _reload_env_shared, _enable_var_for,
# service_is_enabled, and _find_service_dirs come from src/utils/service-common.sh
# (sourced near the top). The helpers below are specific to this entry point.

decree_is_enabled() {
    _load_env_shared
    [[ "${EXIST_IS_SERVICES_DECREE:-false}" == "true" ]]
}

# True when the user has enabled ANYTHING beyond what ships enabled by default.
#
# A bare "is any flag true?" is not the question: caddy ships as
# EXIST_IS_HOSTING_CADDY=true, so that test passes on a completely fresh clone
# and the first-run quest never fires. Compare against .env.exist.shared instead
# — a flag that is true in both is a default, not a choice — so this stays right
# if the set of default-enabled services ever changes.
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
        echo ""
        echo "  ⚠  Caddy is disabled, and port bindings are commented out by default."
        echo "     Nothing will be reachable from a browser."
        echo ""
        echo "     Either enable Caddy (EXIST_IS_HOSTING_CADDY=true), or uncomment the"
        echo "     'ports:' block in each service's docker-compose.yml, then re-run:"
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
    local slug="$1" action="$2"
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

    bash "$script"
}

_run_general_utility() {
    local name="$1"; shift
    case "$name" in
        backup-config)  run_adhoc bash "/src/lib/backup-config.sh" "$@" ;;
        backup-restore) bash "${SCRIPT_DIR}/src/lib/backup-restore.sh" "$@" ;;
        # Host-side: needs the Docker socket to borrow root, which adhoc lacks —
        # and reclaiming ownership of the repo from inside a container bind-mounted
        # into that same repo is exactly the thing it is repairing.
        fix-permissions) bash "${SCRIPT_DIR}/src/lib/fix-permissions.sh" "$@" ;;
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

    # Otherwise it's a service action: `run <slug> [action]` (action → initial).
    _run_service_action "$first" "${2:-initial}"
}

# ── Usage ─────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $0 <action> [args]

Actions:
  (default)           Render *.exist.* templates, run exist.initial.sh for all
                      enabled services (idempotent), then generate docker-compose.yml.
                      Auto-launches quest picker if no services are enabled.
  quest               Interactive onboarding wizard — pick what to build, then
                      run full setup. Re-run anytime to add more services.
  reset               Archive every rendered config file to archive/<timestamp>/
                      so the next run renders fresh. Lists what it will move and
                      asks first. NEVER touches volumes — your data stays put.
  run                 List available run actions.
  run <name>          Run a general utility (src/lib/<name>.sh) or a
                      service's exist.initial.sh.
  run <slug> <act>    Run <category>/<slug>/exist.<act>.sh.
  run fix-permissions Reclaim paths owned by another user and restore tracked
                      file modes (recovery hatch — for when Docker created a
                      bind-mount source as root). --dry-run to preview.
  test [name]         Run tests. 'all' (default) runs general infra tests +
                      every enabled service's exist.test.sh. 'secrets' asserts no
                      rendered secrets are tracked; 'guards'/'harness' prove the
                      secret guards / test plumbing trip on bad input; 'lint'
                      shellchecks every tracked shell script; 'selfcheck'
                      proves each unit suite fails on a forced assertion;
                      'unit'/'integration'/'services' run those suites. Anything
                      else is a service slug.
  validate [name]     On-demand checks: all (default), conventions, drift.
  e2e                 End-to-end: fzf quest picker → fresh clone → render → docker up → test → down.
  e2e --all           Run all e2e-testable quests without prompting.
  e2e <pattern>...    Run e2e-testable quests matching name/filename pattern(s),
                      e.g. 'e2e automation' or 'e2e ai finance'.
  e2e down            Spin down leftover e2e containers/networks/volumes/work dirs
                      from a crashed run (recovery hatch — never touches the real stack).

Options:
EOF
}

# ── Entry point ───────────────────────────────────────────────────────────────

while [[ $# -gt 0 && "$1" == --* ]]; do
    case "$1" in
        --help)  usage; exit 0 ;;
        *)       echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
    shift
done

action="${1:-default}"
[[ $# -gt 0 ]] && shift || true

case "$action" in
    default)
        _is_first_run=false
        [[ ! -f "${SCRIPT_DIR}/.env.shared" ]] && _is_first_run=true

        ensure_git_hooks
        ensure_adhoc_built
        # Back-fill a blank EXIST_DOMAIN / EXIST_LOCAL_HOST_IP *before* rendering.
        # render_template substitutes blank shared values as the empty string, and
        # a destination is written once and never re-rendered — so a template that
        # bakes a bare EXIST_DOMAIN token would otherwise get "" baked in
        # permanently by the very run that fills the value in. No-op on a first
        # run (no .env.shared yet); templates.sh fills both itself there.
        _ensure_host_access
        run_adhoc env REPO_DIR=/repo EXIST_DETECTED_HOST_IP="$(_detect_host_ip)" bash /src/templates.sh
        _reload_env_shared

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
            _ensure_host_access
            run_adhoc env REPO_DIR=/repo EXIST_DETECTED_HOST_IP="$(_detect_host_ip)" bash /src/templates.sh
            _reload_env_shared
        fi
        _ensure_host_ids
        echo ""
        echo "Generating docker-compose.yml..."
        run_adhoc tsx /src/generate-compose.ts /repo docker-compose.yml "${SCRIPT_DIR}"
        _warn_if_no_gateway
        run_initials
        echo "Done! Next step:  docker compose up -d"
        _report_dashboard
        echo ""
        echo "Tip: run ./existential.sh quest to spin up more services or set up pre-baked automations."
        ;;
    reset)
        ensure_adhoc_built
        run_adhoc env REPO_DIR=/repo bash /src/lib/reset.sh
        ;;
    quest)
        ensure_git_hooks
        ensure_adhoc_built
        run_adhoc env REPO_DIR=/repo bash /src/quest.sh "$@"
        _ensure_host_access
        run_adhoc env REPO_DIR=/repo EXIST_DETECTED_HOST_IP="$(_detect_host_ip)" bash /src/templates.sh
        _reload_env_shared
        _ensure_host_ids
        echo ""
        echo "Generating docker-compose.yml..."
        run_adhoc tsx /src/generate-compose.ts /repo docker-compose.yml "${SCRIPT_DIR}"
        _warn_if_no_gateway
        run_initials
        echo "Done! Next step:  docker compose up -d"
        _report_dashboard
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
                # Host-side container-state gate next (adhoc has no docker socket,
                # so this is the only place daemon crash-loops are visible).
                DOCKER_CMD="$DOCKER_CMD" bash "${SCRIPT_DIR}/src/test/integration/container-health.sh" \
                    "${SCRIPT_DIR}/docker-compose.yml" || _rc=1
                run_adhoc bash /src/test/run-all.sh all || _rc=1
                exit "$_rc"
                ;;
            secrets)     bash "${SCRIPT_DIR}/src/test/no-tracked-secrets.sh" ;;
            guards)      bash "${SCRIPT_DIR}/src/test/guard-selftest.sh" ;;
            harness)     bash "${SCRIPT_DIR}/src/test/harness-selftest.sh" ;;
            lint)        bash "${SCRIPT_DIR}/src/test/lint-shell.sh" ;;
            selfcheck)   run_adhoc bash /src/test/run-all.sh selfcheck ;;
            unit)        run_adhoc bash /src/test/run-all.sh unit ;;
            integration) run_adhoc bash /src/test/run-all.sh integration ;;
            services)    run_adhoc bash /src/test/run-all.sh services ;;
            syntax|existential|templates|compose) run_adhoc bash "/src/test/unit/test-${1}.sh" ;;
            gmail|rclone)                          run_adhoc bash "/src/test/integration/test-${1}.sh" ;;
            *)                   _run_service_action "${1}" "test" ;;
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
