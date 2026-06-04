#!/usr/bin/env bash
# render-templates.sh — process *.exist.* template files inside existential-adhoc.
# Run via: run_adhoc env FORCE=false bash /src/render-templates.sh
set -euo pipefail

REPO_DIR="${REPO_DIR:-/repo}"
FORCE="${FORCE:-false}"
SERVICE_CATEGORIES=(hosting nas ai services)

. /src/utils/generate_password.sh
. /src/utils/generate_hex_key.sh

# ── Generators ────────────────────────────────────────────────────────────────

gen_password() { generate_24_char_password; }
gen_hex()      { generate_hex_key "${1:-32}"; }
gen_uuid()     {
    if command -v uuidgen &>/dev/null; then uuidgen | tr '[:upper:]' '[:lower:]'
    else cat /proc/sys/kernel/random/uuid
    fi
}

# ── Env loading ───────────────────────────────────────────────────────────────

_env_shared_loaded=0

_load_env_shared() {
    [[ "$_env_shared_loaded" == "1" ]] && return 0
    if [[ -f "${REPO_DIR}/.env.shared" ]]; then
        set -a; . "${REPO_DIR}/.env.shared"; set +a
        _env_shared_loaded=1
    fi
}

_reload_env_shared() { _env_shared_loaded=0; _load_env_shared; }

# ── Service enablement ────────────────────────────────────────────────────────

_enable_var_for() {
    local rel="${1#"$REPO_DIR"/}"
    local cat="${rel%%/*}"
    local slug="${rel#*/}"; slug="${slug%%/*}"
    local var="EXIST_IS_${cat^^}_${slug^^}"
    echo "${var//-/_}"
}

service_is_enabled() {
    _load_env_shared
    local var; var="$(_enable_var_for "$1")"
    [[ "${!var:-false}" == "true" ]]
}

_find_service_dirs() {
    local cat
    for cat in "${SERVICE_CATEGORIES[@]}"; do
        [[ -d "${REPO_DIR}/${cat}" ]] || continue
        find "${REPO_DIR}/${cat}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null
    done | sort
}

# ── Placeholder replacement ───────────────────────────────────────────────────

# Render a template entirely in memory: read the source, resolve every placeholder
# (EXIST_* references, generated secrets, interactive EXIST_CLI prompts) in a string
# variable, and print the finished content to stdout. Nothing is written to disk
# here — the caller writes the destination once, after this returns. Interactive
# prompts go to the terminal (stderr); only the resolved file lands on stdout.
render_template() {
    local src="$1" dst="$2"
    local content; content="$(cat "$src")"
    local line_num val

    # EXIST_* — substitute values already written to .env.shared.
    # Skip when rendering .env.shared itself (would replace keys with their own values).
    if [[ -f "${REPO_DIR}/.env.shared" && "$dst" != "${REPO_DIR}/.env.shared" ]]; then
        local key value _escaped
        local -a sed_args=()
        while IFS='=' read -r key value || [[ -n "$key" ]]; do
            [[ "$key" =~ ^EXIST_ ]] || continue
            [[ -n "$key" && -n "$value" ]] || continue
            # Escape sed replacement metacharacters: \ first, then & and |
            _escaped="${value//\\/\\\\}"
            _escaped="${_escaped//&/\\&}"
            _escaped="${_escaped//|/\\|}"
            sed_args+=(-e "s|\\\${${key}[^}]*}|${_escaped}|g" -e "s|${key}|${_escaped}|g")
        done < "${REPO_DIR}/.env.shared"
        if [[ ${#sed_args[@]} -gt 0 ]]; then
            content="$(sed "${sed_args[@]}" <<<"$content")"
        fi
    fi

    # Auto-generated — one replacement at a time so each occurrence gets a unique value
    while grep -q "EXIST_24_CHAR_PASSWORD" <<<"$content"; do
        line_num=$(grep -n "EXIST_24_CHAR_PASSWORD" <<<"$content" | head -1 | cut -d: -f1)
        val=$(gen_password 24)
        content="$(sed "${line_num}s|EXIST_24_CHAR_PASSWORD|${val}|" <<<"$content")"
    done
    while grep -q "EXIST_32_CHAR_HEX_KEY" <<<"$content"; do
        line_num=$(grep -n "EXIST_32_CHAR_HEX_KEY" <<<"$content" | head -1 | cut -d: -f1)
        val=$(gen_hex 32)
        content="$(sed "${line_num}s|EXIST_32_CHAR_HEX_KEY|${val}|" <<<"$content")"
    done
    while grep -q "EXIST_64_CHAR_HEX_KEY" <<<"$content"; do
        line_num=$(grep -n "EXIST_64_CHAR_HEX_KEY" <<<"$content" | head -1 | cut -d: -f1)
        val=$(gen_hex 64)
        content="$(sed "${line_num}s|EXIST_64_CHAR_HEX_KEY|${val}|" <<<"$content")"
    done
    while grep -q "EXIST_TIMESTAMP" <<<"$content"; do
        line_num=$(grep -n "EXIST_TIMESTAMP" <<<"$content" | head -1 | cut -d: -f1)
        content="$(sed "${line_num}s|EXIST_TIMESTAMP|$(date +%Y%m%d_%H%M%S)|" <<<"$content")"
    done
    while grep -q "EXIST_UUID" <<<"$content"; do
        line_num=$(grep -n "EXIST_UUID" <<<"$content" | head -1 | cut -d: -f1)
        val=$(gen_uuid)
        content="$(sed "${line_num}s|EXIST_UUID|${val}|" <<<"$content")"
    done

    # EXIST_CLI — read text prompt.
    # Shows the contiguous comment block directly above the field as context.
    # If that block contains `# DEFAULT_FROM: EXIST_FOO`, the value of EXIST_FOO
    # (already resolved above) is used as the default when the user enters nothing.
    while grep -q "EXIST_CLI" <<<"$content"; do
        local match line_content key_name block_start prev_line context
        local default_from default_val escaped
        match=$(grep -n "EXIST_CLI" <<<"$content" | head -1)
        line_num="${match%%:*}"
        line_content="${match#*:}"
        key_name="${line_content%%=*}"

        block_start=$(( line_num - 1 ))
        while (( block_start >= 1 )); do
            prev_line=$(sed -n "${block_start}p" <<<"$content")
            [[ "$prev_line" =~ ^[[:space:]]*# ]] || break
            block_start=$(( block_start - 1 ))
        done
        block_start=$(( block_start + 1 ))

        if (( block_start < line_num )); then
            context=$(sed -n "${block_start},$((line_num - 1))p" <<<"$content")
        else
            context=""
        fi

        default_from=$(printf '%s\n' "$context" | \
            sed -n 's/^# *DEFAULT_FROM: *\([A-Z_][A-Z0-9_]*\) *$/\1/p' | head -1)
        default_val=""
        if [[ -n "$default_from" ]]; then
            default_val=$(grep -E "^${default_from}=" <<<"$content" | head -1 | cut -d= -f2-)
        fi

        # Prompt on the controlling terminal with a plain read (echoes, never leaves
        # the TTY in raw mode). Prompt + context go to stderr so they don't pollute
        # the rendered content this function prints to stdout.
        printf '\n' >&2
        if [[ -n "$context" ]]; then printf '%s\n' "$context" >&2; fi
        if [[ -t 0 ]]; then
            read -rp "  ${key_name} [${default_val}]: " val || val="${default_val}"
        else
            val="${default_val}"
        fi
        if [[ -z "$val" ]]; then val="${default_val}"; fi

        escaped="${val//\\/\\\\}"
        escaped="${escaped//&/\\&}"
        escaped="${escaped//|/\\|}"
        content="$(sed "${line_num}s|EXIST_CLI|${escaped}|" <<<"$content")"
    done

    printf '%s\n' "$content"
}

# ── Template processing ───────────────────────────────────────────────────────

_template_to_dst() {
    local dir fname before after
    dir="$(dirname "$1")"; fname="$(basename "$1")"
    if [[ "$fname" == *".exist."* ]]; then
        before="${fname%%.exist.*}"; after="${fname##*.exist.}"
        if [[ "${before,,}" == "${after,,}" ]]; then echo "${dir}/${before}"
        else echo "${dir}/${before}.${after}"
        fi
    elif [[ "$fname" == *".exist" ]]; then
        echo "${dir}/${fname%.exist}"
    fi
}

_STATS_CREATED=0
_STATS_SKIPPED=0

_process_one_template() {
    local src="$1" dst
    dst="$(_template_to_dst "$src")"

    # .env files are user-owned once rendered — never overwrite, even with --force
    local _dstbase; _dstbase="$(basename "$dst")"
    if [[ -e "$dst" ]] && [[ "$_dstbase" == .env || "$_dstbase" == .env.* ]]; then
        return 1
    fi

    if [[ -e "$dst" ]] && [[ "$FORCE" != "true" ]]; then return 1; fi

    if [[ -d "$src" ]]; then
        cp -r "$src" "$dst"
        local f rendered
        while IFS= read -r f; do
            rendered="$(render_template "$f" "$f")"
            printf '%s\n' "$rendered" > "$f"
        done < <(find "$dst" -type f 2>/dev/null)
    else
        # Resolve every placeholder in memory, then write the destination once.
        # If the user aborts mid-prompt, render_template never returns, so the
        # destination is never written and can't hold a literal EXIST_CLI token.
        local rendered
        rendered="$(render_template "$src" "$dst")"
        printf '%s\n' "$rendered" > "$dst"
        # NFS-vs-bind for persistent volumes is decided by generate-compose.ts
        # (convertNfsVolumes): bind mount to volumes/<name>/ when NFS is unset,
        # NFS named volume when it's configured. Templates leave driver_opts intact.
    fi

    echo "  created: ${dst#"$REPO_DIR/"}"
    return 0
}

_process_templates_in() {
    local root="$1"; [[ -d "$root" ]] || return 0

    while IFS= read -r src; do
        if _process_one_template "$src"; then _STATS_CREATED=$(( _STATS_CREATED + 1 ))
        else _STATS_SKIPPED=$(( _STATS_SKIPPED + 1 ))
        fi
    done < <(find "$root" -name '*.exist.*' -type d \
        -not -path '*/graveyard/*' -not -path '*/.git/*' \
        -not -path '*/node_modules/*' -not -path '*/site/*' 2>/dev/null | sort)

    while IFS= read -r src; do
        if _process_one_template "$src"; then _STATS_CREATED=$(( _STATS_CREATED + 1 ))
        else _STATS_SKIPPED=$(( _STATS_SKIPPED + 1 ))
        fi
    done < <(find "$root" \( -name '*.exist.*' -o -name '*.env.exist' \) -type f \
        -not -path '*/graveyard/*' -not -path '*/.git/*' \
        -not -path '*/node_modules/*' -not -path '*/site/*' 2>/dev/null | sort)
}

# ── Main ──────────────────────────────────────────────────────────────────────
# Guarded so the file can be sourced (e.g. by src/test/unit/test-templates.sh) to load
# the functions without rendering anything. Runs only when executed directly.

_main() {
    if [[ -f "${REPO_DIR}/.env.exist.shared" ]]; then
        if _process_one_template "${REPO_DIR}/.env.exist.shared"; then
            _STATS_CREATED=$(( _STATS_CREATED + 1 ))
            _reload_env_shared
        else
            _STATS_SKIPPED=$(( _STATS_SKIPPED + 1 ))
        fi
    fi
    _load_env_shared

    while IFS= read -r svc_dir; do
        if service_is_enabled "$svc_dir"; then
            _process_templates_in "$svc_dir"
        fi
    done < <(_find_service_dirs)

    echo "Created ${_STATS_CREATED} file(s), skipped ${_STATS_SKIPPED} existing"
    if [[ "$_STATS_SKIPPED" -gt 0 ]]; then
        echo "  (use --force to regenerate existing files)"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _main
fi
