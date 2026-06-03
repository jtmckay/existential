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
# Newest tag from Docker Hub that looks like semver (digits + dots + optional
# single-word suffix).  Returns tags like "3.2.1" or "7-alpine" — call
# latest_hub_clean when you only want bare digits-and-dots.
latest_hub() {
    local path="$1"
    curl -fsSL --max-time 15 \
        "https://registry.hub.docker.com/v2/repositories/${path}/tags?page_size=100&ordering=last_updated" \
        2>/dev/null \
        | jq -r '.results[].name' 2>/dev/null \
        | grep -E '^v?[0-9]+\.[0-9]+' \
        | grep -vE '(rc|alpha|beta|dev|edge|nightly|sha-|-arm|-amd64|-linux|-windows|unstable)' \
        | head -1
}

# latest_hub_clean <org/image>
# Like latest_hub but only returns pure digit-and-dot tags (no flavor suffixes
# like -alpine, -fpm, -builder, -rocm).  Use this for images where the plain
# version tag is the right choice (caddy, nextcloud, portainer, ollama …).
latest_hub_clean() {
    local path="$1"
    curl -fsSL --max-time 15 \
        "https://registry.hub.docker.com/v2/repositories/${path}/tags?page_size=100&ordering=last_updated" \
        2>/dev/null \
        | jq -r '.results[].name' 2>/dev/null \
        | grep -E '^[0-9]+(\.[0-9]+)+$' \
        | head -1
}

# ── Lookup table ──────────────────────────────────────────────────────────────
# Columns (tab-separated):
#   display_name  file  image_prefix  check_type  check_arg  tag_format
#
# check_type : github | hub | hub_clean | skip
# check_arg  : github → owner/repo   hub* → org/image (library/X for official)
# tag_format : how to turn the fetched version string into a Docker image tag
#   bare      → use as-is (v already stripped by fetch helpers)
#   v         → prepend v  (e.g. v2.1.0)
#   <suffix>  → append suffix (e.g. "-cpu" for whisper)
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
    "minio	nas/minio/docker-compose.exist.yml	minio/minio	github	minio/minio	bare"
    "nextcloud	nas/nextcloud/docker-compose.exist.yml	nextcloud	hub_clean	library/nextcloud	bare"
    "nocodb	services/nocodb/docker-compose.exist.yml	nocodb/nocodb	github	nocodb/nocodb	bare"
    "ntfy	services/ntfy/docker-compose.exist.yml	binwiederhier/ntfy	github	binwiederhier/ntfy	v"
    "ollama	ai/ollama/docker-compose.exist.yml	ollama/ollama	hub_clean	ollama/ollama	bare"
    "open-webui	ai/open-webui/docker-compose.exist.yml	ghcr.io/open-webui/open-webui	github	open-webui/open-webui	v"
    "pihole	hosting/pihole/docker-compose.exist.yml	pihole/pihole	github	pi-hole/pi-hole	v"
    "portainer	hosting/portainer/docker-compose.exist.yml	portainer/portainer-ce	hub_clean	portainer/portainer-ce	bare"
    "uptime-kuma	hosting/uptime-kuma/docker-compose.exist.yml	louislam/uptime-kuma	github	louislam/uptime-kuma	bare"
    "vikunja	services/vikunja/docker-compose.exist.yml	vikunja/vikunja	github	go-vikunja/vikunja	bare"
    "whisper	ai/whisper/docker-compose.exist.yml	fedirz/faster-whisper-server	github	fedirz/faster-whisper-server	-cpu"
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
        github)    latest_version=$(latest_github "$check_arg" || true) ;;
        hub)       latest_version=$(latest_hub "$check_arg" || true) ;;
        hub_clean) latest_version=$(latest_hub_clean "$check_arg" || true) ;;
    esac

    if [[ -z "$latest_version" ]]; then
        print_row "$name" "$current_tag" "(fetch failed)" "?"
        (( FAILURES++ )) || true
        continue
    fi

    # Apply tag format
    case "$tag_format" in
        v)    latest_tag="v${latest_version}" ;;
        bare) latest_tag="${latest_version}" ;;
        *)    latest_tag="${latest_version}${tag_format}" ;;  # e.g. "-cpu"
    esac

    # Compare and optionally patch
    if [[ "$current_tag" == "$latest_tag" ]]; then
        status="up to date"
    else
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
