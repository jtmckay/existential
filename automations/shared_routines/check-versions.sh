#!/usr/bin/env bash
# check-versions — compare pinned image tags against upstream and notify when
# updates are available. Reads current tags from the master docker-compose.yml
# (mounted at /work/.decree/docker-compose.yml) so there is no extra state to
# maintain — it's always current after any ./existential.sh run.
#
# Runs weekly via cron. Silent when all tags match; sends one ntfy notification
# listing every service with an available update.
#
# Manual invocation:
#   docker exec decree decree run check-versions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-/work/.decree/docker-compose.yml}"

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    source "${SCRIPT_DIR}/../lib/precheck.sh"
    command -v curl >/dev/null || precheck_fail "check-versions" "curl not found"
    command -v jq   >/dev/null || precheck_fail "check-versions" "jq not found"
    [ -f "$COMPOSE_FILE" ] || precheck_fail "check-versions" \
        "docker-compose.yml not mounted at ${COMPOSE_FILE} — add '../../docker-compose.yml:/work/.decree/docker-compose.yml:ro' to decree volumes"
    precheck_pass "check-versions"
    exit 0
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo "docker-compose.yml not found at ${COMPOSE_FILE}" >&2
    echo "Add '../../docker-compose.yml:/work/.decree/docker-compose.yml:ro' to decree volumes" >&2
    exit 1
fi

# ── Registry fetch helpers (mirrors src/lib/check-versions.sh) ────────────────

latest_github() {
    curl -fsSL --max-time 15 \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${1}/releases?per_page=20" 2>/dev/null \
        | jq -r '[.[] | select(.prerelease==false and .draft==false)
                       | select(.tag_name | test("rc|alpha|beta|pre\\.?[0-9]";"i") | not)
                       | .tag_name][0] // ""' \
        | sed 's/^v//'
}

latest_hub() {
    curl -fsSL --max-time 15 \
        "https://registry.hub.docker.com/v2/repositories/${1}/tags?page_size=100&ordering=last_updated" \
        2>/dev/null | jq -r '.results[].name' 2>/dev/null \
        | grep -E '^v?[0-9]+\.[0-9]+' \
        | grep -vE '(rc|alpha|beta|dev|edge|nightly|sha-|-arm|-amd64|-linux|-windows|unstable)' \
        | head -1
}

latest_hub_clean() {
    curl -fsSL --max-time 15 \
        "https://registry.hub.docker.com/v2/repositories/${1}/tags?page_size=100&ordering=last_updated" \
        2>/dev/null | jq -r '.results[].name' 2>/dev/null \
        | grep -E '^[0-9]+(\.[0-9]+)+$' | head -1
}

# ── CHECKS table (keep in sync with src/lib/check-versions.sh) ───────────────
# Fields (tab-separated): display_name  image_prefix  check_type  check_arg  tag_format

declare -a CHECKS=(
    "actual-budget	actualbudget/actual-server	github	actualbudget/actual	bare"
    "appsmith	appsmith/appsmith-ce	hub	appsmith/appsmith-ce	v"
    "authelia	authelia/authelia	github	authelia/authelia	v"
    "caddy	caddy	hub_clean	library/caddy	bare"
    "chatterbox	ghcr.io/devnen/chatterbox-tts-server	github	devnen/chatterbox-tts-server	v"
    "collabora	collabora/code	hub_clean	collabora/code	bare"
    "dashy	lissy93/dashy	github	Lissy93/Dashy	bare"
    "hermes-agent	nousresearch/hermes-agent	hub	nousresearch/hermes-agent	v"
    "home-assistant	ghcr.io/home-assistant/home-assistant	github	home-assistant/core	bare"
    "it-tools	corentinth/it-tools	github	CorentinTh/it-tools	bare"
    "lightrag	ghcr.io/hkuds/lightrag	github	HKUDS/LightRAG	v"
    "lowcoder	lowcoderorg/lowcoder-ce-api-service	hub_clean	lowcoderorg/lowcoder-ce-api-service	bare"
    "mealie	ghcr.io/mealie-recipes/mealie	github	mealie-recipes/mealie	v"
    "minio	minio/minio	github	minio/minio	bare"
    "nextcloud	nextcloud	hub_clean	library/nextcloud	bare"
    "nocodb	nocodb/nocodb	github	nocodb/nocodb	bare"
    "ntfy	binwiederhier/ntfy	github	binwiederhier/ntfy	v"
    "ollama	ollama/ollama	hub_clean	ollama/ollama	bare"
    "open-webui	ghcr.io/open-webui/open-webui	github	open-webui/open-webui	v"
    "pihole	pihole/pihole	github	pi-hole/pi-hole	v"
    "portainer	portainer/portainer-ce	hub_clean	portainer/portainer-ce	bare"
    "uptime-kuma	louislam/uptime-kuma	github	louislam/uptime-kuma	bare"
    "vikunja	vikunja/vikunja	github	go-vikunja/vikunja	bare"
    "whisperx	ghcr.io/pavelzbornik/whisperx-fastapi	github	pavelzbornik/whisperX-FastAPI	bare"
)

# ── Compare ───────────────────────────────────────────────────────────────────

updates=()
failures=()

for entry in "${CHECKS[@]}"; do
    IFS=$'\t' read -r name image_prefix check_type check_arg tag_format <<< "$entry"

    current_line=$(grep -v "^[[:space:]]*#" "$COMPOSE_FILE" \
        | grep -m1 "image:.*${image_prefix}" || true)
    [[ -z "$current_line" ]] && continue  # service not in this compose

    raw_image=$(echo "$current_line" | sed 's/.*image:[[:space:]]*//' | tr -d "'\" ")
    current_tag="${raw_image##*:}"
    [[ "$raw_image" != *:* ]] && current_tag="(none)"

    latest_version=""
    case "$check_type" in
        github)    latest_version=$(latest_github "$check_arg" 2>/dev/null || true) ;;
        hub)       latest_version=$(latest_hub    "$check_arg" 2>/dev/null || true) ;;
        hub_clean) latest_version=$(latest_hub_clean "$check_arg" 2>/dev/null || true) ;;
    esac

    if [[ -z "$latest_version" ]]; then
        failures+=("$name")
        continue
    fi

    case "$tag_format" in
        v)    latest_tag="v${latest_version}" ;;
        bare) latest_tag="${latest_version}" ;;
        *)    latest_tag="${latest_version}${tag_format}" ;;
    esac

    echo "${name}: ${current_tag} (latest: ${latest_tag})"
    [[ "$current_tag" != "$latest_tag" ]] && updates+=("${name}: ${current_tag} → ${latest_tag}")
done

# ── Report ────────────────────────────────────────────────────────────────────

if [[ ${#failures[@]} -gt 0 ]]; then
    echo "Fetch failed for: ${failures[*]}" >&2
fi

if [[ ${#updates[@]} -eq 0 ]]; then
    echo "All pinned tags are current."
    exit 0
fi

body="$(printf '%d image update(s) available:\n' "${#updates[@]}")"
for u in "${updates[@]}"; do body+="  • ${u}"$'\n'; done
body+=$'\nApply: ./existential.sh run check-versions --update'
body+=$'\nThen:  docker compose pull && docker compose up -d'

echo ""
echo "$body"

# Queue a notify message via decree outbox
_outbox="${OUTBOX_DIR:-/work/.decree/outbox}"
cat > "${_outbox}/check-versions-$(date +%s%N).md" << EOF
---
routine: notify
ntfy_title: Image Updates Available
ntfy_priority: default
ntfy_tags: arrow_up
---
${body}
EOF
