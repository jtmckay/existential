#!/usr/bin/env bash
# existential.sh — thin entry point for the existential homelab stack.
#
# Detects Docker/Podman, builds existential-adhoc on first run, then hands
# off to domain scripts inside the container. All heavy lifting lives in:
#
#   src/templates.sh        — render *.exist.* templates (fzf prompts, placeholders)
#   src/flows.sh            — turn curated flows (machines + the services they need) on and off
#   src/services.sh         — turn single services on and off
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
  sudo usermod -aG docker "${SUDO_USER}"   # once, then reboot
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

# The last entry is the Mac app's Tailscale binary; APFS ignores case, so `tailscale` finds it.
export PATH="$HOME/.local/bin:/usr/local/bin:/run/host/usr/bin:/run/host/usr/local/bin:$PATH:/Applications/Tailscale.app/Contents/MacOS"
export COMPOSE_IGNORE_ORPHANS=1

# What runs here runs on a Mac too: bash 3.2 and BSD tools. `sed -i.bak` is the
# in-place edit both seds accept, and macOS has no `timeout`, so perl's alarm
# stands in for it.
_sed_i() { sed -i.bak "$1" "$2" && rm -f "$2.bak"; }
command -v timeout >/dev/null 2>&1 || timeout() { perl -e 'alarm shift; exec @ARGV' "$@"; }

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

# The address of this host, preferring its tailnet address. Only the Caddy
# add-on uses it (Core is served on the tailnet *name*, _tailscale_serve_core).
#
# The LAN address below works on its own, but when Tailscale is up its 100.64.0.0/10 address is the better answer: it reaches
# every device enrolled rather than only this LAN, and it survives the host moving
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
    if [[ "$(uname)" == Darwin ]]; then
        ip=$(ipconfig getifaddr "$(route -n get 1.1.1.1 2>/dev/null | awk '/interface:/{print $2}')" 2>/dev/null || true)
    else
        ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')
    fi
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
            _sed_i "s|^EXIST_LOCAL_HOST_IP=.*|EXIST_LOCAL_HOST_IP=${ip}|" "$f"
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
        _sed_i "s|^EXIST_DOMAIN=.*|EXIST_DOMAIN=${domain}|" "$f"
        echo "Set EXIST_DOMAIN=${domain} (public wildcard DNS — every <slug>.<domain> resolves to ${ip}, no pihole needed)"
    fi
}

# ── Core over Tailscale ───────────────────────────────────────────────────────
#
# Core's two web apps need a certificate every device already trusts: the editor
# webviews in code-server won't run behind a warning, and the ntfy phone app won't
# connect to one. `tailscale serve` terminates TLS with a Let's Encrypt cert for
# this host's tailnet name and proxies to the loopback ports the templates
# publish. tailscaled keeps a `--bg` config across reboots, and setting a port
# again replaces its handler, so a re-run never stacks a second one.
#
# Reporting rides the same tailnet, as plain http (WireGuard already encrypts it,
# and a worker may know its controller by 100.x address, which no cert names): a
# controller serves host/exist.json on 4480, the answer to "where do I report?",
# and any machine with Loki on serves its push port on 3100.
#
# Never sudo, never fail: whatever is missing is printed as the next step and the
# run carries on. EXIST_TAILNET_NAME is only ever filled in, like EXIST_DOMAIN.
_tailscale_serve_core() {
    local f="${SCRIPT_DIR}/.env.shared" s scheme port target kind status name serving out
    local -a serves=()
    grep -q '^EXIST_IS_SERVICES_CODE_SERVER=true' "$f" 2>/dev/null && serves+=("https 443 http://127.0.0.1:42080")
    grep -q '^EXIST_IS_SERVICES_NTFY=true' "$f" 2>/dev/null && serves+=("https 8443 http://127.0.0.1:44680")
    grep -q '^EXIST_IS_HOSTING_LOKI=true' "$f" 2>/dev/null && serves+=("http 3100 http://127.0.0.1:43100")
    if _is_controller; then
        mkdir -p "${SCRIPT_DIR}/host"
        [[ -f "${SCRIPT_DIR}/host/exist.json" ]] || echo '{}' > "${SCRIPT_DIR}/host/exist.json"
        serves+=("http 4480 ${SCRIPT_DIR}/host/exist.json")
    fi
    [[ ${#serves[@]} -gt 0 ]] || return 0

    echo ""
    if ! command -v tailscale >/dev/null 2>&1; then
        echo "  ⚠  Core needs Tailscale, and it isn't installed on this host."
        echo "     Install it and log in, here and on every device that should reach Core:"
        echo "       https://tailscale.com/download"
        echo "     then re-run ./existential.sh. Without Tailscale, the Caddy add-on serves"
        echo "     https://<slug>.<domain> instead: set EXIST_IS_HOSTING_CADDY=true"
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
        read -r scheme port target <<<"$s"
        kind=Proxy; [[ "$target" == /* ]] && kind=Path
        [[ "$serving" == *"\"${name}:${port}\":{\"Handlers\":{\"/\":{\"${kind}\":\"${target}\""* ]] && continue
        if ! out=$(timeout 30 tailscale serve --bg --"${scheme}"="$port" "$target" </dev/null 2>&1); then
            _tailscale_serve_steps "$out"
            return 0
        fi
    done

    if grep -q '^EXIST_TAILNET_NAME=$' "$f"; then
        _sed_i "s|^EXIST_TAILNET_NAME=$|EXIST_TAILNET_NAME=${name}|" "$f"
    fi
    echo "Core is served over Tailscale (HTTPS, trusted on every device in your tailnet):"
    [[ " ${serves[*]} " == *" 443 "* ]] && echo "  code-server  https://${name}"
    [[ " ${serves[*]} " == *" 8443 "* ]] && echo "  ntfy         https://${name}:8443"
    [[ " ${serves[*]} " == *" 3100 "* ]] && echo "  Loki         http://${name}:3100   (where machines report)"
    [[ " ${serves[*]} " == *" 4480 "* ]] && echo "  controller   http://${name}:4480   (workers ask here where to report)"
    return 0
}

# A worker is a machine whose host runs decree with the worker flow on (reporting).
# Its EXIST_CONTROLLER names the controller it reports to; blank, it is the
# controller. Read from host/.decree/plugins.yml, what is wanted, so the first
# run knows before the host sync has installed anything.
_is_worker() {
    grep -qE '^[[:space:]]+-[[:space:]]+worker[[:space:]]*$|^on:.*[[ ,]worker[], ]' "${SCRIPT_DIR}/host/.decree/plugins.yml" 2>/dev/null
}
_is_controller() {
    _is_worker && ! grep -qE '^EXIST_CONTROLLER=.+' "${SCRIPT_DIR}/.env.shared" 2>/dev/null
}

# The controller's answer to "where do I report?", host/exist.json, served on 4480
# (_tailscale_serve_core) and read by the reporting plugin on every worker:
# EXIST_REPORTING_URL, else this host's Loki when it is on, else nowhere.
_controller_answer() {
    local f="${SCRIPT_DIR}/.env.shared" url name
    _is_controller || return 0
    url=$(grep -m1 '^EXIST_REPORTING_URL=' "$f" 2>/dev/null | cut -d= -f2-) || true
    if [[ -z "$url" ]] && grep -q '^EXIST_IS_HOSTING_LOKI=true' "$f" 2>/dev/null; then
        name=$(grep -m1 '^EXIST_TAILNET_NAME=' "$f" 2>/dev/null | cut -d= -f2-) || true
        if [[ -n "$name" ]]; then url="http://${name}:3100"; else url="http://127.0.0.1:43100"; fi
    fi
    mkdir -p "${SCRIPT_DIR}/host"
    if [[ -n "$url" ]]; then printf '{"loki":"%s"}\n' "$url"; else echo '{}'; fi > "${SCRIPT_DIR}/host/exist.json"
}

_tailscale_serve_steps() {
    echo "  ⚠  Tailscale can't serve Core over HTTPS yet. Do this once, then re-run ./existential.sh:"
    [[ -n "$1" ]] && head -3 <<<"$1" | sed "s/^/       /"
    echo "     1. https://login.tailscale.com/admin/dns: turn on MagicDNS and HTTPS Certificates."
    # The Mac app already runs as you; on Linux tailscaled is root's.
    [[ "$(uname)" == Darwin ]] && return 0
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
    if [[ "$DOCKER_CMD" == podman ]] && ${ROOTLESS_PODMAN:-false}; then
        local me; me="$(id -un 2>/dev/null || echo "${USER:-$(id -u)}")"
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

# The host's own plugins (host/.decree: none, by default) at this checkout's
# version, then whether a decree daemon is there to run them. Nothing starts one
# for you: it has to start at boot, which is the host's to set up.
_host_plugins() {
    # No engine (_worker_without_engine): the same sync, with the host's own yq and decree.
    if [[ -n "${DOCKER_CMD:-}" ]]; then run_adhoc env REPO_DIR=/repo bash /src/lib/plugin.sh sync host
    else REPO_DIR="$SCRIPT_DIR" bash "${SCRIPT_DIR}/src/lib/plugin.sh" sync host; fi \
        || echo "  ⚠  The host's plugin sync failed (above); ./existential.sh tries again."
    local on
    on="$(cd "${SCRIPT_DIR}/host/.decree/machines" 2>/dev/null && ls -- *.yml 2>/dev/null | sed 's/\.yml$//' | xargs)"
    [[ -n "$on" ]] || return 0
    if ! command -v decree >/dev/null 2>&1; then
        echo "  ⚠  The host's plugins (${on}) run in a decree daemon on the host, and decree is not here:"
        _install_steps decree
        echo "     Or turn one off:  ./existential.sh run plugin off host/<name>"
    elif ! tmux has-session -t "=existential-host" 2>/dev/null; then
        echo "  ⚠  The host's plugins (${on}) run in a decree daemon on the host, and none runs host/.decree. Start one:"
        echo "     tmux new -d -s existential-host -c '${SCRIPT_DIR}/host' decree daemon"
        echo "     and have it start at boot: https://existential.company/docs/hosting/host-daemon"
        echo "     Or turn one off:  ./existential.sh run plugin off host/<name>"
    elif [[ " ${on} " == *" reporting "* ]] && ! command -v alloy >/dev/null 2>&1; then
        echo "  ⚠  reporting ships this host's decree runs with alloy, and alloy is not here:"
        _install_steps alloy
    elif [[ " ${on} " == *" reporting "* ]]; then
        # The answer to "is this host reporting?": what its newest report said.
        local runs="${SCRIPT_DIR}/host/.decree/runs" r last=""
        for r in $(ls -t "$runs" 2>/dev/null | head -20); do
            last="$(grep -m1 '^reporting:' "${runs}/${r}/0001-report.log" 2>/dev/null)" && break
        done
        last="${last#reporting: }"; echo "  Last report: ${last:-none yet (the first is within 5 minutes)}"
    fi
    return 0
}

# _install_steps <tool> — how to get one of a worker's tools on this host. yq is
# the version the decree image pins, so host and container agree.
_install_steps() {
    local df="${SCRIPT_DIR}/services/automation/decree/Dockerfile" v os arch
    os="$(uname -s | tr 'A-Z' 'a-z')"
    case "$(uname -m)" in x86_64|amd64) arch=amd64 ;; arm64|aarch64) arch=arm64 ;; *) arch="$(uname -m)" ;; esac
    case "$1" in
        decree)
            echo "       curl -fsSL https://raw.githubusercontent.com/jtmckay/decree/main/install.sh | sh" ;;
        yq)
            v="$(sed -n 's/^ARG YQ_VERSION=//p' "$df")"
            echo "       mkdir -p ~/.local/bin && curl -fsSL -o ~/.local/bin/yq \\"
            echo "         https://github.com/mikefarah/yq/releases/download/v${v}/yq_${os}_${arch} && chmod +x ~/.local/bin/yq"
            [[ "$os" == darwin ]] && echo "       or: brew install yq" ;;
        alloy)
            # The version loki-alloy runs, so every host ships with the same alloy.
            v="$(sed -n 's/^ *image: grafana\/alloy:v//p' "${SCRIPT_DIR}/hosting/loki/docker-compose.exist.yml")"
            echo "       mkdir -p ~/.local/bin && curl -fsSL -o /tmp/alloy.zip \\"
            echo "         https://github.com/grafana/alloy/releases/download/v${v}/alloy-${os}-${arch}.zip \\"
            echo "         && unzip -p /tmp/alloy.zip > ~/.local/bin/alloy && chmod +x ~/.local/bin/alloy && rm /tmp/alloy.zip"
            [[ "$os" == darwin ]] && echo "       or: brew install grafana/grafana/alloy" ;;
        curl|tmux)
            if [[ "$os" == darwin ]]; then echo "       brew install $1"
            else echo "       with your package manager: sudo apt install $1, sudo dnf install $1, ..."; fi ;;
    esac
}

# A worker without docker or podman: curl is how reporting sends (and how decree
# and yq install, so it comes first), decree runs its plugins, yq installs them
# (what adhoc does elsewhere), and tmux keeps the daemon running. Each one missing
# is named with how to get it; 1 if any is. decree and yq install to ~/.local/bin,
# which is not always on PATH: one there is named with the line that puts it on.
_worker_needs() {
    # shellcheck disable=SC2088  # printed for the user to paste, never expanded here
    local t miss=0 bin="${XDG_BIN_HOME:-${HOME}/.local/bin}" rc="~/.bashrc"
    # shellcheck disable=SC2088  # as above
    [[ "${SHELL##*/}" == zsh ]] && rc="~/.zshrc"
    for t in curl decree yq tmux; do
        if ! command -v "$t" >/dev/null 2>&1 && [[ -x "${bin}/${t}" ]]; then
            echo "  ✗ ${t} is in ${bin}, which is not on PATH. Add it, open a new shell, then re-run ./existential.sh:"
            echo "       echo 'export PATH=\"${bin}:\$PATH\"' >> ${rc}"
            miss=1; continue
        elif ! command -v "$t" >/dev/null 2>&1; then
            echo "  ✗ ${t} is not here. Install it, then re-run ./existential.sh:"
        elif [[ "$t" == yq && "$(yq --version 2>&1)" != *mikefarah* ]]; then
            echo "  ✗ the yq here ($(command -v yq)) is not mikefarah's yq v4. Put that one first on PATH:"
        else
            continue
        fi
        _install_steps "$t"; miss=1
    done
    return "$miss"
}

# A host that is already a worker with no services, and has what a worker needs:
# nothing here is for a container, so the image is never built, engine or not.
_worker_only() {
    [[ -f "${SCRIPT_DIR}/.env.shared" ]] && _is_worker \
        && ! grep -qE '^EXIST_IS_[A-Z0-9_]+=true' "${SCRIPT_DIR}/.env.shared" \
        && _worker_needs >/dev/null
}

# The first run's one question, asked here and not in adhoc so that a worker never
# builds the image. Echoes core, controller, worker or none; Enter, anything else
# and no terminal are core.
_ask_role() {
    local pick=""
    if [[ -t 0 && -t 2 ]]; then
        {
            echo "What should this install start with?"
            echo "  core        workspace, automation and notifications (Enter)"
            echo "  controller  Core, and the host your other hosts report to"
            echo "  worker      no services; reports this host to a controller"
            echo "  none        nothing yet: turn services on with ./existential.sh service"
        } >&2
        read -r -p "Start with [core]: " pick || true
    fi
    case "$(printf '%s' "$pick" | tr 'A-Z' 'a-z')" in
        controller) echo controller ;;
        worker)     echo worker ;;
        none)       echo none ;;
        *)          echo core ;;
    esac
}

# A worker, by the first run's answer, by having no engine, or by already being one
# (_worker_only): nothing runs in a container, so adhoc is never built. Its
# plugins run in a decree daemon on the host. The two steps that run in adhoc
# elsewhere run here instead: .env.shared is written with every service off and
# the controller asked (a later run with an engine appends the rest of its keys),
# and _host_plugins syncs host/.decree with the host's yq and decree.
_worker_without_engine() {
    local f="${SCRIPT_DIR}/.env.shared" ctl=""
    [[ -f "$f" ]] || echo "A worker runs no containers: this host reports itself to a controller, with its own tools."
    _worker_needs || return 1
    if grep -qE '^EXIST_IS_[A-Z0-9_]+=true' "$f" 2>/dev/null; then
        echo "  ✗ Services are on in .env.shared, and they need docker: https://docs.docker.com/engine/install/"
        echo "    Or, to make this host a worker only, set each EXIST_IS_*=true there to false."
        return 1
    fi
    if [[ ! -f "$f" ]]; then
        if [[ -t 0 ]]; then
            echo "Which host is the controller? This worker sends its reports there."
            echo "Give its Tailscale name (e.g. myserver) or IP address. Leave it blank to skip for now;"
            echo "you can set EXIST_CONTROLLER in .env.shared later."
            read -r -p "Controller: " ctl || true
            [[ "$ctl" =~ ^[A-Za-z0-9.-]+$ ]] || ctl=""
        fi
        { grep -E '^EXIST_IS_' "${SCRIPT_DIR}/.env.exist.shared" | sed 's/=.*/=false/'
          echo "EXIST_CONTROLLER=${ctl}"; } > "$f"
        ( REPO_DIR="$SCRIPT_DIR"; . "${SCRIPT_DIR}/src/utils/flows.sh"; plugins_turn on worker )
    fi
    _build
    ctl="$(grep -m1 '^EXIST_CONTROLLER=' "$f" | cut -d= -f2-)"
    if [[ -n "$ctl" ]] && ! curl -fsS --max-time 5 "http://${ctl}:4480/" >/dev/null 2>&1; then
        echo "  ⚠  http://${ctl}:4480 does not answer from here. The controller serves it on its tailnet,"
        echo "     so this host needs a route there (Tailscale, or a network that reaches that address)."
    fi
}

# ── Service enablement ────────────────────────────────────────────────────────
# SERVICE_CATEGORIES, _load_env_shared, _reload_env_shared, _enable_var_for,
# service_is_enabled, and _find_service_dirs come from src/utils/service-common.sh
# (sourced near the top). The helpers below are specific to this entry point.

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
        echo "     name. Set EXIST_IS_HOSTING_CADDY=true in .env.shared, or uncomment the"
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

    local n
    n=$($DOCKER_CMD compose -f "$compose" ps -q 2>/dev/null | grep -c . || true)
    [[ "$n" -gt 0 ]] || return 0

    echo ""
    echo "  ⚠  ${n} container(s) from this stack are still running."
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
    if [[ "$reply" == [nN] || "$reply" == [nN][oO] ]]; then
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
    [[ -n "$user" ]] || return 0   # nothing that logs in is on yet
    echo ""
    echo "  Your login:  ${user}   (EXIST_USERNAME in .env.shared)"
    echo "  Password:    EXIST_PASSWORD in .env.shared"
    grep -q '^EXIST_IS_SERVICES_NTFY=true' "$f" 2>/dev/null || return 0
    tailnet=$(grep -m1 '^EXIST_TAILNET_NAME=' "$f" 2>/dev/null | cut -d= -f2-)
    echo "  ntfy's phone app: add the server https://${tailnet:-<host>.<tailnet>.ts.net}:8443"
    echo "  and log in with both (also in services/ntfy/.env as NTFY_ADMIN_USER / NTFY_ADMIN_PASSWORD)."
}

# ── Service init scripts (exist.initial.sh) ───────────────────────────────────
# Runs on every `./existential.sh` call for each enabled service that ships
# exist.initial.sh. Scripts must be idempotent — they check for existing state
# and skip work that has already been done. No sentinel files.
#
# Only pre-startup, non-interactive work belongs here (creating files,
# applying system config). Post-startup automated work lives in decree
# migrations; interactive steps are documented on the service's docs page.

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
        local slug="${svc_dir##*/}"
        local s sname
        for s in "$svc_dir"/exist.*.sh; do
            [[ -f "$s" ]] || continue
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
        local s
        for s in "$svc_dir"/exist.*.sh; do
            [[ -f "$s" ]] && s="${s##*/exist.}" && echo "  ${s%.sh}" >&2
        done
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

# ── The build, shared by the bare command and `flow` ──────────────────────────

# Render every enabled service's templates. A blank EXIST_DOMAIN /
# EXIST_LOCAL_HOST_IP is back-filled *before* rendering: render_template
# substitutes blank shared values as the empty string, and a destination is
# written once and never re-rendered, so a template that bakes a bare
# EXIST_DOMAIN token would otherwise get "" baked in permanently by the very run
# that fills the value in. No-op on a first run (no .env.shared yet);
# templates.sh fills both itself there.
_render() {
    _ensure_host_access
    run_adhoc env REPO_DIR=/repo EXIST_ROLE="${EXIST_ROLE:-}" EXIST_DETECTED_HOST_IP="$(_detect_host_ip)" bash /src/templates.sh
    _reload_env_shared
}

# The two hardware questions, asked once and only when they matter: Core needs
# no GPU, so the first run never asks. They wait until an enabled service
# reserves one. EXIST_GPU_VENDOR is the record of having asked, and
# `run models` is the way back. Blank until then resolves to `none`.
_ask_hardware_if_needed() {
    [[ -z "${EXIST_GPU_VENDOR:-}" && -t 0 ]] || return 0
    local svc_dir
    while IFS= read -r svc_dir; do
        service_is_enabled "$svc_dir" || continue
        grep -qs 'driver: nvidia' "${svc_dir}/docker-compose.exist.yml" || continue
        run_adhoc env REPO_DIR=/repo FIRST_RUN=1 bash /src/lib/models.sh
        _render
        return 0
    done < <(_find_service_dirs)
}

# _image_lines <compose file> — "<service> <image>" for each service's image:,
# trailing comment dropped. Plain awk: this runs on the host, Mac included.
_image_lines() {
    awk '/^services:/ { s = 1; next }
         /^[^ #]/     { s = 0 }
         s && /^  [A-Za-z0-9_.-]+:[[:space:]]*$/ { svc = $1; sub(/:$/, "", svc); next }
         s && svc != "" && /^    image:/ {
             img = $0; sub(/^    image:[[:space:]]*/, "", img); sub(/[[:space:]]+#.*$/, "", img)
             print svc, img
         }' "$1"
}

# _set_image <compose file> <service> <image> — rewrite that service's image:,
# keeping any trailing comment.
_set_image() {
    local tmp
    tmp="$(mktemp)"
    awk -v want="$2" -v img="$3" '
        /^services:/ { s = 1 }
        /^[^ #]/ && !/^services:/ { s = 0 }
        s && /^  [A-Za-z0-9_.-]+:[[:space:]]*$/ { svc = $1; sub(/:$/, "", svc) }
        s && svc == want && /^    image:/ {
            c = ""; if (match($0, /[[:space:]]+#.*$/)) c = substr($0, RSTART)
            print "    image: " img c; next
        }
        { print }' "$1" > "$tmp" && cat "$tmp" > "$1"
    rm -f "$tmp"
}

# A rendered compose file is written once, so an image a template moves to
# (`git pull`, `run check-versions --update`) never reaches it on its own.
# List each enabled service whose rendered image differs from its template's,
# and ask before updating the rendered file; `docker compose up -d` pulls it.
# No terminal is the auto-update flow, which you turned on to follow the branch,
# so there they are applied: listed only, the pins would never move.
_offer_image_updates() {
    local svc_dir out svc old new reply changes=""
    while IFS= read -r svc_dir; do
        service_is_enabled "$svc_dir" || continue
        out="${svc_dir}/docker-compose.yml"
        [[ -f "$out" && -f "${svc_dir}/docker-compose.exist.yml" ]] || continue
        while read -r svc new; do
            old="$(_image_lines "$out" | awk -v s="$svc" '$1 == s { print $2; exit }')"
            [[ -n "$old" && "$old" != "$new" ]] && changes="${changes}${out}|${svc}|${old}|${new}"$'\n'
        done < <(_image_lines "${svc_dir}/docker-compose.exist.yml")
    done < <(_find_service_dirs)
    [[ -n "$changes" ]] || return 0

    echo ""
    echo "Image updates in the templates, not yet in your rendered compose files:"
    while IFS='|' read -r out svc old new; do
        [[ -n "$out" ]] && echo "  ${svc}: ${old} → ${new}"
    done <<< "$changes"
    if [[ -t 0 ]]; then
        read -rp "  Update them? [Y/n] " reply
        [[ "$reply" =~ ^[Nn] ]] && return 0
    fi
    while IFS='|' read -r out svc old new; do
        [[ -n "$out" ]] && _set_image "$out" "$svc" "$new"
    done <<< "$changes"
    echo "  Updated."
}

# Pull every enabled service's image and rebuild the ones built here, so the
# next `docker compose up -d` starts on them. Running containers are untouched:
# compose swaps a container only on `up`. Offline, a pull is skipped, not fatal.
_stage_images() {
    adhoc_detect_runtime
    local compose=(compose -f "${SCRIPT_DIR}/docker-compose.yml") out
    echo ""
    echo "Fetching images (running containers are left alone)..."
    if ! out="$($DOCKER_CMD "${compose[@]}" pull --quiet --ignore-buildable 2>&1)"; then
        printf '%s\n' "$out" | tail -5
        echo "  ⚠ Some images could not be pulled; docker compose up -d tries again."
    fi
    grep -q '^    build:' "${SCRIPT_DIR}/docker-compose.yml" || return 0
    echo "Building images..."
    $DOCKER_CMD "${compose[@]}" build --quiet \
        || echo "  ⚠ A build failed; docker compose up -d --build shows why."
}

# A NAS folder is made by a person, and a wrong owner otherwise shows up minutes
# after `up -d`, deep in one service's first start (nextcloud's installer loops
# "Cannot create or write into the data directory", then serves its setup page
# and stays unhealthy). So each folder is mounted here first, the way Compose
# will mount it and as the uid every container runs as, and docker-compose.yml
# is not written until all of them pass. A _data folder must also take a chmod,
# which NFS allows only its owner; a _share (your own files) needs a write; a
# volume every template mounts `:ro` needs only a read.
_check_nas() {
    local f="${SCRIPT_DIR}/.env.shared" vol=existential-nas-check
    local addr uid gid key dir out owner mode w c r ro fix bad=0
    addr="$(grep -m1 '^EXIST_NFS_ADDRESS=' "$f" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]')"
    [[ -n "$addr" && "$addr" != none ]] || return 0
    uid="$(grep -m1 '^EXIST_PUID=' "$f" | cut -d= -f2- || true)"; uid="${uid:-1000}"
    gid="$(grep -m1 '^EXIST_PGID=' "$f" | cut -d= -f2- || true)"; gid="${gid:-1000}"
    adhoc_detect_runtime
    # The chmod sets the mode the folder already has: it changes nothing, it only
    # asks whether this uid may.
    local probe='t=/d/.existential-check; w=0; c=0
        touch "$t" 2>/dev/null && rm -f "$t" && w=1
        chmod "$(stat -c %a /d)" /d 2>/dev/null && c=1
        ls /d >/dev/null 2>&1 && r=1 || r=0
        echo "$(stat -c "%u:%g %a" /d) $w $c $r"'
    echo ""
    echo "Checking the NAS folders on ${addr} as ${uid}:${gid}..."
    while IFS='=' read -r key dir; do
        [[ "$dir" == /* ]] || continue
        $DOCKER_CMD volume rm -f "$vol" >/dev/null 2>&1
        if ! out="$({ $DOCKER_CMD volume create --driver local --opt type=nfs \
                        --opt "o=addr=${addr},rw,nfsvers=4" --opt "device=:${dir}" "$vol" >/dev/null &&
                      $DOCKER_CMD run --rm --user "${uid}:${gid}" --entrypoint "" -v "${vol}:/d" \
                        existential/decree:local sh -c "$probe"; } 2>&1)"; then
            $DOCKER_CMD volume rm -f "$vol" >/dev/null 2>&1
            bad=1
            echo "  ✗ ${key}  ${addr}:${dir}"
            echo "      could not mount it: $(printf '%s\n' "$out" | tail -1)"
            echo "      The folder must exist on the NAS and be exported over NFS to this host."
            continue
        fi
        $DOCKER_CMD volume rm -f "$vol" >/dev/null 2>&1
        read -r owner mode w c r <<< "$(printf '%s\n' "$out" | tail -1)"
        _nas_read_only "$key" && ro=1 || ro=0
        if [[ "$ro" == 1 && "$r" == 1 ]] ||
           [[ "$ro" == 0 && "$w" == 1 && ( "$c" == 1 || "$key" == EXIST_NFS_SHARE_* ) ]]; then
            echo "  ✓ ${key}  ${dir}"
            continue
        fi
        bad=1
        if [[ "$ro" == 1 ]]; then fix="cannot read it"
        elif [[ "$w" == 1 ]]; then fix="cannot change its mode (over NFS only the owner can)"
        else fix="cannot write it"; fi
        echo "  ✗ ${key}  ${addr}:${dir}"
        echo "      owned by ${owner}, mode ${mode}: ${uid}:${gid} ${fix}."
        echo "      Fix it on the NAS, either way:"
        if [[ "$ro" == 1 ]]; then
            echo "        • as root there:  chmod -R a+rX ${dir}"
        else
            echo "        • as root there:  chown ${uid}:${gid} ${dir} && chmod $([[ "$key" == EXIST_NFS_SHARE_* ]] && echo 775 || echo 770) ${dir}"
        fi
        [[ "$owner" == 0:* ]] ||
            echo "        • or on that folder's NFS share, map every client to its owner: Mapall user:group ${owner}
          (TrueNAS: Shares → NFS → Edit → Advanced Options; Synology: Squash → Map all users)"
        echo "      Or set ${key}=none in .env.shared to keep it off the NAS."
    done < <(grep -E '^EXIST_NFS_(PATH|SHARE)_[A-Z0-9_]+=' "$f")
    [[ "$bad" == 0 ]] && return 0
    echo ""
    echo "docker-compose.yml was not written. Fix the folders above, then run ./existential.sh again."
    return 1
}

# _nas_read_only <EXIST_NFS_…key> — true when the key's volume is mounted, and
# only ever `:ro`, by the service templates (the inverse of generate-compose.ts's nfsKey).
_nas_read_only() {
    local v mounts
    case "$1" in
        EXIST_NFS_SHARE_*) v="${1#EXIST_NFS_SHARE_}_SHARE" ;;
        *)                 v="${1#EXIST_NFS_PATH_}" ;;
    esac
    v="$(printf '%s' "$v" | tr 'A-Z' 'a-z')"
    mounts="$(_find_service_dirs | while IFS= read -r d; do
        grep -hE "^[[:space:]]*- ${v}:" "${d}/docker-compose.exist.yml" 2>/dev/null
    done)"
    [[ -n "$mounts" ]] && ! grep -qvE ':ro([,[:space:]]|$)' <<< "$mounts"
}

# Everything after rendering: ids, Tailscale, the compose file, setup scripts.
_build() {
    _offer_image_updates
    _ensure_host_ids
    if ! grep -qE '^EXIST_IS_[A-Z0-9_]+=true' "${SCRIPT_DIR}/.env.shared" 2>/dev/null; then
        echo ""
        _host_plugins
        if _is_worker; then
            _controller_answer
            echo "A worker with no services, so nothing for docker compose. The host's decree daemon (host/.decree)"
            echo "reports this host to $(grep -m1 '^EXIST_CONTROLLER=' "${SCRIPT_DIR}/.env.shared" | cut -d= -f2- | grep . || echo 'the Loki this host names, as the controller')."
        else
            echo "Nothing is on yet. Pick services:  ./existential.sh service   (or a flow: ./existential.sh flow)"
        fi
        [[ -f "${SCRIPT_DIR}/docker-compose.yml" ]] && echo "Anything still running stops with:  docker compose down"
        return 0
    fi
    _tailscale_serve_core
    _controller_answer
    _start_on_boot
    _check_nas || exit 1
    echo ""
    echo "Generating docker-compose.yml..."
    run_adhoc tsx /src/generate-compose.ts /repo docker-compose.yml "${SCRIPT_DIR}"
    _warn_if_no_gateway
    run_initials
    _host_plugins
    _stage_images
    echo "Done! Next step:  docker compose up -d"
    _report_dashboard
}

# ── Usage ─────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $0 [action]

Actions:
  (none)                 Render templates for enabled services, run their setup
                         scripts, generate docker-compose.yml. The first run
                         asks Core or none; a login is asked when a service needs it.
  flow [list|on|off] [name...]
                         What the stack does for you: each flow turns on the
                         services it needs and its machine, then the same.
  service [list|on|off] [slug...]
                         Turn single services on or off without opening
                         .env.shared, then the same.
  reset                  Archive every rendered file to archive/<timestamp>/ so the
                         next run renders fresh. Asks first; never touches volumes.
  run                    List every action.
  run <utility> [args]   A general utility in src/lib/ (rclone, models, footprint, ...).
  run <slug> [action] [args]
                         A service's exist.<action>.sh (action defaults to initial).
  test [name]            all (default); secrets, guards, harness, lint, typecheck,
                         decree, selfcheck, unit, integration or services; any
                         unit or integration suite by name; or a service slug.
                         host: what runs on the host also runs on a Mac.
  validate [name]        all (default), conventions or drift.
  e2e [--all|down|<pattern>...]
                         Does a fresh install come up working? Clone, render, up,
                         test, down: Core, then each flow marked e2e.
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
        if _worker_only || ! adhoc_find_runtime; then _worker_without_engine; exit $?; fi
        if [[ "$_is_first_run" == "true" ]]; then
            EXIST_ROLE="$(_ask_role)"
            # DOCKER_CMD blank is what sends _host_plugins to the host's own yq and decree.
            if [[ "$EXIST_ROLE" == worker ]]; then DOCKER_CMD=""; _worker_without_engine; exit $?; fi
        fi
        ensure_adhoc_built
        _render
        _ask_hardware_if_needed
        _build
        [[ "$_is_first_run" == "true" ]] && _report_login
        echo ""
        echo "Tip: ./existential.sh flow  picks what else the stack does for you."
        ;;
    reset)
        # Before anything is archived, while docker-compose.yml still exists.
        _offer_stack_down
        ensure_adhoc_built
        run_adhoc env REPO_DIR=/repo bash /src/reset.sh
        ;;
    flow|service)
        ensure_git_hooks
        ensure_adhoc_built
        # 3 is "nothing changed": a list, or a picker left without a choice.
        _rc=0; run_adhoc env REPO_DIR=/repo bash "/src/${action}s.sh" "$@" || _rc=$?
        [[ "$_rc" -eq 3 ]] && exit 0
        [[ "$_rc" -eq 0 ]] || exit "$_rc"
        _render
        _ask_hardware_if_needed
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
                # What runs on the host also runs on a Mac (bash 3.2, BSD tools).
                bash "${SCRIPT_DIR}/src/test/host-portable.sh" || _rc=1
                # The same gate for TypeScript. tsx strips types without checking
                # them, so without this `"strict": true` means nothing.
                bash "${SCRIPT_DIR}/src/test/typecheck-ts.sh" || _rc=1
                # The rest run in containers. A worker may have no engine; CI does.
                if ! adhoc_find_runtime; then
                    echo "  (no docker or podman: container suites skipped; CI runs them)"
                    exit "$_rc"
                fi
                # Both decree projects, with every shipped message template.
                run_adhoc bash /src/test/decree-check.sh || _rc=1
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
            host)        bash "${SCRIPT_DIR}/src/test/host-portable.sh" ;;
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
