#!/usr/bin/env bash
# service-common.sh — shared service-enablement + env helpers.
#
# Sourced only (never executed directly — see CLAUDE.md "src/utils/"). Both the
# host entry point (existential.sh) and the in-container renderer (src/templates.sh)
# need the same logic for "is this service enabled?" and "load .env.shared"; this
# is the single source of truth so the two can't drift.
#
# Contract: the caller must have $SCRIPT_DIR pointing at the repo root before any
# of these functions run. existential.sh sets it directly; templates.sh aliases
# SCRIPT_DIR="$REPO_DIR". Functions read $SCRIPT_DIR at call time so a test can
# override it after sourcing.
#
# No `set -e`/shebang side effects here — sourcing must not change the caller's
# shell options.

# Category scan order — hosting first so host-level setup (daemon config,
# password files) completes before service-level scripts run.
SERVICE_CATEGORIES=(hosting nas ai services)

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
_reload_env_shared() { _env_shared_loaded=0; _load_env_shared; }

# Map a service directory (…/<category>/<slug>) → its EXIST_IS_<CAT>_<SLUG> var.
_enable_var_for() {
    local rel="${1#"$SCRIPT_DIR"/}"
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
        [[ -d "${SCRIPT_DIR}/${cat}" ]] || continue
        find "${SCRIPT_DIR}/${cat}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null
    done | sort
}
