#!/usr/bin/env bash
# hermes — pre-startup init
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Skip when running inside a container — docker socket not available in adhoc.
if [[ "${IN_CONTAINER:-}" == "1" ]]; then
    exit 0
fi

# Pre-populate hermes build trees from the image so stage2-hook.sh skips its
# 5-min recursive chown on every container restart. The hook gates the entire
# chown block on .venv ownership: if .venv is already uid ${EXIST_PUID:-1000},
# it skips chowning .venv, ui-tui, gateway, and node_modules.
#
# We extract once per image version (tracked by image digest in .image_id).
# On fresh clone or after a new image pull: re-extracts and chowns on the host
# (~1 min, much faster than overlayfs chown inside the container).
_ensure_hermes_install() {
    local cache_dir="${SCRIPT_DIR}/hermes_install"
    local image
    image=$(grep -m1 'image:.*hermes-agent' "${SCRIPT_DIR}/docker-compose.yml" \
            | sed 's/[[:space:]]*image:[[:space:]]*//')

    if [[ -z "${image:-}" ]]; then
        echo "[hermes] Could not find hermes-agent image in docker-compose.yml — skipping build cache." >&2
        return 0
    fi

    local img_id
    img_id=$(docker inspect --format='{{.Id}}' "$image" 2>/dev/null) || {
        echo "[hermes] Image $image not pulled yet — pull it, then re-run ./existential.sh run." >&2
        return 0
    }

    if [[ -f "${cache_dir}/.image_id" ]] && \
       [[ "$(cat "${cache_dir}/.image_id")" == "$img_id" ]] && \
       [[ -d "${cache_dir}/.venv" ]]; then
        echo "[hermes] Build cache current (${image##*:})."
        return 0
    fi

    echo "[hermes] Extracting build trees from image (one-time per version, ~1 min)..."
    rm -rf "${cache_dir:?}"/.venv "${cache_dir}"/ui-tui "${cache_dir}"/gateway "${cache_dir}"/node_modules "${cache_dir}"/.image_id

    local cid
    cid=$(docker create "$image" 2>/dev/null)

    for tree in .venv ui-tui gateway node_modules; do
        printf "[hermes]   %-14s " "$tree"
        if docker cp "${cid}:/opt/hermes/${tree}" "${cache_dir}/" 2>/dev/null; then
            echo "ok"
        else
            echo "(not in image, skipping)"
        fi
    done

    docker rm "$cid" >/dev/null 2>&1

    local uid="${EXIST_PUID:-$(id -u)}"
    local gid="${EXIST_PGID:-$(id -g)}"
    echo "[hermes] Chowning cache to ${uid}:${gid}..."
    chown -R "${uid}:${gid}" "$cache_dir"
    echo "$img_id" > "${cache_dir}/.image_id"
    echo "[hermes] Build cache ready — future container restarts will skip the chown."
}

_ensure_hermes_install

# Install honcho-ai into the cached venv so the honcho memory plugin is importable.
# Runs after _ensure_hermes_install so the venv is guaranteed to exist.
_ensure_honcho_ai() {
    local venv="${SCRIPT_DIR}/hermes_install/.venv"
    if [[ ! -d "${venv}" ]]; then
        echo "[hermes] .venv not yet extracted — honcho-ai will be installed on next run." >&2
        return 0
    fi
    if "${venv}/bin/python" -c "import honcho" 2>/dev/null; then
        echo "[hermes] honcho-ai already installed."
        return 0
    fi
    local image
    image=$(grep -m1 'image:.*hermes-agent' "${SCRIPT_DIR}/docker-compose.yml" \
            | sed 's/[[:space:]]*image:[[:space:]]*//')
    echo "[hermes] Installing honcho-ai==2.1.2 into venv..."
    docker run --rm \
        -v "${venv}:/opt/hermes/.venv" \
        -e UV_LINK_MODE=copy \
        --entrypoint uv \
        "${image}" \
        pip install "honcho-ai==2.1.2" --python /opt/hermes/.venv/bin/python
    echo "[hermes] honcho-ai installed."
}

_ensure_honcho_ai
