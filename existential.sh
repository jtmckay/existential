#!/usr/bin/env bash
# existential.sh — create .example counterparts, replace EXIST_ placeholders,
# merge enabled services into a unified docker-compose.yml.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"

FORCE=false

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

gen_password() { LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c "${1:-24}"; printf '\n'; }
gen_hex()      { openssl rand -hex $(( ${1:-32} / 2 )); }
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

# ── Process .example files ────────────────────────────────────────────────────

process_examples() {
    local created=0 skipped=0

    _find_examples() {
        find "$SCRIPT_DIR" \
            "$@" \
            -not -path "*/graveyard/*" \
            -not -path "*/.git/*" \
            -not -path "*/node_modules/*" \
            -not -path "*/site/*" \
            -name "*.example" \
            2>/dev/null \
            | sort
    }

    # Directories first (no placeholder replacement)
    while IFS= read -r src; do
        local dst="${src%.example}"
        if [[ -e "$dst" ]] && [[ "$FORCE" != "true" ]]; then
            (( skipped++ )) || true
            continue
        fi
        cp -r "$src" "$dst"
        while IFS= read -r f; do replace_placeholders "$f"; done < <(find "$dst" -type f 2>/dev/null)
        (( created++ )) || true
        echo "  created: ${dst#"$SCRIPT_DIR/"}"
    done < <(_find_examples -type d)

    # Files second (with placeholder replacement)
    while IFS= read -r src; do
        local dst="${src%.example}"
        if [[ -e "$dst" ]] && [[ "$FORCE" != "true" ]]; then
            (( skipped++ )) || true
            continue
        fi
        cp "$src" "$dst"
        replace_placeholders "$dst"
        if [[ "$dst" == */docker-compose.yml ]] && grep -q 'TRUENAS' "$dst" 2>/dev/null; then
            local truenas_addr=""
            truenas_addr=$(grep '^EXIST_TRUENAS_SERVER_ADDRESS=' "$SCRIPT_DIR/.env.exist" 2>/dev/null | cut -d= -f2-)
            if [[ -z "$truenas_addr" || "$truenas_addr" == "EXIST_CLI" ]]; then
                _comment_out_truenas_volumes "$dst"
                echo "  note: TrueNAS not configured — NFS volumes commented out in ${dst#"$SCRIPT_DIR/"}"
            fi
        fi
        (( created++ )) || true
        echo "  created: ${dst#"$SCRIPT_DIR/"}"
    done < <(_find_examples -type f)

    echo "Created ${created} file(s), skipped ${skipped} existing"
    [[ "$skipped" -gt 0 ]] && echo "  (use --force to regenerate existing files)"
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

# ── Integration setup ─────────────────────────────────────────────────────────

run_setup() {
    local integration="${1:-}"

    if [[ -z "$integration" ]]; then
        echo "Available integrations: actual-budget, gmail, gmail-transactions-cron, gmail-labels, ntfy, rclone"
        echo "Usage: $0 setup <integration>"
        return 0
    fi

    case "$integration" in
        actual-budget) bash "${SCRIPT_DIR}/src/setup/actual-budget.sh" ;;
        gmail)  $DOCKER_CMD compose -f "${SCRIPT_DIR}/existential-compose.yml" run --rm -it \
                    --entrypoint "" -p 8803:8803 \
                    existential-adhoc bash /src/setup/gmail-sync.sh ;;
        gmail-transactions-cron) run_adhoc bash /src/setup/gmail-transactions-cron.sh ;;
        gmail-labels) run_adhoc bash /src/setup/gmail-labels.sh ;;
        ntfy)   run_adhoc bash /src/setup/ntfy.sh ;;
        rclone) run_adhoc bash /src/setup/rclone.sh ;;
        *)      echo "Unknown integration: $integration. Available: actual-budget, gmail, gmail-transactions-cron, gmail-labels, ntfy, rclone" >&2; return 1 ;;
    esac
}

# ── Test suite ────────────────────────────────────────────────────────────────

run_tests() {
    local name="${1:-all}"

    case "$name" in
        all)             run_adhoc bash /src/test/run-all.sh ;;
        syntax|gmail|rclone) run_adhoc bash "/src/test/test-${name}.sh" ;;
        *)               echo "Unknown test: $name. Available: all, syntax, gmail, rclone" >&2; return 1 ;;
    esac
}

# ── Validation (on-demand, not part of `test`) ────────────────────────────────
#
# `validate` runs convention + drift checks against the .example files. Kept
# out of `test` because the user opts into running it explicitly — it doesn't
# need to fire on every CI run.

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
  (default)           Process .example files then generate docker-compose.yml
  examples            Process .example files only
  compose [file]      Generate unified docker-compose.yml (default: docker-compose.yml)
  setup <name>        Configure an integration: actual-budget, gmail, gmail-labels, ntfy, rclone
  test [name]         Run tests: all (default), syntax, gmail, rclone
  validate [name]     On-demand checks: all (default), conventions, drift
                        conventions — slugs in sync across compose/piHole/Caddy/dashy
                        drift       — what re-rendering would change in your .env / compose files

Options:
  --force             Overwrite existing files when processing .example files
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
        echo ""
        generate_compose
        ;;
    examples)
        process_examples
        ;;
    compose)
        generate_compose "${1:-docker-compose.yml}"
        ;;
    setup)
        run_setup "${1:-}"
        ;;
    test)
        run_tests "${1:-all}"
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
