#!/usr/bin/env bash
# exist.test.sh — validate that seaweedfs is operational.
#
# See .claude/reference/testing.md for the convention.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/test" && pwd)/exist-test.sh"
exist_self_elevate
exist_test_init "seaweedfs" EXIST_IS_NAS_SEAWEEDFS
skip_if_disabled

# S3 API on :8333 (caddy: seaweedfs-api.<domain>), Admin UI on :23646
# (caddy: seaweedfs.<domain>). /healthz is unauthenticated and proves only that
# the S3 gateway is accepting connections -- it does not touch the filer, the
# volume server, or the identities in s3.json. A seaweedfs whose s3.json has
# drifted from what nextcloud and the routines read would still pass both probes
# below, which is exactly the hole minIO's old test left open. The two rclone
# checks after them are the ones that matter.
http_probe "seaweedfs S3 /healthz (direct)" "http://seaweedfs:8333/healthz" 200
probe_caddy "seaweedfs S3 /healthz" seaweedfs-api /healthz 200

# The Admin UI is password-protected (-admin.user/-admin.password), so an
# unauthenticated GET is a 401 on a correctly configured instance.
http_probe_any "seaweedfs admin UI (direct)" "http://seaweedfs:23646/" "^(200|301|302|307|401)$"
probe_caddy_any "seaweedfs admin UI" seaweedfs / "^(200|301|302|307|401)$"

# Credentials actually authenticate. Configured entirely from RCLONE_CONFIG_* env
# (no rclone.conf written) -- the same pattern workspace-sync.sh uses. `lsd` is a
# read-only listing, so this writes nothing to the service.
#
# Unlike minIO's MC_HOST_ form, nothing is embedded in a URL here, so a password
# containing '/', '@' or ':' is no longer a problem.
_rclone_probe() {
    local label="$1" key="$2" secret="$3" remote="$4" hint="$5"
    if [ -z "$key" ] || [ -z "$secret" ]; then
        skip "$label" "credentials not set in nas/seaweedfs/.env"
        return 0
    fi
    if RCLONE_CONFIG_SW_TYPE=s3 \
       RCLONE_CONFIG_SW_PROVIDER=Other \
       RCLONE_CONFIG_SW_ENV_AUTH=false \
       RCLONE_CONFIG_SW_ENDPOINT="${SEAWEEDFS_URL:-http://seaweedfs:8333}" \
       RCLONE_CONFIG_SW_REGION="${SEAWEEDFS_REGION:-us-east-1}" \
       RCLONE_CONFIG_SW_ACCESS_KEY_ID="$key" \
       RCLONE_CONFIG_SW_SECRET_ACCESS_KEY="$secret" \
       rclone lsd "$remote" >/dev/null 2>&1; then
        ok "$label"
    else
        fail "$label" "rclone could not list ${remote}" "$hint"
    fi
}

if command -v rclone >/dev/null 2>&1; then
    load_env_exist
    _rclone_probe "seaweedfs root credentials authenticate" \
        "${SEAWEEDFS_ROOT_USER:-}" "${SEAWEEDFS_ROOT_PASSWORD:-}" "sw:" \
        "Check SEAWEEDFS_ROOT_USER/PASSWORD in nas/seaweedfs/.env against nas/seaweedfs/s3.json"
    # The scoped identity nextcloud mounts /S3 with. Rendered into s3.json once and
    # into nas/nextcloud/.env separately -- if those two drift, the /S3 mount lists
    # nothing and this is the only thing that says so.
    _rclone_probe "seaweedfs nextcloud identity reaches its bucket" \
        "${SEAWEEDFS_NEXTCLOUD_ACCESS_KEY:-}" "${SEAWEEDFS_NEXTCLOUD_SECRET_KEY:-}" "sw:nextcloud" \
        "s3.json and nas/nextcloud/.env disagree — compare against EXIST_S3_NEXTCLOUD_* in .env.shared"
else
    skip "seaweedfs credentials authenticate" "rclone not installed in this container"
fi

finish
