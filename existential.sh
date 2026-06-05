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
FORCE=false

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

# ── Container runtime ─────────────────────────────────────────────────────────

if docker --version &>/dev/null 2>&1; then
    DOCKER_CMD=docker
elif podman --version &>/dev/null 2>&1; then
    DOCKER_CMD=podman
elif distrobox-host-exec podman --version &>/dev/null 2>&1; then
    podman() { distrobox-host-exec podman "$@"; }
    DOCKER_CMD=podman
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
    local tty_flags=()
    [[ -t 0 && -t 1 ]] && tty_flags=(-it)
    $DOCKER_CMD compose -f "${SCRIPT_DIR}/existential-compose.yml" run --rm "${tty_flags[@]}" \
        --user "$(id -u):$(id -g)" \
        --entrypoint "" existential-adhoc "$@"
}

# ── Service enablement ────────────────────────────────────────────────────────
# SERVICE_CATEGORIES, _load_env_shared, _reload_env_shared, _enable_var_for,
# service_is_enabled, and _find_service_dirs come from src/utils/service-common.sh
# (sourced near the top). The helpers below are specific to this entry point.

decree_is_enabled() {
    _load_env_shared
    [[ "${EXIST_IS_SERVICES_DECREE:-false}" == "true" ]]
}

_has_any_enabled() {
    grep -qE '^EXIST_IS_[A-Z0-9_]+=true' "${SCRIPT_DIR}/.env.shared" 2>/dev/null
}

# ── Access warning ─────────────────────────────────────────────────────────────

_warn_if_no_gateway() {
    _load_env_shared
    local caddy_on pihole_on
    caddy_on=$(grep '^EXIST_IS_HOSTING_CADDY=' "${SCRIPT_DIR}/.env.shared" 2>/dev/null | cut -d= -f2-)
    pihole_on=$(grep '^EXIST_IS_HOSTING_PIHOLE=' "${SCRIPT_DIR}/.env.shared" 2>/dev/null | cut -d= -f2-)
    if [[ "${caddy_on:-false}" != "true" || "${pihole_on:-false}" != "true" ]]; then
        echo ""
        echo "  ⚠  Port bindings are commented out by default."
        echo "     Services are only reachable via https://<slug>.internal"
        echo "     which requires Caddy (TLS routing) and pihole (DNS)."
        echo ""
        echo "     To access services without them, uncomment the 'ports:' block"
        echo "     in each service's docker-compose.exist.yml and re-run:"
        echo "       ./existential.sh --force"
        echo ""
    fi
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
    local name="$1"
    case "$name" in
        backup-config)  run_adhoc bash "/src/lib/backup-config.sh" ;;
        backup-restore) bash "${SCRIPT_DIR}/src/lib/backup-restore.sh" ;;
        *)              run_adhoc bash "/src/lib/${name}.sh" ;;
    esac
}

run_setup() {
    local first="${1:-}" second="${2:-}"

    if [[ -z "$first" ]]; then
        _list_setup_actions
        return 0
    fi

    if [[ -n "$second" ]]; then
        _run_service_action "$first" "$second"
        return $?
    fi

    if [[ -f "${SCRIPT_DIR}/src/lib/${first}.sh" ]]; then
        _run_general_utility "$first"
    else
        _run_service_action "$first" "initial"
    fi
}

# ── Usage ─────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $0 [--force] <action> [args]

Actions:
  (default)           Render *.exist.* templates, run exist.initial.sh for all
                      enabled services (idempotent), then generate docker-compose.yml.
                      Auto-launches quest picker if no services are enabled.
  quest               Interactive onboarding wizard — pick what to build, then
                      run full setup. Re-run anytime to add more services.
  run                 List available run actions.
  run <name>          Run a general utility (src/lib/<name>.sh) or a
                      service's exist.initial.sh.
  run <slug> <act>    Run <category>/<slug>/exist.<act>.sh.
  test [name]         Run tests. 'all' (default) runs general infra tests +
                      every enabled service's exist.test.sh. 'secrets' asserts no
                      rendered secrets are tracked; 'guards'/'harness' prove the
                      secret guards / test plumbing trip on bad input; 'selfcheck'
                      proves each unit suite fails on a forced assertion;
                      'syntax|gmail|rclone' run those individually. Anything else
                      is a service slug.
  validate [name]     On-demand checks: all (default), conventions, drift.
  e2e                 End-to-end: fzf quest picker → fresh clone → render → docker up → test → down.
  e2e --all           Run all e2e-testable quests without prompting.
  e2e <pattern>...    Run e2e-testable quests matching name/filename pattern(s),
                      e.g. 'e2e automation' or 'e2e ai finance'.
  e2e down            Spin down leftover e2e containers/networks/volumes/work dirs
                      from a crashed run (recovery hatch — never touches the real stack).

Options:
  --force             Re-render existing files even if they already exist.
EOF
}

# ── Entry point ───────────────────────────────────────────────────────────────

while [[ $# -gt 0 && "$1" == --* ]]; do
    case "$1" in
        --force) FORCE=true ;;
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
        run_adhoc env REPO_DIR=/repo FORCE="$FORCE" bash /src/templates.sh
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
            run_adhoc env REPO_DIR=/repo FORCE="$FORCE" bash /src/templates.sh
            _reload_env_shared
        fi
        echo ""
        echo "Generating docker-compose.yml..."
        run_adhoc tsx /src/generate-compose.ts /repo docker-compose.yml "${SCRIPT_DIR}"
        _warn_if_no_gateway
        run_initials
        echo "Done! Next step:  docker compose up -d"
        echo ""
        echo "Tip: run ./existential.sh quest to spin up more services or set up pre-baked automations."
        ;;
    quest)
        ensure_git_hooks
        ensure_adhoc_built
        run_adhoc env REPO_DIR=/repo bash /src/quest.sh "$@"
        run_adhoc env REPO_DIR=/repo FORCE="$FORCE" bash /src/templates.sh
        _reload_env_shared
        echo ""
        echo "Generating docker-compose.yml..."
        run_adhoc tsx /src/generate-compose.ts /repo docker-compose.yml "${SCRIPT_DIR}"
        _warn_if_no_gateway
        run_initials
        echo "Done! Next step:  docker compose up -d"
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
