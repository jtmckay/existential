#!/usr/bin/env bash
# Compares pinned container image tags against latest available versions.
#
# Covers two kinds of pin:
#   * compose `image:` lines in *.exist.yml — tag only
#   * Dockerfile `FROM` lines — tag + sha256 digest, updated together
# An image with no semver tags (distroless) uses check type `digest`, which
# reports whether the pinned digest still matches the tag it claims.
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
        | grep -vE '(rc|alpha|beta|dev|edge|nightly|sha-|-arm|-amd64|-linux|-windows|unstable|boringcrypto)' \
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

# _registry_auth <prefix>
# Echoes "<registry>\t<repo>\t<token>" for the pull registry behind an image
# prefix. Split out of image_exists so resolve_digest can reuse the same token
# dance across Docker Hub, ghcr and gcr.
_registry_auth() {
    local prefix="$1" registry repo token
    if [[ "$prefix" == ghcr.io/* ]]; then
        registry="ghcr.io"
        repo="${prefix#ghcr.io/}"
        token=$(curl -fsSL --max-time 15 \
            "https://ghcr.io/token?scope=repository:${repo}:pull" 2>/dev/null \
            | jq -r '.token // empty')
    elif [[ "$prefix" == gcr.io/* ]]; then
        registry="gcr.io"
        repo="${prefix#gcr.io/}"
        token=$(curl -fsSL --max-time 15 \
            "https://gcr.io/v2/token?scope=repository:${repo}:pull&service=gcr.io" 2>/dev/null \
            | jq -r '.token // empty')
    else
        registry="registry-1.docker.io"
        repo="$prefix"
        [[ "$repo" == */* ]] || repo="library/${repo}"   # official images live under library/
        token=$(curl -fsSL --max-time 15 \
            "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${repo}:pull" \
            2>/dev/null | jq -r '.token // empty')
    fi
    [[ -n "$token" ]] || return 1
    printf '%s\t%s\t%s' "$registry" "$repo" "$token"
}

# resolve_digest <prefix> <tag>
# The manifest digest a tag currently points at, as "sha256:...". Empty on any
# failure — callers must treat that as "unknown", never as "changed", or a
# transient network blip would rewrite a pin.
resolve_digest() {
    local prefix="$1" tag="$2" registry repo token auth
    auth=$(_registry_auth "$prefix") || return 1
    IFS=$'\t' read -r registry repo token <<< "$auth"
    curl -sSI --max-time 15 \
        -H "Authorization: Bearer ${token}" \
        -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
        -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" \
        -H "Accept: application/vnd.oci.image.index.v1+json" \
        -H "Accept: application/vnd.oci.image.manifest.v1+json" \
        "https://${registry}/v2/${repo}/manifests/${tag}" 2>/dev/null \
        | grep -i '^docker-content-digest:' \
        | tr -d '\r' | awk '{print $2}'
}

# image_exists <image_prefix> <tag>
# Checks whether <image_prefix>:<tag> is actually pullable from the registry the
# image comes from (GHCR for ghcr.io/* prefixes, else Docker Hub). This catches a
# tag that exists upstream on GitHub but was never published to the pull registry
# — minio's RELEASE.* tags read as "up to date" yet 404 on `docker pull`.
# Exit: 0 = exists (manifest 200), 1 = confirmed missing (404),
#       2 = unverifiable (auth/network failure — caller should not hard-fail).
image_exists() {
    local prefix="$1" tag="$2" registry repo token url auth
    # No token means we could not ask, not that the tag is gone — 2, never 1.
    auth=$(_registry_auth "$prefix") || return 2
    IFS=$'\t' read -r registry repo token <<< "$auth"

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
# check_type : github | hub | hub_clean | hub_release | digest | skip
#   digest    → the tag is a moving target (e.g. :latest); don't look for a newer
#               version, just re-resolve what the pinned tag points at now.
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
#
# Choosing github vs hub*: check wherever the *image tag* comes from, which is
# not always where the software is versioned. Projects that cut GitHub releases
# for the source but tag their images on a different scheme (pihole, minio) must
# use a hub* type — checking GitHub there yields a version that is real upstream
# but not pullable, which image_exists then reports as LATEST NOT PULLABLE.

declare -a CHECKS=(
    "actual-budget	services/actual-budget/docker-compose.exist.yml	actualbudget/actual-server	github	actualbudget/actual	bare"
    "appsmith	services/appsmith/docker-compose.exist.yml	appsmith/appsmith-ce	hub	appsmith/appsmith-ce	v"
    "caddy	hosting/caddy/docker-compose.exist.yml	caddy	hub_clean	library/caddy	bare"
    "chatterbox	ai/chatterbox/docker-compose.exist.yml	ghcr.io/devnen/chatterbox-tts-server	github	devnen/chatterbox-tts-server	v"
    "comfyui	ai/comfyui/docker-compose.exist.yml	ghcr.io/ai-dock/comfyui	skip		"
    "collabora	nas/collabora/docker-compose.exist.yml	collabora/code	hub_clean	collabora/code	bare"
    "dashy	services/dashy/docker-compose.exist.yml	lissy93/dashy	github	Lissy93/Dashy	bare"
    "grafana	hosting/grafana/docker-compose.exist.yml	grafana/grafana	hub_clean	grafana/grafana	bare"
    "decree-wh-go	services/decree/webhook/Dockerfile	golang	hub_clean	library/golang	-alpine3.23"
    "decree-wh-base	services/decree/webhook/Dockerfile	gcr.io/distroless/static-debian13	digest		"
    "hermes-agent	ai/hermes/docker-compose.exist.yml	nousresearch/hermes-agent	hub	nousresearch/hermes-agent	v"
    "home-assistant	services/homeassistant/docker-compose.exist.yml	ghcr.io/home-assistant/home-assistant	github	home-assistant/core	bare"
    "it-tools	services/it-tools/docker-compose.exist.yml	corentinth/it-tools	github	CorentinTh/it-tools	bare"
    "lowcoder	services/lowcoder/docker-compose.exist.yml	lowcoderorg/lowcoder-ce-api-service	hub_clean	lowcoderorg/lowcoder-ce-api-service	bare"
    "loki	hosting/loki/docker-compose.exist.yml	grafana/loki	hub_clean	grafana/loki	bare"
    # hub, not hub_clean: every alloy tag is v-prefixed, which hub_clean rejects.
    "loki-alloy	hosting/loki/docker-compose.exist.yml	grafana/alloy	hub	grafana/alloy	v"
    "mealie	services/mealie/docker-compose.exist.yml	ghcr.io/mealie-recipes/mealie	github	mealie-recipes/mealie	v"
    "minio	nas/minio/docker-compose.exist.yml	minio/minio	hub_release	minio/minio	bare"
    "nextcloud	nas/nextcloud/docker-compose.exist.yml	nextcloud	hub_clean	library/nextcloud	bare"
    "nocodb	services/nocodb/docker-compose.exist.yml	nocodb/nocodb	github	nocodb/nocodb	bare"
    "ntfy	services/ntfy/docker-compose.exist.yml	binwiederhier/ntfy	github	binwiederhier/ntfy	v"
    "ollama	ai/ollama/docker-compose.exist.yml	ollama/ollama	hub_clean	ollama/ollama	bare"
    "open-webui	ai/open-webui/docker-compose.exist.yml	ghcr.io/open-webui/open-webui	github	open-webui/open-webui	v"
    "openviking	ai/openviking/docker-compose.exist.yml	ghcr.io/volcengine/openviking	github	volcengine/OpenViking	v"
    # hub_clean, NOT github: pi-hole's GitHub releases version the core software
    # (v6.x) while the images are tagged by date (2026.07.2). Checking GitHub
    # returned 6.4.3, which does not exist on Docker Hub.
    "pihole	hosting/pihole/docker-compose.exist.yml	pihole/pihole	hub_clean	pihole/pihole	bare"
    "portainer	hosting/portainer/docker-compose.exist.yml	portainer/portainer-ce	hub_clean	portainer/portainer-ce	bare"
    # github, not hub*: every prom/prometheus tag is v-prefixed (so hub_clean
    # matches nothing) and hub sorts the -busybox/-distroless flavours above the
    # plain tag. The GitHub release tag is the plain version.
    "prometheus	hosting/prometheus/docker-compose.exist.yml	prom/prometheus	github	prometheus/prometheus	v"
    "uptime-kuma	hosting/uptime-kuma/docker-compose.exist.yml	louislam/uptime-kuma	github	louislam/uptime-kuma	bare"
    "whisperx	ai/whisperx/docker-compose.exist.yml	ghcr.io/pavelzbornik/whisperx-fastapi	github	pavelzbornik/whisperX-FastAPI	bare"
    "wyoming-piper	ai/wyoming-piper/docker-compose.exist.yml	rhasspy/wyoming-piper	github	OHF-Voice/wyoming-piper	bare"
    "wyoming-whisper	ai/wyoming-whisper/docker-compose.exist.yml	rhasspy/wyoming-whisper	github	OHF-Voice/wyoming-faster-whisper	bare"
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

    # Current tag. Compose files carry `image: <prefix>:<tag>`; Dockerfiles
    # carry `FROM <prefix>:<tag>@sha256:<digest> [AS stage]`, where the digest
    # is what actually resolves and the tag is documentation. Both are parsed
    # here so a base image is tracked exactly like any other pinned image.
    is_dockerfile=false
    [[ "$(basename "$file")" == Dockerfile* ]] && is_dockerfile=true
    current_digest=""

    if [[ "$is_dockerfile" == "true" ]]; then
        current_line=$(grep -v "^[[:space:]]*#" "$REPO/$file" 2>/dev/null \
            | grep -m1 "^FROM ${image_prefix}[:@]" || true)
        if [[ -z "$current_line" ]]; then
            print_row "$name" "(not found in file)" "" "SKIP"
            continue
        fi
        ref="${current_line#FROM }"; ref="${ref%% *}"      # drop " AS builder"
        [[ "$ref" == *@* ]] && current_digest="${ref#*@}"
        ref_notag="${ref%@*}"
        if [[ "$ref_notag" == *:* ]]; then
            current_tag="${ref_notag##*:}"
        else
            current_tag="(none)"
        fi
    else
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
    fi

    # Images with no semver tags (distroless: the Debian release is part of the
    # repo name) are tracked for digest drift instead — "has the tag I pinned
    # been re-pushed?" rather than "is there a newer version?".
    if [[ "$check_type" == "digest" ]]; then
        latest_digest=$(resolve_digest "$image_prefix" "$current_tag" || true)
        if [[ -z "$latest_digest" ]]; then
            print_row "$name" "${current_digest:0:19}" "(fetch failed)" "?"
            (( FAILURES++ )) || true
        elif [[ "$latest_digest" == "$current_digest" ]]; then
            print_row "$name" "${current_digest:0:19}" "${latest_digest:0:19}" "up to date"
        else
            (( UPDATES_AVAILABLE++ )) || true
            status="→ DIGEST DRIFT"
            if [[ "$UPDATE" == "true" ]]; then
                # Match whatever the FROM line actually carries — tag+digest,
                # tag only, or digest only — then VERIFY. An unverified sed
                # reports success on a pin shape it never matched, and every
                # later run then reports DIGEST DRIFT forever.
                sed -i -E "s|^FROM ${image_prefix}(:[^[:space:]@]+)?(@sha256:[0-9a-f]+)?|FROM ${image_prefix}:${current_tag}@${latest_digest}|" \
                    "$REPO/$file"
                if grep -qF "@${latest_digest}" "$REPO/$file"; then
                    status="→ UPDATED"
                else
                    status="→ UPDATE FAILED"
                    (( FAILURES++ )) || true
                fi
            fi
            print_row "$name" "${current_digest:0:19}" "${latest_digest:0:19}" "$status"
        fi
        continue
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
            if [[ "$is_dockerfile" == "true" ]]; then
                # Tag and digest must move together, or the digest would keep
                # pinning the old image and the tag would be a lie. A digest we
                # cannot resolve means we leave the pin alone.
                new_digest=$(resolve_digest "$image_prefix" "$latest_tag" || true)
                if [[ -z "$new_digest" ]]; then
                    status="→ UPDATE (digest fetch failed, not applied)"
                else
                    # `[^[:space:]]*` after a literal `:` cannot match a
                    # digest-only `FROM prefix@sha256:…` line, which the
                    # grep above happily selects. Match both shapes, then
                    # verify rather than assuming the rewrite landed.
                    sed -i -E "s|^FROM ${image_prefix}(:[^[:space:]@]+)?(@sha256:[0-9a-f]+)?|FROM ${image_prefix}:${latest_tag}@${new_digest}|" \
                        "$REPO/$file"
                    if grep -qF "@${new_digest}" "$REPO/$file"; then
                        status="→ UPDATED"
                    else
                        status="→ UPDATE FAILED"
                        (( FAILURES++ )) || true
                    fi
                fi
            else
                # Patch the ref exactly as the file spells it, not a
                # `image: <prefix>:<tag>` string rebuilt from the lookup table.
                # The two are not the same: a line may quote the value
                # (`image: "lissy93/dashy:4.2.0"`) or carry a registry prefix
                # the table omits (`index.docker.io/appsmith/appsmith-ce`), and
                # a rebuilt pattern silently matches neither. $raw_image is the
                # value already parsed off that line (quotes stripped), so
                # swapping its tag hits every shape.
                if [[ "$current_tag" == "(none)" ]]; then
                    new_image="${raw_image}:${latest_tag}"
                else
                    new_image="${raw_image%:*}:${latest_tag}"
                fi
                sed -i "s|${raw_image}\([\"']*\)$|${new_image}\1|" "$REPO/$file"
                if grep -qF "${new_image}" "$REPO/$file"; then
                    status="→ UPDATED"
                else
                    status="→ UPDATE FAILED"
                    (( FAILURES++ )) || true
                fi
            fi
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
