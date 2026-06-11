#!/usr/bin/env bash
# Compares pinned container image tags against latest available versions.
#
# Usage (via existential.sh):
#   ./existential.sh run check-versions            — show version table
#   ./existential.sh run check-versions --update   — apply updates to .exist.yml files
#
# Usage (direct — self-elevates into adhoc container):
#   src/lib/check-versions.sh [--update]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${IN_CONTAINER:-}" ]]; then
    REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
    exec docker compose -f "$REPO/existential-compose.yml" run --rm \
        existential-adhoc bash /src/lib/check-versions.sh "$@"
fi

REPO="/repo"

UPDATE=false
[[ "${1:-}" == "--update" ]] && UPDATE=true

# ── Fetch helpers ─────────────────────────────────────────────────────────────

# latest_github <owner/repo>
# Latest stable (non-pre-release, non-draft) release tag, v-prefix stripped.
# Scans up to 20 releases and skips both the prerelease API flag and common
# RC/alpha/beta patterns in the tag name itself.
latest_github() {
    local repo="$1"
    curl -fsSL --max-time 15 \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${repo}/releases?per_page=20" 2>/dev/null \
        | jq -r '
            [.[]
             | select(.prerelease == false and .draft == false)
             | select(.tag_name | test("rc|alpha|beta|pre\\.?[0-9]"; "i") | not)
             | .tag_name
            ][0] // ""
          ' \
        | sed 's/^v//'
}

# latest_hub <org/image>
# Highest-versioned tag from Docker Hub that looks like semver (digits + dots +
# optional single-word suffix), v-prefix stripped.  Returns tags like "3.2.1" or
# "7-alpine" — call latest_hub_clean when you only want bare digits-and-dots.
# Sorts by version (sort -V), not by upload time: Docker Hub re-pushes old LTS
# tags, so "most recently updated" is not "newest version" (portainer 2.39 vs 2.42).
latest_hub() {
    local path="$1"
    curl -fsSL --max-time 15 \
        "https://registry.hub.docker.com/v2/repositories/${path}/tags?page_size=100&ordering=last_updated" \
        2>/dev/null \
        | jq -r '.results[].name' 2>/dev/null \
        | grep -E '^v?[0-9]+\.[0-9]+' \
        | grep -vE '(rc|alpha|beta|dev|edge|nightly|sha-|-arm|-amd64|-linux|-windows|unstable)' \
        | sed 's/^v//' \
        | sort -V | tail -1
}

# latest_hub_clean <org/image>
# Like latest_hub but only returns pure digit-and-dot tags (no flavor suffixes
# like -alpine, -fpm, -builder, -rocm).  Use this for images where the plain
# version tag is the right choice (caddy, nextcloud, portainer, ollama …).
# Also sorts by version, not upload time (see latest_hub).
latest_hub_clean() {
    local path="$1"
    curl -fsSL --max-time 15 \
        "https://registry.hub.docker.com/v2/repositories/${path}/tags?page_size=100&ordering=last_updated" \
        2>/dev/null \
        | jq -r '.results[].name' 2>/dev/null \
        | grep -E '^[0-9]+(\.[0-9]+)+$' \
        | sort -V | tail -1
}

# latest_hub_release <org/image>
# Newest MinIO-style RELEASE.<timestamp> tag from Docker Hub. The timestamp
# format sorts lexically in chronological order, so a plain sort works. Excludes
# microarch variants (-cpuv1) and floating latest/cicd tags. Needed because
# MinIO stopped pushing newer RELEASE tags to Docker Hub while still cutting
# GitHub releases — checking GitHub would point at a tag that isn't pullable.
latest_hub_release() {
    local path="$1"
    curl -fsSL --max-time 15 \
        "https://registry.hub.docker.com/v2/repositories/${path}/tags?page_size=100&ordering=last_updated" \
        2>/dev/null \
        | jq -r '.results[].name' 2>/dev/null \
        | grep -E '^RELEASE\.' \
        | grep -vE '(-cpuv|-cicd|latest)' \
        | sort | tail -1
}

# image_exists <image_prefix> <tag>
# Checks whether <image_prefix>:<tag> is actually pullable from the registry the
# image comes from (GHCR for ghcr.io/* prefixes, else Docker Hub). This catches a
# tag that exists upstream on GitHub but was never published to the pull registry
# — minio's RELEASE.* tags read as "up to date" yet 404 on `docker pull`.
# Exit: 0 = exists (manifest 200), 1 = confirmed missing (404),
#       2 = unverifiable (auth/network failure — caller should not hard-fail).
image_exists() {
    local prefix="$1" tag="$2" registry repo token url
    if [[ "$prefix" == ghcr.io/* ]]; then
        registry="ghcr.io"
        repo="${prefix#ghcr.io/}"
        token=$(curl -fsSL --max-time 15 \
            "https://ghcr.io/token?scope=repository:${repo}:pull" 2>/dev/null \
            | jq -r '.token // empty')
    else
        registry="registry-1.docker.io"
        repo="$prefix"
        [[ "$repo" == */* ]] || repo="library/${repo}"   # official images live under library/
        token=$(curl -fsSL --max-time 15 \
            "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${repo}:pull" \
            2>/dev/null | jq -r '.token // empty')
    fi
    [[ -n "$token" ]] || return 2

    url="https://${registry}/v2/${repo}/manifests/${tag}"
    local code
    code=$(curl -sSL -o /dev/null -w '%{http_code}' --max-time 15 \
        -H "Authorization: Bearer ${token}" \
        -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
        -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" \
        -H "Accept: application/vnd.oci.image.index.v1+json" \
        -H "Accept: application/vnd.oci.image.manifest.v1+json" \
        "$url" 2>/dev/null || true)

    case "$code" in
        200) return 0 ;;
        404) return 1 ;;
        *)   return 2 ;;   # 401/429/5xx/empty → unverifiable, don't hard-fail
    esac
}

# ── Lookup table ──────────────────────────────────────────────────────────────
# Columns (tab-separated):
#   display_name  file  image_prefix  check_type  check_arg  tag_format
#
# check_type : github | hub | hub_clean | hub_release | skip
# check_arg  : github → owner/repo   hub* → org/image (library/X for official)
# tag_format : flavor suffix appended to the fetched (v-stripped) version
#   bare      → no suffix
#   <suffix>  → append suffix (e.g. "-cpu" for whisper)
#   v         → no suffix; marks the v-prefix as the default for an *untagged*
#               image. For an already-pinned image the v-prefix is copied from
#               the file's current tag, so v vs bare is irrelevant once pinned.
#
# Add "skip" as check_type for images that need manual version management
# (complex release schemes, variant-only images, etc.).

declare -a CHECKS=(
    "actual-budget	services/actual-budget/docker-compose.exist.yml	actualbudget/actual-server	github	actualbudget/actual	bare"
    "appsmith	services/appsmith/docker-compose.exist.yml	appsmith/appsmith-ce	hub	appsmith/appsmith-ce	v"
    "caddy	hosting/caddy/docker-compose.exist.yml	caddy	hub_clean	library/caddy	bare"
    "chatterbox	ai/chatterbox/docker-compose.exist.yml	ghcr.io/devnen/chatterbox-tts-server	github	devnen/chatterbox-tts-server	v"
    "comfyui	ai/comfyui/docker-compose.exist.yml	ghcr.io/ai-dock/comfyui	skip		"
    "collabora	nas/collabora/docker-compose.exist.yml	collabora/code	hub_clean	collabora/code	bare"
    "dashy	services/dashy/docker-compose.exist.yml	lissy93/dashy	github	Lissy93/Dashy	bare"
    "hermes-agent	ai/hermes/docker-compose.exist.yml	nousresearch/hermes-agent	hub	nousresearch/hermes-agent	v"
    "hermes-workspace	ai/hermes/docker-compose.exist.yml	ghcr.io/outsourc-e/hermes-workspace	github	outsourc-e/hermes-workspace	v"
    "home-assistant	services/homeassistant/docker-compose.exist.yml	ghcr.io/home-assistant/home-assistant	github	home-assistant/core	bare"
    "it-tools	services/it-tools/docker-compose.exist.yml	corentinth/it-tools	github	CorentinTh/it-tools	bare"
    "lightrag	ai/lightrag/docker-compose.exist.yml	ghcr.io/hkuds/lightrag	github	HKUDS/LightRAG	v"
    "lowcoder	services/lowcoder/docker-compose.exist.yml	lowcoderorg/lowcoder-ce-api-service	hub_clean	lowcoderorg/lowcoder-ce-api-service	bare"
    "mealie	services/mealie/docker-compose.exist.yml	ghcr.io/mealie-recipes/mealie	github	mealie-recipes/mealie	v"
    "minio	nas/minio/docker-compose.exist.yml	minio/minio	hub_release	minio/minio	bare"
    "nextcloud	nas/nextcloud/docker-compose.exist.yml	nextcloud	hub_clean	library/nextcloud	bare"
    "nocodb	services/nocodb/docker-compose.exist.yml	nocodb/nocodb	github	nocodb/nocodb	bare"
    "ntfy	services/ntfy/docker-compose.exist.yml	binwiederhier/ntfy	github	binwiederhier/ntfy	v"
    "ollama	ai/ollama/docker-compose.exist.yml	ollama/ollama	hub_clean	ollama/ollama	bare"
    "open-webui	ai/open-webui/docker-compose.exist.yml	ghcr.io/open-webui/open-webui	github	open-webui/open-webui	v"
    "pihole	hosting/pihole/docker-compose.exist.yml	pihole/pihole	github	pi-hole/pi-hole	v"
    "portainer	hosting/portainer/docker-compose.exist.yml	portainer/portainer-ce	hub_clean	portainer/portainer-ce	bare"
    "uptime-kuma	hosting/uptime-kuma/docker-compose.exist.yml	louislam/uptime-kuma	github	louislam/uptime-kuma	bare"
    "vikunja	services/vikunja/docker-compose.exist.yml	vikunja/vikunja	github	go-vikunja/vikunja	bare"
    "whisperx	ai/whisperx/docker-compose.exist.yml	ghcr.io/pavelzbornik/whisperx-fastapi	github	pavelzbornik/whisperX-FastAPI	bare"
)

# ── Output helpers ────────────────────────────────────────────────────────────

W_NAME=16; W_CURR=30; W_LATEST=30
SEP="$(printf '%*s' $(( W_NAME + W_CURR + W_LATEST + 18 )) '' | tr ' ' '-')"

print_header() {
    printf "\n%-${W_NAME}s  %-${W_CURR}s  %-${W_LATEST}s  %s\n" "SERVICE" "CURRENT TAG" "LATEST TAG" "STATUS"
    echo "$SEP"
}

UPDATES_AVAILABLE=0
FAILURES=0

print_row() {
    local name="$1" current="$2" latest="$3" status="$4"
    printf "%-${W_NAME}s  %-${W_CURR}s  %-${W_LATEST}s  %s\n" "$name" "$current" "$latest" "$status"
}

# ── Version check loop ────────────────────────────────────────────────────────

print_header

for entry in "${CHECKS[@]}"; do
    IFS=$'\t' read -r name file image_prefix check_type check_arg tag_format <<< "$entry"

    # Current tag: parse image line, skip commented-out lines
    current_line=$(grep -v "^[[:space:]]*#" "$REPO/$file" 2>/dev/null \
        | grep -m1 "image:.*${image_prefix}" || true)
    if [[ -z "$current_line" ]]; then
        print_row "$name" "(not found in file)" "" "SKIP"
        continue
    fi
    raw_image=$(echo "$current_line" | sed 's/.*image:[[:space:]]*//' | tr -d "'\" ")
    if [[ "$raw_image" == *:* ]]; then
        current_tag="${raw_image##*:}"
    else
        current_tag="(none)"
    fi

    if [[ "$check_type" == "skip" ]]; then
        print_row "$name" "$current_tag" "(manual)" "—"
        continue
    fi

    # Fetch latest version
    latest_version=""
    case "$check_type" in
        github)      latest_version=$(latest_github "$check_arg" || true) ;;
        hub)         latest_version=$(latest_hub "$check_arg" || true) ;;
        hub_clean)   latest_version=$(latest_hub_clean "$check_arg" || true) ;;
        hub_release) latest_version=$(latest_hub_release "$check_arg" || true) ;;
    esac

    if [[ -z "$latest_version" ]]; then
        print_row "$name" "$current_tag" "(fetch failed)" "?"
        (( FAILURES++ )) || true
        continue
    fi

    # Build the latest tag. Fetch helpers return a bare (v-stripped) version, so
    # tag_format only adds a flavor suffix here; v/bare add nothing.
    case "$tag_format" in
        v|bare) latest_core="${latest_version}" ;;
        *)      latest_core="${latest_version}${tag_format}" ;;  # e.g. "-cpu"
    esac
    # Take the v-prefix from the file's existing tag so we never churn an image
    # cosmetically between "2.0.0" and "v2.0.0" (chatterbox, it-tools). Only a
    # fresh, untagged image falls back to tag_format's v intent.
    if [[ "$current_tag" == v[0-9]* ]] \
        || { [[ "$current_tag" == "(none)" ]] && [[ "$tag_format" == "v" ]]; }; then
        latest_tag="v${latest_core}"
    else
        latest_tag="${latest_core}"
    fi

    # Compare and optionally patch
    if [[ "$current_tag" == "$latest_tag" ]]; then
        # "Up to date" — but the pinned tag must actually be pullable. A tag can
        # exist upstream (GitHub) yet 404 on the pull registry (minio, whisper),
        # which silently reads as up to date and then breaks `docker compose up`.
        if [[ "$current_tag" != "(none)" ]]; then
            # `|| exists=$?` keeps a non-zero return (1 missing / 2 unverifiable)
            # from tripping `set -e` and aborting the whole run.
            exists=0; image_exists "$image_prefix" "$current_tag" || exists=$?
            if [[ "$exists" -eq 1 ]]; then
                print_row "$name" "$current_tag" "$latest_tag" "✗ PIN NOT PULLABLE"
                (( FAILURES++ )) || true
                continue
            fi
        fi
        status="up to date"
    else
        # Never offer (or apply) an update to a tag that isn't on the pull registry.
        exists=0; image_exists "$image_prefix" "$latest_tag" || exists=$?
        if [[ "$exists" -eq 1 ]]; then
            print_row "$name" "$current_tag" "$latest_tag" "✗ LATEST NOT PULLABLE"
            (( FAILURES++ )) || true
            continue
        fi

        status="→ UPDATE"
        (( UPDATES_AVAILABLE++ )) || true

        if [[ "$UPDATE" == "true" ]]; then
            if [[ "$current_tag" == "(none)" ]]; then
                # Image had no tag — insert one
                sed -i "s|image: ${image_prefix}$|image: ${image_prefix}:${latest_tag}|" "$REPO/$file"
            else
                sed -i "s|image: ${image_prefix}:${current_tag}|image: ${image_prefix}:${latest_tag}|g" \
                    "$REPO/$file"
            fi
            status="→ UPDATED"
        fi
    fi

    print_row "$name" "$current_tag" "$latest_tag" "$status"
done

echo "$SEP"
echo ""

if [[ "$UPDATES_AVAILABLE" -gt 0 && "$UPDATE" == "false" ]]; then
    echo "  ${UPDATES_AVAILABLE} update(s) available. Run with --update to apply."
elif [[ "$UPDATE" == "true" ]]; then
    echo "  Applied updates. Re-run \`./existential.sh compose\` to regenerate docker-compose.yml."
else
    echo "  All images up to date."
fi
[[ "$FAILURES" -gt 0 ]] && echo "  ${FAILURES} check(s) failed (network issue or image not found)."
echo ""
