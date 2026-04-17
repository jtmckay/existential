#!/usr/bin/env bash
# Decree Setup
#
# Discovers routine setup scripts in .decree/setup/ and walks through
# enabling them one at a time. After each successful setup the routine
# is enabled in config.yml.
#
# Run on the host (from any directory):
#   bash services/decree/setup.sh
#
# Run inside the decree container:
#   docker exec -it decree bash /work/.decree/setup.sh
#
# Requires: bash 4+

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "${IN_CONTAINER:-}" = "1" ]; then
    DECREE_DIR="/work/.decree"
    SECRETS_DIR="/config"
else
    DECREE_DIR="${SCRIPT_DIR}/daemon/.decree"
    SECRETS_DIR="${SCRIPT_DIR}/secrets"
fi

export DECREE_DIR SECRETS_DIR

SETUP_DIR="${DECREE_DIR}/setup"
CONFIG="${DECREE_DIR}/config.yml"

# ── Helpers ───────────────────────────────────────────────────────────────────

hr() { printf '%0.s═' {1..56}; echo; }

# Returns "yes" if the routine has enabled: true in config.yml, "no" otherwise.
is_enabled() {
    local routine="$1"
    awk -v r="  ${routine}:" '
        $0 == r { found=1; next }
        found && /enabled:/ { print (/true/ ? "yes" : "no"); exit }
        found && /^  [^ ]/ { print "no"; exit }
    ' "$CONFIG"
}

# Sets enabled: true for a routine in config.yml (atomic write).
enable_routine() {
    local routine="$1"
    awk -v r="  ${routine}:" '
        $0 == r { found=1 }
        found && /enabled:/ { sub(/enabled: .*/, "enabled: true"); found=0 }
        { print }
    ' "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"
}

# ── Guards ────────────────────────────────────────────────────────────────────

if [ ! -f "$CONFIG" ]; then
    echo "Config not found: ${CONFIG}"
    exit 1
fi

if [ ! -d "$SETUP_DIR" ]; then
    echo "No setup directory found at ${SETUP_DIR}"
    exit 0
fi

# ── Main loop ─────────────────────────────────────────────────────────────────

while true; do
    echo ""
    hr
    echo "  Decree Setup"
    hr
    echo ""

    ROUTINES=()
    i=1
    for script in "${SETUP_DIR}"/*.sh; do
        [ -f "$script" ] || continue
        routine="$(basename "$script" .sh)"
        ROUTINES+=("$routine")
        status="$(is_enabled "$routine")"
        if [ "$status" = "yes" ]; then
            printf '  [%d] %-24s enabled\n' "$i" "$routine"
        elif [ "$status" = "no" ]; then
            printf '  [%d] %-24s not enabled\n' "$i" "$routine"
        else
            # No matching routine in config.yml — infrastructure setup script
            printf '  [%d] %-24s\n' "$i" "$routine"
        fi
        i=$(( i + 1 ))
    done

    if [ ${#ROUTINES[@]} -eq 0 ]; then
        echo "  No setup scripts found in ${SETUP_DIR}"
        echo ""
        exit 0
    fi

    echo ""
    echo "  [q] quit"
    echo ""

    read -rp "Select a routine to set up: " choice

    if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
        echo ""
        exit 0
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && \
       [ "$choice" -ge 1 ]         && \
       [ "$choice" -le "${#ROUTINES[@]}" ]; then

        routine="${ROUTINES[$((choice - 1))]}"
        script="${SETUP_DIR}/${routine}.sh"

        echo ""
        hr
        echo "  Setting up: ${routine}"
        hr
        echo ""

        if bash "$script"; then
            in_config="$(is_enabled "$routine")"
            if [ -n "$in_config" ]; then
                enable_routine "$routine"
                echo ""
                echo "  Routine '${routine}' enabled in config.yml."
                echo "  Restart the daemon to apply: docker compose restart decree"
            else
                echo ""
                echo "  Setup complete."
            fi
        else
            echo ""
            echo "  Setup did not complete."
            [ -n "$(is_enabled "$routine")" ] && \
                echo "  Routine '${routine}' remains disabled."
        fi

        echo ""
        read -rp "Press Enter to return to the menu..." _
    else
        echo "  Invalid selection."
        sleep 1
    fi
done
