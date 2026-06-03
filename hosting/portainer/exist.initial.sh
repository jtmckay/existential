#!/usr/bin/env bash
# Portainer — ensure the admin password file exists with correct permissions
# before docker compose up. Portainer reads this at startup via
# --admin-password-file so the file must exist before the container starts.
#
# Idempotent: generates the file on first run, only fixes permissions on
# subsequent runs. Runs every time ./existential.sh is called.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASSWORD_FILE="${SCRIPT_DIR}/portainer_password.txt"

if [[ ! -f "$PASSWORD_FILE" ]]; then
    password=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)
    install -m 600 /dev/null "$PASSWORD_FILE"
    printf '%s' "$password" > "$PASSWORD_FILE"
    echo "[portainer] Generated admin password → ${PASSWORD_FILE}"
    echo "            Save this value — it is not stored elsewhere."
    echo "            Password: ${password}"
else
    chmod 600 "$PASSWORD_FILE"
fi
