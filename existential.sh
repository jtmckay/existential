#!/usr/bin/env bash
# existential.sh — orchestrator for the existential homelab stack.
#
# Responsibilities:
#   1. Render *.exist.* template files into their counterparts (gated by EXIST_IS_*)
#   2. Run service-specific exist.initial.sh scripts on first init (sentinel-gated)
#   3. Merge enabled services into a unified docker-compose.yml
#   4. Dispatch service-specific exist.<action>.sh scripts via `run <slug> <action>`
#   5. Dispatch general utilities (rclone, backup, restore) via `run <name>`
#
# This script does NOT contain service-specific code. Service setup lives in
# each service's directory as exist.<name>.sh (sibling to docker-compose.yml).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FORCE=false

# Service-bearing categories — walked for both template rendering and exist.*.sh.
# (automations/ is handled separately, tied to EXIST_IS_SERVICES_DECREE.)
#
# Order matters for run_initials: hosting first so pihole's router-config
# walkthrough runs before service initials that might reference .internal
# hostnames. nas second for similar reasons (storage backing for services).
SERVICE_CATEGORIES=(hosting nas ai services)

# Expand PATH to cover user-local and host-injected binaries (distrobox, etc.)
export PATH="$HOME/.local/bin:/usr/local/bin:/run/host/usr/bin:/run/host/usr/local/bin:$PATH"

# ── Container runtime detection ───────────────────────────────────────────────

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

# ── Utilities ──────────────────────────────────────────────────────────────────

# Cross-platform sed -i (BSD vs GNU)
_sed() {
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# Random value generators — kept as standalone sourceable libs in src/lib/ so
# other scripts (tests, decree routines, ad-hoc tooling) can reuse them.
# shellcheck source=src/utils/generate_password.sh
. "${SCRIPT_DIR}/src/utils/generate_password.sh"
# shellcheck source=src/utils/generate_hex_key.sh
. "${SCRIPT_DIR}/src/utils/generate_hex_key.sh"

gen_password() { generate_24_char_password; }
gen_hex()      { generate_hex_key "${1:-32}"; }
gen_uuid()     {
    if command -v uuidgen &>/dev/null; then uuidgen | tr '[:upper:]' '[:lower:]'
    else cat /proc/sys/kernel/random/uuid
    fi
}

# Comment out driver/driver_opts blocks that reference TRUENAS in a compose file,
# leaving a bare named volume that Docker Compose will create as local storage.
_comment_out_truenas_volumes() {
    local file="$1"
    local tmp
    tmp=$(mktemp "${SCRIPT_DIR}/.tmp.XXXXXX")
    trap 'rm -f "$tmp"' RETURN

    mapfile -t _lines < "$file"
    local -a _out=()
    local _i=0
    local _n=${#_lines[@]}

    while (( _i < _n )); do
        local _line="${_lines[$_i]}"
        if [[ "$_line" =~ ^([[:space:]]+)driver_opts[[:space:]]*: ]]; then
            local _base_indent=${#BASH_REMATCH[1]}
            local -a _block=("$_line")
            local _j=$(( _i + 1 ))
            while (( _j < _n )); do
                local _bl="${_lines[$_j]}"
                [[ -z "${_bl//[[:space:]]/}" ]] && break
                local _leading="${_bl%%[![:space:]]*}"
                (( ${#_leading} > _base_indent )) || break
                _block+=("$_bl")
                (( _j++ ))
            done
            local _has_truenas=0
            for _bl in "${_block[@]}"; do
                [[ "$_bl" == *TRUENAS* ]] && { _has_truenas=1; break; }
            done
            if (( _has_truenas )); then
                if [[ ${#_out[@]} -gt 0 && "${_out[-1]}" =~ ^[[:space:]]+driver[[:space:]]*: ]]; then
                    _out[-1]="#${_out[-1]}"
                fi
                for _bl in "${_block[@]}"; do _out+=("#$_bl"); done
            else
                _out+=("${_block[@]}")
            fi
            _i=$_j
        else
            _out+=("$_line")
            (( _i++ ))
        fi
    done

    printf '%s\n' "${_out[@]}" > "$tmp"
    mv "$tmp" "$file"
}

# ── EXIST_ placeholder replacement ────────────────────────────────────────────

replace_placeholders() {
    local file="$1"

    # EXIST_* — values from .env.shared (look-up placeholders). Excludes
    # the dynamic generators (EXIST_CLI, EXIST_24_CHAR_PASSWORD, etc.) which
    # aren't keys in .env.shared anyway.
    if [[ -f "$SCRIPT_DIR/.env.shared" ]]; then
        while IFS='=' read -r key value || [[ -n "$key" ]]; do
            [[ "$key" =~ ^EXIST_ ]] || continue
            [[ -n "$key" && -n "$value" ]] || continue
            _sed "s|${key}|${value}|g" "$file"
        done < "$SCRIPT_DIR/.env.shared"
    fi

    # Auto-generated — replace one instance at a time so each gets a unique value
    local line_num val
    while grep -q "EXIST_24_CHAR_PASSWORD" "$file" 2>/dev/null; do
        line_num=$(grep -n "EXIST_24_CHAR_PASSWORD" "$file" | head -1 | cut -d: -f1)
        val=$(gen_password 24)
        _sed "${line_num}s|EXIST_24_CHAR_PASSWORD|${val}|" "$file"
    done
    while grep -q "EXIST_32_CHAR_HEX_KEY" "$file" 2>/dev/null; do
        line_num=$(grep -n "EXIST_32_CHAR_HEX_KEY" "$file" | head -1 | cut -d: -f1)
        val=$(gen_hex 32)
        _sed "${line_num}s|EXIST_32_CHAR_HEX_KEY|${val}|" "$file"
    done
    while grep -q "EXIST_64_CHAR_HEX_KEY" "$file" 2>/dev/null; do
        line_num=$(grep -n "EXIST_64_CHAR_HEX_KEY" "$file" | head -1 | cut -d: -f1)
        val=$(gen_hex 64)
        _sed "${line_num}s|EXIST_64_CHAR_HEX_KEY|${val}|" "$file"
    done
    while grep -q "EXIST_TIMESTAMP" "$file" 2>/dev/null; do
        line_num=$(grep -n "EXIST_TIMESTAMP" "$file" | head -1 | cut -d: -f1)
        _sed "${line_num}s|EXIST_TIMESTAMP|$(date +%Y%m%d_%H%M%S)|" "$file"
    done
    while grep -q "EXIST_UUID" "$file" 2>/dev/null; do
        line_num=$(grep -n "EXIST_UUID" "$file" | head -1 | cut -d: -f1)
        val=$(gen_uuid)
        _sed "${line_num}s|EXIST_UUID|${val}|" "$file"
    done

    # EXIST_CLI — interactive, show surrounding comment context.
    # If the context contains `# DEFAULT_FROM: EXIST_FOO`, a blank entry
    # falls back to the value of EXIST_FOO already written in this file.
    while grep -q "EXIST_CLI" "$file" 2>/dev/null; do
        local match line_content start context escaped default_from default_val
        match=$(grep -n "EXIST_CLI" "$file" | head -1)
        line_num="${match%%:*}"
        line_content="${match#*:}"
        start=$(( line_num > 6 ? line_num - 6 : 1 ))
        context=$(sed -n "${start},$((line_num - 1))p" "$file" | grep "^#" || true)

        default_from=$(printf '%s\n' "$context" | sed -n 's/^# *DEFAULT_FROM: *\([A-Z_][A-Z0-9_]*\) *$/\1/p' | head -1)
        default_val=""
        if [[ -n "$default_from" ]]; then
            default_val=$(grep -E "^${default_from}=" "$file" | head -1 | cut -d= -f2-)
        fi

        echo ""
        echo "  ${file}"
        [[ -n "$context" ]] && printf '  %s\n' "$context"
        printf '  %s\n' "$line_content"
        if [[ -n "$default_val" ]]; then
            read -rp "  Value [${default_val}]: " val
            [[ -z "$val" ]] && val="$default_val"
        else
            read -rp "  Value: " val
        fi

        # Escape | and \ for sed
        escaped="${val//\\/\\\\}"
        escaped="${escaped//|/\\|}"
        _sed "${line_num}s|EXIST_CLI|${escaped}|" "$file"
    done
}

# ── Service enablement (EXIST_IS_<CATEGORY>_<SLUG>) ───────────────────────────
#
# Source of truth is .env.shared. We re-source on demand so a freshly rendered
# .env.shared (.env.exist.shared → .env.shared) is picked up mid-run.

_env_shared_loaded=0
_load_env_shared() {
    [[ "$_env_shared_loaded" == "1" ]] && return 0
    if [[ -f "${SCRIPT_DIR}/.env.shared" ]]; then
        set -a
        # shellcheck disable=SC1091
        . "${SCRIPT_DIR}/.env.shared"
        set +a
        _env_shared_loaded=1
    fi
}

_reload_env_shared() {
    _env_shared_loaded=0
    _load_env_shared
}

# Compute the EXIST_IS_* variable name for a service directory like
# services/decree/ or ai/open-webui/.
_enable_var_for() {
    local svc_dir="$1"
    local rel="${svc_dir#"$SCRIPT_DIR"/}"
    local cat="${rel%%/*}"
    local slug="${rel#*/}"
    slug="${slug%%/*}"
    local var="EXIST_IS_${cat^^}_${slug^^}"
    echo "${var//-/_}"
}

service_is_enabled() {
    _load_env_shared
    local var
    var="$(_enable_var_for "$1")"
    [[ "${!var:-false}" == "true" ]]
}

decree_is_enabled() {
    _load_env_shared
    [[ "${EXIST_IS_SERVICES_DECREE:-false}" == "true" ]]
}

# Every <category>/<slug>/ directory under the standard service categories.
_find_service_dirs() {
    local cat
    for cat in "${SERVICE_CATEGORIES[@]}"; do
        [[ -d "${SCRIPT_DIR}/${cat}" ]] || continue
        find "${SCRIPT_DIR}/${cat}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null
    done | sort
}

# ── Process *.exist.* and *.env.exist template files ─────────────────────────
#
# Template naming:
#   foo.exist.ext        → renders to foo.ext
#   foo.exist.Foo        → renders to Foo (palindrome rule — extension-less files)
#   .env.exist.shared    → renders to .env.shared  (infix rule)
#   <service>/.env.exist → renders to <service>/.env (ends-with-exist rule)

_template_to_dst() {
    local dir fname before after
    dir="$(dirname "$1")"
    fname="$(basename "$1")"
    if [[ "$fname" == *".exist."* ]]; then
        # Has .exist. infix
        before="${fname%%.exist.*}"
        after="${fname##*.exist.}"
        if [[ "${before,,}" == "${after,,}" ]]; then
            echo "${dir}/${before}"
        else
            echo "${dir}/${before}.${after}"
        fi
    elif [[ "$fname" == *".exist" ]]; then
        # Ends with .exist — strip the suffix
        echo "${dir}/${fname%.exist}"
    fi
}

_process_one_template() {
    local src="$1"
    local dst
    dst="$(_template_to_dst "$src")"

    if [[ -e "$dst" ]] && [[ "$FORCE" != "true" ]]; then
        return 1   # skipped
    fi

    if [[ -d "$src" ]]; then
        cp -r "$src" "$dst"
        while IFS= read -r f; do replace_placeholders "$f"; done < <(find "$dst" -type f 2>/dev/null)
    else
        cp "$src" "$dst"
        replace_placeholders "$dst"
        # TrueNAS-not-configured: comment out NFS volume blocks so the file
        # still renders to a working compose without TrueNAS.
        if [[ "$dst" == */docker-compose.yml ]] && grep -q 'TRUENAS' "$dst" 2>/dev/null; then
            local truenas_addr=""
            truenas_addr=$(grep '^EXIST_TRUENAS_SERVER_ADDRESS=' "$SCRIPT_DIR/.env.shared" 2>/dev/null | cut -d= -f2-)
            if [[ -z "$truenas_addr" || "$truenas_addr" == "EXIST_CLI" ]]; then
                _comment_out_truenas_volumes "$dst"
                echo "  note: TrueNAS not configured — NFS volumes commented out in ${dst#"$SCRIPT_DIR/"}"
            fi
        fi
    fi

    echo "  created: ${dst#"$SCRIPT_DIR/"}"
    return 0
}

_process_templates_in() {
    local root="$1"
    [[ -d "$root" ]] || return 0

    # Dirs first (so files inside the new dir get placeholders too)
    while IFS= read -r src; do
        if _process_one_template "$src"; then
            _STATS_CREATED=$(( _STATS_CREATED + 1 ))
        else
            _STATS_SKIPPED=$(( _STATS_SKIPPED + 1 ))
        fi
    done < <(find "$root" -name '*.exist.*' -type d \
                   -not -path '*/graveyard/*' -not -path '*/.git/*' \
                   -not -path '*/node_modules/*' -not -path '*/site/*' 2>/dev/null | sort)

    # Files second: *.exist.* (infix) and *.env.exist (suffix)
    while IFS= read -r src; do
        if _process_one_template "$src"; then
            _STATS_CREATED=$(( _STATS_CREATED + 1 ))
        else
            _STATS_SKIPPED=$(( _STATS_SKIPPED + 1 ))
        fi
    done < <(find "$root" \( -name '*.exist.*' -o -name '*.env.exist' \) -type f \
                   -not -path '*/graveyard/*' -not -path '*/.git/*' \
                   -not -path '*/node_modules/*' -not -path '*/site/*' 2>/dev/null | sort)
}

render_templates() {
    _STATS_CREATED=0
    _STATS_SKIPPED=0

    # 1) Top-level: .env.exist.shared must run first — renders to .env.shared,
    #    which gates all EXIST_IS_* checks in the service loop below.
    if [[ -f "${SCRIPT_DIR}/.env.exist.shared" ]]; then
        if _process_one_template "${SCRIPT_DIR}/.env.exist.shared"; then
            _STATS_CREATED=$(( _STATS_CREATED + 1 ))
            _reload_env_shared
        else
            _STATS_SKIPPED=$(( _STATS_SKIPPED + 1 ))
        fi
    fi
    _load_env_shared

    # 2) Per-service: gate on EXIST_IS_<CATEGORY>_<SLUG>.
    while IFS= read -r svc_dir; do
        if service_is_enabled "$svc_dir"; then
            _process_templates_in "$svc_dir"
        fi
    done < <(_find_service_dirs)

    echo "Created ${_STATS_CREATED} file(s), skipped ${_STATS_SKIPPED} existing"
    [[ "$_STATS_SKIPPED" -gt 0 ]] && echo "  (use --force to regenerate existing files)"
}

# ── Service init scripts (exist.initial.sh) ───────────────────────────────────

run_initials() {
    _load_env_shared
    local ran=0 skipped=0

    while IFS= read -r svc_dir; do
        service_is_enabled "$svc_dir" || continue

        local init_script="${svc_dir}/exist.initial.sh"
        local sentinel="${svc_dir}/.existential.initialized"
        local rel="${svc_dir#"$SCRIPT_DIR"/}"

        [[ -f "$init_script" ]] || continue
        if [[ -f "$sentinel" ]] && [[ "$FORCE" != "true" ]]; then
            (( skipped++ ))
            continue
        fi

        echo ""
        echo "Initializing ${rel}..."
        if bash "$init_script"; then
            touch "$sentinel"
            echo "  ✓ ${rel} initialized"
            (( ran++ ))
        else
            local rc=$?
            echo "  ✗ ${rel}: exist.initial.sh failed (exit ${rc})" >&2
            echo "  Fix the issue and re-run \`./existential.sh\`." >&2
            return 1
        fi
    done < <(_find_service_dirs)

    if [[ $ran -gt 0 || $skipped -gt 0 ]]; then
        echo ""
        echo "Initialized ${ran} service(s), skipped ${skipped} already-initialized"
    fi
}

# ── Adhoc container runner ────────────────────────────────────────────────────

run_adhoc() {
    local tty_flags=()
    [[ -t 0 && -t 1 ]] && tty_flags=(-it)
    $DOCKER_CMD compose -f "${SCRIPT_DIR}/existential-compose.yml" run --rm "${tty_flags[@]}" \
        --entrypoint "" \
        existential-adhoc "$@"
}

# ── Generate unified docker-compose.yml ───────────────────────────────────────

generate_compose() {
    local output="${1:-docker-compose.yml}"
    echo "Generating ${output}..."
    run_adhoc tsx /src/generate-compose.ts /repo "$output"
}

# ── Run dispatch ──────────────────────────────────────────────────────────────
#
# Two shapes:
#   ./existential.sh run <utility>           — runs src/lib/<utility>.sh
#   ./existential.sh run <slug> [action]     — runs <category>/<slug>/exist.<action>.sh
#                                              action defaults to "initial"
#
# The dispatcher looks at src/lib/ first; if nothing matches there, it
# scans service categories. This keeps general utilities (rclone, backup,
# restore) discoverable while letting services own their own setup scripts.

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
            sname="${s##*/}"
            sname="${sname#exist.}"
            sname="${sname%.sh}"
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

    # Each service script is responsible for its own runtime (host vs. adhoc).
    # Scripts that need the adhoc container self-elevate via a header block.
    bash "$script"
}

# General utilities run inside existential-adhoc; backup-restore runs on the
# host and execs into per-service sidecars for actual operations.
_run_general_utility() {
    local name="$1"
    case "$name" in
        backup-config)  run_adhoc bash "/src/lib/backup-config.sh" ;;
        backup-restore) bash "${SCRIPT_DIR}/src/lib/backup-restore.sh" ;;
        *)              run_adhoc bash "/src/lib/${name}.sh" ;;
    esac
}

_has_any_enabled() {
    grep -qE '^EXIST_IS_[A-Z0-9_]+=true' "${SCRIPT_DIR}/.env.shared" 2>/dev/null
}

run_quest() {
    REPO_DIR="${SCRIPT_DIR}" bash "${SCRIPT_DIR}/src/quest.sh" "$@"
}

run_setup() {
    local first="${1:-}"
    local second="${2:-}"

    if [[ -z "$first" ]]; then
        _list_setup_actions
        return 0
    fi

    # Two-arg form: slug + action
    if [[ -n "$second" ]]; then
        _run_service_action "$first" "$second"
        return $?
    fi

    # One-arg form: prefer src/lib/<first>.sh (general utility); fall back
    # to a service's exist.initial.sh.
    if [[ -f "${SCRIPT_DIR}/src/lib/${first}.sh" ]]; then
        _run_general_utility "$first"
    else
        _run_service_action "$first" "initial"
    fi
}

# ── Test suite ────────────────────────────────────────────────────────────────

run_tests() {
    local name="${1:-all}"

    case "$name" in
        all)
            # run-all.sh runs general infra tests + every enabled service's exist.test.sh
            run_adhoc bash /src/test/run-all.sh
            ;;
        syntax|gmail|rclone)
            # General-infra tests live in src/test/test-<name>.sh
            run_adhoc bash "/src/test/test-${name}.sh"
            ;;
        *)
            # Anything else is treated as a service slug — delegate to setup's
            # test-action dispatcher so per-service exist.test.sh self-elevates
            # consistently (whether run via `test <slug>` or `setup <slug> test`).
            _run_service_action "$name" "test"
            ;;
    esac
}

# ── Backup (on-demand) ───────────────────────────────────────────────────────
#
# DB and volume backups run inside per-service decree sidecars on their own
# cron schedules. Activate by copying the cron templates from each service's
# decree/cron.example/ into that service's decree/cron/ dir
# (db-backup-{nightly,weekly}.md, volume-backup-{nightly,weekly}.md).
#
# The target lists (which DBs, which volumes) live in those cron files'
# frontmatter — no separate registry to keep in sync. Use the on-demand
# subcommands below to trigger a backup outside the schedule.

run_backup() {
    local sub="${1:-}"
    [[ $# -gt 0 ]] && shift || true
    case "$sub" in
        db|dbs)
            local svc="${1:-}" tier="${2:-nightly}"
            [ -n "$svc" ] || { echo "Usage: $0 backup db <service> [tier]" >&2; return 1; }
            $DOCKER_CMD exec "${svc}-decree" decree run db-backup -- "$tier"
            ;;
        volumes|vol)
            local svc="${1:-}" tier="${2:-nightly}"
            [ -n "$svc" ] || { echo "Usage: $0 backup volumes <service> [tier]" >&2; return 1; }
            $DOCKER_CMD exec "${svc}-decree" decree run volume-backup -- "$tier"
            ;;
        restore)
            bash "${SCRIPT_DIR}/src/lib/backup-restore.sh"
            ;;
        ""|--help|-h)
            cat <<EOF
Usage: $0 backup <subcommand> [args]

Subcommands:
  db <service> [tier]       Trigger db-backup on a service sidecar now.
                            tier = nightly (default) | weekly
                            e.g. ./existential.sh backup db mealie
  volumes <service> [tier]  Trigger volume-backup on a service sidecar now.
                            e.g. ./existential.sh backup volumes hermes
  restore                   Interactive restore — DB or volume.
                            (Same as \`./existential.sh run backup-restore\`.)

Scheduled runs come from each service's decree/cron/ dir. Copy the templates
from <service>/decree/cron.example/ into the active decree/cron/ dir to activate.
EOF
            ;;
        *)
            echo "Unknown backup subcommand: $sub" >&2
            $0 backup --help
            return 1
            ;;
    esac
}

# ── Validation (on-demand, not part of `test`) ────────────────────────────────

run_validate() {
    local name="${1:-all}"
    local rc=0

    case "$name" in
        all)
            echo "=== Conventions ==="
            run_adhoc tsx /src/test/validate-conventions.ts || rc=1
            echo ""
            echo "=== Drift (template vs rendered) ==="
            run_adhoc tsx /src/test/check-drift.ts || rc=1
            ;;
        conventions)
            run_adhoc tsx /src/test/validate-conventions.ts || rc=1
            ;;
        drift)
            run_adhoc tsx /src/test/check-drift.ts || rc=1
            ;;
        *)
            echo "Unknown validation: $name. Available: all, conventions, drift" >&2
            return 1
            ;;
    esac
    return $rc
}

# ── Entry point ───────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $0 [--force] <action> [args]

Actions:
  (default)           Render *.exist.* templates, run exist.initial.sh for newly
                      enabled services, then generate docker-compose.yml.
                      Auto-launches quest picker if no services are enabled.
  quest               Interactive onboarding wizard — pick what to build, then
                      run full setup. Re-run anytime to add more services.
  templates           Render *.exist.* template files only (gated by EXIST_IS_*).
  initials            Run exist.initial.sh for enabled services with no sentinel.
  compose [file]      Generate unified docker-compose.yml (default: docker-compose.yml).
  run                 List available run actions.
  run <name>          Run a general utility (src/lib/<name>.sh) or a
                      service's exist.initial.sh.
  run <slug> <act>    Run <category>/<slug>/exist.<act>.sh.
  test [name]         Run tests. 'all' (default) runs general infra tests +
                      every enabled service's exist.test.sh. 'syntax|gmail|rclone'
                      run those individually. Anything else is treated as a
                      service slug and runs that service's exist.test.sh.
  backup <sub>        Volume backups / restore: volumes [tier], restore.
  validate [name]     On-demand checks: all (default), conventions, drift.
  e2e [quest...]      End-to-end tests: fresh clone → render → docker up → test → down.
                      Runs quests 1–6 by default; pass quest numbers to run specific ones.
                      Pre-flight check aborts early if conflicting containers exist.

Options:
  --force             Re-render existing files / re-run already-initialized
                      services (bypasses the .existential.initialized sentinel).
EOF
}

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
        render_templates
        if ! _has_any_enabled; then
            echo "No services are enabled yet."
            echo "Tip: run ./existential.sh quest anytime to pick what to build."
            echo ""
            run_quest
            # Re-render so newly-enabled service templates get processed
            render_templates
        fi
        run_initials
        echo ""
        generate_compose
        ;;
    quest)
        run_quest "$@"
        render_templates
        run_initials
        echo ""
        generate_compose
        ;;
    templates)
        render_templates
        ;;
    initials)
        run_initials
        ;;
    compose)
        generate_compose "${1:-docker-compose.yml}"
        ;;
    run)
        run_setup "$@"
        ;;
    test)
        run_tests "${1:-all}"
        ;;
    backup)
        run_backup "$@"
        ;;
    validate)
        run_validate "${1:-all}"
        ;;
    e2e)
        bash "${SCRIPT_DIR}/src/test/e2e.sh" "$@"
        ;;
    --help|-h)
        usage
        ;;
    *)
        echo "Unknown action: $action" >&2
        usage
        exit 1
        ;;
esac
