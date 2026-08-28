#!/usr/bin/env bash
# exist.initial.sh — pre-startup setup for nextcloud.
#
# The nextcloud image ships its runtime config as *fragments* in
# /usr/src/nextcloud/config/ — small files that read getenv() on every request:
#
#   reverse-proxy.config.php   OVERWRITEHOST / OVERWRITEPROTOCOL / OVERWRITECLIURL
#                              / TRUSTED_PROXIES  ← without it, caddy access is
#                              redirected to http:// and the client IP is lost
#   redis.config.php           REDIS_HOST ← memcache + transactional file locking
#   apcu / apps / s3 / smtp / swift / apache-pretty-urls
#
# They are the reason this service can follow the repo's "prefer runtime env over
# render-time baking" rule: nothing is stamped into config.php, so changing
# EXIST_DOMAIN takes effect on the next container start with no re-render.
#
# The image only installs them into a config dir it considers EMPTY:
#
#   for dir in config data custom_apps themes; do
#       if [ ! -d "/var/www/html/$dir" ] || directory_empty "/var/www/html/$dir"; then
#
# and volumes/nextcloud_config/ ships a committed .gitkeep (see
# .claude/reference/volumes.md — every bind dir gets one so a fresh clone has the
# directory and Docker doesn't root-create it with the wrong owner). That one
# file makes directory_empty false, the fragments are never copied, and the
# failure is silent: nextcloud installs and serves, but proxied requests redirect
# to http:// and redis caching is quietly inactive.
#
# So: drop the .gitkeep once it has done its job — it exists to survive `git
# clone`, and by the time this runs the directory is already on disk with the
# right owner. Only ever removed when it is the ONLY thing there, so an install
# that already has a config.php is untouched.
#
# Idempotent, no sentinel: the condition IS the state. Nothing to do on a
# configured instance, and nothing to do once the fragments are in place.
#
# See .claude/reference/services.md for the convention.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_DIR="${EXIST_NFS_HOST_MOUNT:-${REPO_DIR}/volumes}/nextcloud_config"

[ -d "$CONFIG_DIR" ] || exit 0

# Anything besides .gitkeep means the image has already populated this (or the
# user has their own config) — leave it completely alone.
for f in "$CONFIG_DIR"/* "$CONFIG_DIR"/.[!.]*; do
    [ -e "$f" ] || continue
    [ "$(basename "$f")" = ".gitkeep" ] && continue
    exit 0
done

[ -e "${CONFIG_DIR}/.gitkeep" ] || exit 0

rm -f "${CONFIG_DIR}/.gitkeep"
echo "  nextcloud: cleared .gitkeep from nextcloud_config/ so the image installs its"
echo "             config fragments (reverse-proxy, redis) on first start"
