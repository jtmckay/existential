#!/bin/sh
# nextcloud — nothing phones home.
#
#   updatechecker=false — the update check sends more than a version request:
#   install time, PHP version and a user-count bucket. The image tag pins the
#   version here anyway, so the in-app notice has nothing to offer.
#
#   survey_client — shipped enabled; it nags the admin to send monthly usage
#   statistics. Disabled, so there is nothing to opt in to.
#
# Runs on every start (before-starting); both commands are idempotent.
# Needs the exec bit: the image's run_path skips hook scripts without it.
# Exits 0 on every path: a failing before-starting hook stops apache starting.
set -u

occ() { php /var/www/html/occ "$@" >/dev/null 2>&1; }

if ! php /var/www/html/occ status 2>/dev/null | grep -q 'installed: true'; then
    exit 0
fi

occ config:system:set updatechecker --type=boolean --value=false \
    || echo "[nextcloud] WARNING: could not turn off the update check"
occ app:disable survey_client || true

exit 0
