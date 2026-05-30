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

# ── NFS volume handling ───────────────────────────────────────────────────────

_comment_out_nfs_volumes() {
    local file="$1"
    local tmp; tmp=$(mktemp "${REPO_DIR}/.tmp.XXXXXX")
    trap 'rm -f "$tmp"' RETURN

    mapfile -t _lines < "$file"
    local -a _out=()
    local _i=0 _n=${#_lines[@]}

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
                _block+=("$_bl"); (( _j++ ))
            done
            local _has_truenas=0
            for _bl in "${_block[@]}"; do
                [[ "$_bl" == *EXIST_NFS_* ]] && { _has_truenas=1; break; }
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
            _out+=("$_line"); (( _i++ ))
        fi
    done

    printf '%s\n' "${_out[@]}" > "$tmp"
    mv "$tmp" "$file"
}

# ── Placeholder replacement ───────────────────────────────────────────────────

replace_placeholders() {
    local file="$1"

    # EXIST_* — substitute values already written to .env.shared.
    # Skip when $file IS .env.shared (would replace key names with their own values).
    if [[ -f "${REPO_DIR}/.env.shared" ]] && \
       [[ "$(realpath "$file" 2>/dev/null)" != "$(realpath "${REPO_DIR}/.env.shared" 2>/dev/null)" ]]; then
        while IFS='=' read -r key value || [[ -n "$key" ]]; do
            [[ "$key" =~ ^EXIST_ ]] || continue
            [[ -n "$key" && -n "$value" ]] || continue
            sed -i "s|${key}|${value}|g" "$file"
        done < "${REPO_DIR}/.env.shared"
    fi

    # Auto-generated — one replacement at a time so each occurrence gets a unique value
    local line_num val
    while grep -q "EXIST_24_CHAR_PASSWORD" "$file" 2>/dev/null; do
        line_num=$(grep -n "EXIST_24_CHAR_PASSWORD" "$file" | head -1 | cut -d: -f1)
        val=$(gen_password 24)
        sed -i "${line_num}s|EXIST_24_CHAR_PASSWORD|${val}|" "$file"
    done
    while grep -q "EXIST_32_CHAR_HEX_KEY" "$file" 2>/dev/null; do
        line_num=$(grep -n "EXIST_32_CHAR_HEX_KEY" "$file" | head -1 | cut -d: -f1)
        val=$(gen_hex 32)
        sed -i "${line_num}s|EXIST_32_CHAR_HEX_KEY|${val}|" "$file"
    done
    while grep -q "EXIST_64_CHAR_HEX_KEY" "$file" 2>/dev/null; do
        line_num=$(grep -n "EXIST_64_CHAR_HEX_KEY" "$file" | head -1 | cut -d: -f1)
        val=$(gen_hex 64)
        sed -i "${line_num}s|EXIST_64_CHAR_HEX_KEY|${val}|" "$file"
    done
    while grep -q "EXIST_TIMESTAMP" "$file" 2>/dev/null; do
        line_num=$(grep -n "EXIST_TIMESTAMP" "$file" | head -1 | cut -d: -f1)
        sed -i "${line_num}s|EXIST_TIMESTAMP|$(date +%Y%m%d_%H%M%S)|" "$file"
    done
    while grep -q "EXIST_UUID" "$file" 2>/dev/null; do
        line_num=$(grep -n "EXIST_UUID" "$file" | head -1 | cut -d: -f1)
        val=$(gen_uuid)
        sed -i "${line_num}s|EXIST_UUID|${val}|" "$file"
    done

    # EXIST_CLI — fzf text prompt.
    # Shows the contiguous comment block directly above the field as the fzf header.
    # If that block contains `# DEFAULT_FROM: EXIST_FOO`, the value of EXIST_FOO
    # (already written earlier in the same file) is used as the pre-filled default.
    while grep -q "EXIST_CLI" "$file" 2>/dev/null; do
        local match line_content key_name block_start prev_line context
        local default_from default_val escaped val
        match=$(grep -n "EXIST_CLI" "$file" | head -1)
        line_num="${match%%:*}"
        line_content="${match#*:}"
        key_name="${line_content%%=*}"

        block_start=$(( line_num - 1 ))
        while (( block_start >= 1 )); do
            prev_line=$(sed -n "${block_start}p" "$file")
            [[ "$prev_line" =~ ^[[:space:]]*# ]] || break
            (( block_start-- ))
        done
        (( block_start++ ))

        if (( block_start < line_num )); then
            context=$(sed -n "${block_start},$((line_num - 1))p" "$file")
        else
            context=""
        fi

        default_from=$(printf '%s\n' "$context" | \
            sed -n 's/^# *DEFAULT_FROM: *\([A-Z_][A-Z0-9_]*\) *$/\1/p' | head -1)
        default_val=""
        if [[ -n "$default_from" ]]; then
            default_val=$(grep -E "^${default_from}=" "$file" | head -1 | cut -d= -f2-)
        fi

        val=$(printf '\n' | fzf \
            --disabled --print-query --no-info \
            --layout=reverse --height=8 \
            --header="${context}" \
            --prompt="  ${key_name}: " \
            --query="${default_val}" 2>/dev/null | head -1) || val="${default_val}"

        escaped="${val//\\/\\\\}"
        escaped="${escaped//|/\\|}"
        sed -i "${line_num}s|EXIST_CLI|${escaped}|" "$file"
    done
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

    if [[ -e "$dst" ]] && [[ "$FORCE" != "true" ]]; then return 1; fi

    if [[ -d "$src" ]]; then
        cp -r "$src" "$dst"
        while IFS= read -r f; do replace_placeholders "$f"; done < <(find "$dst" -type f 2>/dev/null)
    else
        cp "$src" "$dst"
        replace_placeholders "$dst"
        if [[ "$dst" == */docker-compose.yml ]] && grep -q 'EXIST_NFS_SERVER_ADDRESS' "$dst" 2>/dev/null; then
            local nfs_addr=""
            nfs_addr=$(grep '^EXIST_NFS_SERVER_ADDRESS=' "${REPO_DIR}/.env.shared" 2>/dev/null | cut -d= -f2-)
            if [[ -z "$nfs_addr" || "$nfs_addr" == "EXIST_CLI" ]]; then
                _comment_out_nfs_volumes "$dst"
                echo "  note: NFS server not configured — NFS volumes commented out in ${dst#"$REPO_DIR/"}"
            fi
        fi
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
