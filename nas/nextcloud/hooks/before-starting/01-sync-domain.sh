#!/bin/sh
# nextcloud — re-apply trusted_domains from the environment on every start.
#
# NEXTCLOUD_TRUSTED_DOMAINS is read by the image's installer ONCE, on the very
# first run, and written into config/config.php as trusted_domains — after
# that the environment is ignored (image /entrypoint.sh's install block only
# consults it inside `if [ "$installed_version" = "0.0.0.0" ]`).
#
# That makes EXIST_DOMAIN a one-way door for this one setting: change it and
# Nextcloud answers "Access through untrusted domain" on the new hostname,
# while everything else in the stack follows the new name immediately (caddy
# reads {$CADDY_DOMAIN} at runtime, dashy-conf.yml and honcho's config.toml are
# always-rendered). trusted_domains was the one thing that did not, so the
# stack ended up half-moved.
#
# TRUSTED_PROXIES/OVERWRITEHOST/OVERWRITEPROTOCOL/OVERWRITECLIURL do NOT need
# this treatment and are deliberately NOT handled here (an earlier version of
# this script re-applied all five via occ, which was dead work for four of
# them — see docker-compose.exist.yml's environment comment for the verified
# reason: the installer also drops config/reverse-proxy.config.php into the
# live config dir, and that file's getenv() calls are re-evaluated on every
# PHP request, already overriding config.php's stale copy for free).
#
# `before-starting` is the image's own hook directory, run on EVERY start,
# after the install/upgrade steps and with the database up, so occ is usable
# here. `occ config:system:set` is idempotent, which is why this can run
# unconditionally and needs no sentinel — it converges, then stays quiet.
#
# Needs the exec bit: the image's run_path skips hook scripts without it.
set -eu

_occ() { php /var/www/html/occ "$@" >/dev/null 2>&1 || return 1; }

# Only meaningful once the instance exists. On a truly fresh container the
# post-installation hook has already run by now, but guard anyway rather than
# spraying errors during a failed install.
if ! php /var/www/html/occ status 2>/dev/null | grep -q 'installed: true'; then
    echo "[nextcloud] not installed yet — skipping domain sync."
    exit 0
fi

# trusted_domains is an indexed list. Index 0 is left alone: the installer puts
# the container's own name there and Nextcloud needs it for internal requests.
if [ -n "${NEXTCLOUD_TRUSTED_DOMAINS:-}" ]; then
    _cur=$(php /var/www/html/occ config:system:get trusted_domains 1 2>/dev/null || echo "")
    if [ "$_cur" != "$NEXTCLOUD_TRUSTED_DOMAINS" ]; then
        if _occ config:system:set trusted_domains 1 --value="$NEXTCLOUD_TRUSTED_DOMAINS"; then
            echo "[nextcloud] trusted_domains re-synced from the environment: ${NEXTCLOUD_TRUSTED_DOMAINS}"
        fi
    fi
fi
