#!/usr/bin/env sh
# ntfy — first-boot user provisioning, alongside the real server.
#
# server.yml sets auth-default-access: deny-all, so a fresh ntfy rejects every
# publish until users exist. Creating them is a container-local job — it needs
# the ntfy binary and the auth database, neither of which the host has — which
# is why this is an entrypoint rather than exist.initial.sh.
#
# The ordering is forced by ntfy itself: `ntfy user add` refuses to run until
# the auth file exists ("please start the server at least once to create it"),
# and only `ntfy serve` creates it. So provisioning runs in the BACKGROUND,
# waiting for that file, while serve takes the foreground as PID 1. Users land
# a second or two after startup; ntfy reads the auth database per request (the
# ACL cache is off by default), so they take effect with no restart.
#
# Idempotent, no sentinels: `ntfy user add --ignore-exists` is a no-op on a
# user that's already there (verified against a real v2.27.0 container — exit
# 0, password untouched), so a restart does nothing and a hand-edited user is
# left alone. The auth database IS the state.
set -eu

AUTH_FILE="${NTFY_AUTH_FILE:-/var/lib/ntfy/user.db}"

_provision() {
    # Wait for serve to create the auth file. Bounded: if it never appears the
    # server is failing for its own reasons and a silent retry loop would only
    # hide that.
    _waited=0
    while [ ! -f "$AUTH_FILE" ]; do
        if [ "$_waited" -ge 60 ]; then
            echo "[ntfy] ${AUTH_FILE} never appeared — users not provisioned." >&2
            return 1
        fi
        sleep 1
        _waited=$((_waited + 1))
    done

    # The admin: the login for the web UI and the mobile apps. Never publishes.
    # `--ignore-exists` prints its own "already exists"/"added" line, so this
    # needs no branch of its own.
    if [ -n "${NTFY_ADMIN_USER:-}" ] && [ -n "${NTFY_ADMIN_PASSWORD:-}" ]; then
        NTFY_PASSWORD="$NTFY_ADMIN_PASSWORD" \
            ntfy user add --role=admin --ignore-exists "$NTFY_ADMIN_USER"
    fi

    # The bot: the identity decree and every other service publishes as. A plain
    # user rather than an admin, so a leaked credential can post notifications
    # and nothing else — it cannot add users, mint tokens, or read the auth
    # database.
    if [ -n "${NTFY_BOT_USER:-}" ] && [ -n "${NTFY_BOT_PASSWORD:-}" ]; then
        NTFY_PASSWORD="$NTFY_BOT_PASSWORD" \
            ntfy user add --ignore-exists "$NTFY_BOT_USER"
        # Re-applied every boot on purpose: this is the one thing that must
        # track NTFY_BOT_TOPICS, and `ntfy access` replaces the rule for a
        # topic pattern rather than stacking duplicates.
        ntfy access "$NTFY_BOT_USER" "${NTFY_BOT_TOPICS:-*}" rw
        echo "[ntfy] ${NTFY_BOT_USER} may publish to ${NTFY_BOT_TOPICS:-*}."
    fi
}

# Never take the server down over a provisioning failure: a running ntfy with
# no bot is a bad notification path, but an ntfy that will not start is worse.
_provision || echo "[ntfy] User provisioning failed — see above." >&2 &

exec ntfy "$@"
