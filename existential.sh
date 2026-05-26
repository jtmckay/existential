#!/usr/bin/env bash
# existential.sh — orchestrator for the existential homelab stack.
#
# Responsibilities:
#   1. Render *.example files into their counterparts (gated by EXIST_IS_*)
#   2. Run service-specific exist.initial.sh scripts on first init (sentinel-gated)
#   3. Merge enabled services into a unified docker-compose.yml
#   4. Dispatch service-specific exist.<action>.sh scripts via `setup <slug> <action>`
#   5. Dispatch general utilities (rclone, backup, restore) via `setup <name>`
#
# This script does NOT contain service-specific code. Service setup lives in
# each service's directory as exist.<name>.sh (sibling to docker-compose.yml).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FORCE=false

# Service-bearing categories — walked for both .example processing and exist.*.sh.
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
# shellcheck source=src/lib/generate_password.sh
. "${SCRIPT_DIR}/src/lib/generate_password.sh"
# shellcheck source=src/lib/generate_hex_key.sh
. "${SCRIPT_DIR}/src/lib/generate_hex_key.sh"

gen_password() { generate_24_char_password; }
gen_hex()      { generate_hex_key "${1:-32}"; }
gen_uuid()     {
    if command -v uuidgen &>/dev/null; then uuidgen | tr '[:upper:]' '[:lower:]'
    elif [[ -r /proc/sys/kernel/random/uuid ]]; then cat /proc/sys/kernel/random/uuid
    else python3 -c "import uuid; print(uuid.uuid4())"
    fi
}

# Comment out driver/driver_opts blocks that reference TRUENAS in a compose file,
# leaving a bare named volume that Docker Compose will create as local storage.
_comment_out_truenas_volumes() {
    local file="$1"
    python3 - "$file" <<'PYEOF'
import sys, re

lines = open(sys.argv[1]).readlines()
out = []
i = 0
while i < len(lines):
    line = lines[i]
    if re.match(r'[ \t]+driver_opts\s*:', line):
        base_indent = len(line) - len(line.lstrip())
        block = [line]
        j = i + 1
        while j < len(lines) and lines[j].strip() and (len(lines[j]) - len(lines[j].lstrip())) > base_indent:
            block.append(lines[j])
            j += 1
        if any('TRUENAS' in l for l in block):
            if out and re.match(r'[ \t]+driver\s*:', out[-1]):
                out[-1] = '#' + out[-1]
            out.extend('#' + l for l in block)
            i = j
            continue
    out.append(line)
    i += 1
open(sys.argv[1], 'w').writelines(out)
PYEOF
}

# ── EXIST_ placeholder replacement ────────────────────────────────────────────

replace_placeholders() {
    local file="$1"

    # EXIST_* — values from root .env.exist (look-up placeholders). Excludes
    # the dynamic generators (EXIST_CLI, EXIST_24_CHAR_PASSWORD, etc.) which
    # aren't keys in .env.exist anyway.
    if [[ -f "$SCRIPT_DIR/.env.exist" ]]; then
        while IFS='=' read -r key value || [[ -n "$key" ]]; do
            [[ "$key" =~ ^EXIST_ ]] || continue
            [[ -n "$key" && -n "$value" ]] || continue
            _sed "s|${key}|${value}|g" "$file"
        done < "$SCRIPT_DIR/.env.exist"
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
# Source of truth is .env.exist. We re-source on demand so a freshly rendered
# .env.exist (.env.exist.example → .env.exist) is picked up mid-run.

_env_exist_loaded=0
_load_env_exist() {
    [[ "$_env_exist_loaded" == "1" ]] && return 0
    if [[ -f "${SCRIPT_DIR}/.env.exist" ]]; then
        set -a
        # shellcheck disable=SC1091
        . "${SCRIPT_DIR}/.env.exist"
        set +a
        _env_exist_loaded=1
    fi
}

_reload_env_exist() {
    _env_exist_loaded=0
    _load_env_exist
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
    _load_env_exist
    local var
    var="$(_enable_var_for "$1")"
    [[ "${!var:-false}" == "true" ]]
}

decree_is_enabled() {
    _load_env_exist
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

# ── Process .example files ────────────────────────────────────────────────────

_process_one_example() {
    local src="$1"
    local dst="${src%.example}"

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
            truenas_addr=$(grep '^EXIST_TRUENAS_SERVER_ADDRESS=' "$SCRIPT_DIR/.env.exist" 2>/dev/null | cut -d= -f2-)
            if [[ -z "$truenas_addr" || "$truenas_addr" == "EXIST_CLI" ]]; then
                _comment_out_truenas_volumes "$dst"
                echo "  note: TrueNAS not configured — NFS volumes commented out in ${dst#"$SCRIPT_DIR/"}"
            fi
        fi
    fi

    echo "  created: ${dst#"$SCRIPT_DIR/"}"
    return 0
}

_process_examples_in() {
    local root="$1"
    [[ -d "$root" ]] || return 0

    # Dirs first (so files inside the new dir get placeholders too)
    while IFS= read -r src; do
        if _process_one_example "$src"; then
            _STATS_CREATED=$(( _STATS_CREATED + 1 ))
        else
            _STATS_SKIPPED=$(( _STATS_SKIPPED + 1 ))
        fi
    done < <(find "$root" -name '*.example' -type d \
                   -not -path '*/graveyard/*' -not -path '*/.git/*' \
                   -not -path '*/node_modules/*' -not -path '*/site/*' 2>/dev/null | sort)

    # Files second
    while IFS= read -r src; do
        if _process_one_example "$src"; then
            _STATS_CREATED=$(( _STATS_CREATED + 1 ))
        else
            _STATS_SKIPPED=$(( _STATS_SKIPPED + 1 ))
        fi
    done < <(find "$root" -name '*.example' -type f \
                   -not -path '*/graveyard/*' -not -path '*/.git/*' \
                   -not -path '*/node_modules/*' -not -path '*/site/*' 2>/dev/null | sort)
}

process_examples() {
    _STATS_CREATED=0
    _STATS_SKIPPED=0

    # 1) Top-level: .env.exist.example always processes (it's the master config
    #    that gates everything else).
    if [[ -f "${SCRIPT_DIR}/.env.exist.example" ]]; then
        if _process_one_example "${SCRIPT_DIR}/.env.exist.example"; then
            _STATS_CREATED=$(( _STATS_CREATED + 1 ))
            _reload_env_exist
        else
            _STATS_SKIPPED=$(( _STATS_SKIPPED + 1 ))
        fi
    fi
    _load_env_exist

    # 2) Per-service: gate on EXIST_IS_<CATEGORY>_<SLUG>.
    while IFS= read -r svc_dir; do
        if service_is_enabled "$svc_dir"; then
            _process_examples_in "$svc_dir"
        fi
    done < <(_find_service_dirs)

    # 3) Special: automations/ is processed when decree is enabled.
    if decree_is_enabled; then
        _process_examples_in "${SCRIPT_DIR}/automations"
    fi

    echo "Created ${_STATS_CREATED} file(s), skipped ${_STATS_SKIPPED} existing"
    [[ "$_STATS_SKIPPED" -gt 0 ]] && echo "  (use --force to regenerate existing files)"
}

# ── Service init scripts (exist.initial.sh) ───────────────────────────────────

run_initials() {
    _load_env_exist
    local ran=0 skipped=0

    while IFS= read -r svc_dir; do
        service_is_enabled "$svc_dir" || continue

        local init_script="${svc_dir}/exist.initial.sh"
        local sentinel="${svc_dir}/.exist.initialized"
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
    $DOCKER_CMD compose -f "${SCRIPT_DIR}/existential-compose.yml" run --rm -it \
        --entrypoint "" \
        existential-adhoc "$@"
}

# ── Generate unified docker-compose.yml ───────────────────────────────────────

generate_compose() {
    local output="${1:-docker-compose.yml}"
    echo "Generating ${output}..."
    run_adhoc python3 /src/generate-compose.py /repo "$output"
}

# ── Setup dispatch ────────────────────────────────────────────────────────────
#
# Two shapes:
#   ./existential.sh setup <utility>           — runs src/setup/<utility>.sh
#   ./existential.sh setup <slug> [action]     — runs <category>/<slug>/exist.<action>.sh
#                                                action defaults to "initial"
#
# The dispatcher looks at src/setup/ first; if nothing matches there, it
# scans service categories. This keeps general utilities (rclone, backup,
# restore) discoverable while letting services own their own setup scripts.

_list_setup_actions() {
    echo "Usage: $0 setup <name> [action]"
    echo ""
    echo "General utilities (src/setup/):"
    local f
    for f in "${SCRIPT_DIR}/src/setup/"*.sh; do
        [[ -f "$f" ]] || continue
        local name="${f##*/}"
        echo "  $0 setup ${name%.sh}"
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
                echo "  $0 setup ${slug}"
            else
                echo "  $0 setup ${slug} ${sname}"
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
        echo "Unknown setup target: $slug" >&2
        echo "Run \`$0 setup\` (no args) to see available actions." >&2
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

# General utilities from src/setup/. A couple need explicit invocation modes;
# the rest just run on host (they self-elevate if they need container tooling).
_run_general_utility() {
    local name="$1"
    case "$name" in
        backup)         run_adhoc bash /src/setup/backup.sh ;;
        rclone)         run_adhoc bash /src/setup/rclone.sh ;;
        backup-restore) bash "${SCRIPT_DIR}/src/setup/backup-restore.sh" ;;
        *)              bash "${SCRIPT_DIR}/src/setup/${name}.sh" ;;
    esac
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

    # One-arg form: prefer src/setup/<first>.sh (general utility); fall back
    # to a service's exist.initial.sh.
    if [[ -f "${SCRIPT_DIR}/src/setup/${first}.sh" ]]; then
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
# Both DB and volume backups run inside decree-backup on its internal cron
# schedule. Activate by copying the cron templates from
# services/decree/decree-backup/cron.example_/ into the active cron/ dir
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
            local tier="${1:-nightly}"
            $DOCKER_CMD exec decree-backup decree run db-backup -- "$tier"
            ;;
        volumes)
            local tier="${1:-nightly}"
            $DOCKER_CMD exec decree-backup decree run volume-backup -- "$tier"
            ;;
        restore)
            bash "${SCRIPT_DIR}/src/setup/backup-restore.sh"
            ;;
        ""|--help|-h)
            cat <<EOF
Usage: $0 backup <subcommand> [args]

Subcommands:
  db [tier]         Trigger db-backup inside decree-backup right now.
                    tier = nightly (default) | weekly
  volumes [tier]    Trigger volume-backup inside decree-backup right now.
                    tier = nightly (default) | weekly
  restore           Interactive restore — DB or volume.
                    (Same as \`./existential.sh setup backup-restore\`.)

Scheduled runs come from decree-backup's cron — copy the templates in
services/decree/decree-backup/cron.example_/ into the active cron/ dir.
Edit the cron file's frontmatter (TARGETS / VOLUMES) to add or remove
backup targets.
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
            python3 "${SCRIPT_DIR}/src/test/validate-conventions.py" || rc=1
            echo ""
            echo "=== Drift (.example vs rendered) ==="
            python3 "${SCRIPT_DIR}/src/test/check-drift.py" || rc=1
            ;;
        conventions)
            python3 "${SCRIPT_DIR}/src/test/validate-conventions.py" || rc=1
            ;;
        drift)
            python3 "${SCRIPT_DIR}/src/test/check-drift.py" || rc=1
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
  (default)           Process .example files, run exist.initial.sh for newly
                      enabled services, then generate docker-compose.yml.
  examples            Process .example files only (gated by EXIST_IS_*).
  initials            Run exist.initial.sh for enabled services with no sentinel.
  compose [file]      Generate unified docker-compose.yml (default: docker-compose.yml).
  setup               List available setup actions.
  setup <name>        Run a general utility (src/setup/<name>.sh) or a
                      service's exist.initial.sh.
  setup <slug> <act>  Run <category>/<slug>/exist.<act>.sh.
  test [name]         Run tests. 'all' (default) runs general infra tests +
                      every enabled service's exist.test.sh. 'syntax|gmail|rclone'
                      run those individually. Anything else is treated as a
                      service slug and runs that service's exist.test.sh.
  backup <sub>        Volume backups / restore: volumes [tier], restore.
  validate [name]     On-demand checks: all (default), conventions, drift.

Options:
  --force             Re-render existing files / re-run already-initialized
                      services (bypasses the .exist.initialized sentinel).
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
        process_examples
        run_initials
        echo ""
        generate_compose
        ;;
    examples)
        process_examples
        ;;
    initials)
        run_initials
        ;;
    compose)
        generate_compose "${1:-docker-compose.yml}"
        ;;
    setup)
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
    --help|-h)
        usage
        ;;
    *)
        echo "Unknown action: $action" >&2
        usage
        exit 1
        ;;
esac
