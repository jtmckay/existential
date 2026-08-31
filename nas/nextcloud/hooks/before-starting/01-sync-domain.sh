#!/bin/sh
# nextcloud — re-apply the domain/proxy settings from the environment on every start.
#
# NEXTCLOUD_TRUSTED_DOMAINS, OVERWRITEHOST, OVERWRITEPROTOCOL, OVERWRITECLIURL and
# TRUSTED_PROXIES are read by the image's installer ONCE, on the very first run,
# and written into config/config.php. After that the environment is ignored — the
# compose template says as much, and its suggested remedy was "nuke your Nextcloud
# volumes and start over".
#
# That makes EXIST_DOMAIN a one-way door: change it and Nextcloud answers "Access
# through untrusted domain" on the new hostname, while everything else in the
# stack follows the new name immediately (caddy reads {$CADDY_DOMAIN} at runtime,
# dashy-conf.yml and honcho's config.toml are always-rendered). Nextcloud was the
# one thing that did not, so the stack ended up half-moved.
#
# `before-starting` is the image's own hook that runs on EVERY start, after the
# install/upgrade steps and with the database up, so occ is usable here. Each
# `occ config:system:set` is idempotent, which is why this can run unconditionally
# and needs no sentinel — it converges, then stays quiet.
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

_changed=""

# trusted_domains is an indexed list. Index 0 is left alone: the installer puts
# the container's own name there and Nextcloud needs it for internal requests.
if [ -n "${NEXTCLOUD_TRUSTED_DOMAINS:-}" ]; then
    _cur=$(php /var/www/html/occ config:system:get trusted_domains 1 2>/dev/null || echo "")
    if [ "$_cur" != "$NEXTCLOUD_TRUSTED_DOMAINS" ]; then
        _occ config:system:set trusted_domains 1 --value="$NEXTCLOUD_TRUSTED_DOMAINS" \
            && _changed="${_changed} trusted_domains=${NEXTCLOUD_TRUSTED_DOMAINS}"
    fi
fi

# overwrite* tell Nextcloud what URL it is reached on, which is what generates
# correct links and redirects behind caddy.
for _pair in \
    "overwritehost:${OVERWRITEHOST:-}" \
    "overwriteprotocol:${OVERWRITEPROTOCOL:-}" \
    "overwrite.cli.url:${OVERWRITECLIURL:-}"
do
    _key=${_pair%%:*}
    _val=${_pair#*:}
    [ -n "$_val" ] || continue
    _cur=$(php /var/www/html/occ config:system:get "$_key" 2>/dev/null || echo "")
    if [ "$_cur" != "$_val" ]; then
        _occ config:system:set "$_key" --value="$_val" && _changed="${_changed} ${_key}=${_val}"
    fi
done

# trusted_proxies is a list like trusted_domains, but here index 0 IS ours: the
# docker bridge caddy sits on. Without it Nextcloud sees caddy's address as the
# client and every request looks like it came from the proxy.
if [ -n "${TRUSTED_PROXIES:-}" ]; then
    _cur=$(php /var/www/html/occ config:system:get trusted_proxies 0 2>/dev/null || echo "")
    if [ "$_cur" != "$TRUSTED_PROXIES" ]; then
        _occ config:system:set trusted_proxies 0 --value="$TRUSTED_PROXIES" \
            && _changed="${_changed} trusted_proxies=${TRUSTED_PROXIES}"
    fi
fi

if [ -n "$_changed" ]; then
    echo "[nextcloud] domain config re-synced from the environment:${_changed}"
fi
