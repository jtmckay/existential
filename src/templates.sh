#!/usr/bin/env bash
# render-templates.sh — process *.exist.* template files inside existential-adhoc.
# Run via: run_adhoc env FORCE=false bash /src/render-templates.sh
set -euo pipefail

REPO_DIR="${REPO_DIR:-/repo}"
FORCE="${FORCE:-false}"

# Shared service-enablement + env helpers read $SCRIPT_DIR as the repo root;
# here that is REPO_DIR. Provides SERVICE_CATEGORIES, _load_env_shared,
# _reload_env_shared, _enable_var_for, service_is_enabled, _find_service_dirs.
SCRIPT_DIR="${REPO_DIR}"

. /src/utils/generate_password.sh
. /src/utils/generate_hex_key.sh
. /src/utils/service-common.sh

# ── Generators ────────────────────────────────────────────────────────────────

gen_password() { generate_24_char_password; }
gen_hex()      { generate_hex_key "${1:-32}"; }
gen_uuid()     {
    if command -v uuidgen &>/dev/null; then uuidgen | tr '[:upper:]' '[:lower:]'
    else cat /proc/sys/kernel/random/uuid
    fi
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
        local key value _escaped k
        local -a _keys=()
        local -A _vals=()
        while IFS='=' read -r key value || [[ -n "$key" ]]; do
            [[ "$key" =~ ^EXIST_ ]] || continue
            [[ -n "$key" && -n "$value" ]] || continue
            _keys+=("$key")
            _vals["$key"]="$value"
        done < "${REPO_DIR}/.env.shared"

        # Build the substitutions longest-key-first so a shorter key (EXIST_FOO)
        # can't rewrite the prefix of a longer one (EXIST_FOOBAR). The bare-token
        # form is anchored on a trailing word boundary (\b) for the same reason and
        # so a key name embedded in unrelated text can't be silently replaced with
        # a secret value.
        local -a sed_args=()
        if [[ ${#_keys[@]} -gt 0 ]]; then
            while IFS= read -r k; do
                _escaped="${_vals[$k]//\\/\\\\}"
                _escaped="${_escaped//&/\\&}"
                _escaped="${_escaped//|/\\|}"
                sed_args+=(-e "s|\\\${${k}[^}]*}|${_escaped}|g" -e "s|${k}\\b|${_escaped}|g")
            done < <(printf '%s\n' "${_keys[@]}" | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2-)
        fi
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

# Rendered files that hold secrets (DB passwords, API keys, private keys) must
# not be world/group-readable. chmod 600 anything that looks like a credential
# file so a fresh render never leaves secrets at the default umask (664/644).
_secure_if_secret() {
    local f="$1" base; base="$(basename "$f")"
    case "$base" in
        .env|.env.*|*.pem|*_password*.txt) chmod 600 "$f" 2>/dev/null || true ;;
    esac
}

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
            _secure_if_secret "$f"
        done < <(find "$dst" -type f 2>/dev/null)
    else
        # Resolve every placeholder in memory, then write the destination once.
        # If the user aborts mid-prompt, render_template never returns, so the
        # destination is never written and can't hold a literal EXIST_CLI token.
        local rendered
        rendered="$(render_template "$src" "$dst")"
        printf '%s\n' "$rendered" > "$dst"
        _secure_if_secret "$dst"
        # Every volume becomes a host bind mount in generate-compose.ts
        # (materializeBindMounts): ${EXIST_NFS_HOST_MOUNT}/<name> for NFS-marked
        # volumes when a host mount is set, else volumes/<name>/. The top-level
        # volumes: block here is just the declaration source it reads.
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
