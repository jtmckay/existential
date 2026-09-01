#!/usr/bin/env bash
# test-compose.sh — unit tests for src/generate-compose.ts.
#
# Black-box: builds throwaway fixture repos under a temp dir, runs the real
# generate-compose.ts via tsx against them, and asserts the merged
# docker-compose.yml / master .env. Covers service discovery, relative-path
# adjustment, materialisation of every declared volume into a host bind mount,
# placement from the service's `x-exist-volumes` block (`nfs: true` binding to
# the host mount when one is set, everything else staying local), the hard error
# when a mounted volume is undeclared, the hard error when an NFS server is set
# without a host mount, the network mode, the empty case, and archiving.
#
# Needs tsx + js-yaml — only present inside existential-adhoc. Skips cleanly
# elsewhere. Read-only re: the real repo. Invoked by ./existential.sh test.

set -euo pipefail

GC="/src/generate-compose.ts"

if ! command -v tsx >/dev/null 2>&1 || [[ ! -f "$GC" ]]; then
    echo "skipped — tsx/generate-compose not available (run inside existential-adhoc)"
    exit 0
fi

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }

assert_contains()     { if grep -qF -- "$2" <<<"$3"; then _ok "$1"; else _fail "$1" "missing: $2"; fi; }
assert_not_contains() { if grep -qF -- "$2" <<<"$3"; then _fail "$1" "unexpected: $2"; else _ok "$1"; fi; }
assert_file()         { if [[ -f "$2" ]]; then _ok "$1"; else _fail "$1" "no such file: $2"; fi; }
assert_no_file()      { if [[ -f "$2" ]]; then _fail "$1" "unexpected file: $2"; else _ok "$1"; fi; }

# Fresh fixture repo with one service (services/foo) exercising every volume
# shape: relative bind, named volume, absolute path, and an NFS volume.
new_repo() {
    local d; d="$(mktemp -d "$TMP/repo.XXXXXX")"
    mkdir -p "$d/services/foo"
    cat > "$d/services/foo/docker-compose.yml" <<'YAML'
services:
  foo:
    image: foo:1
    volumes:
      - ./data:/data
      - named_vol:/cache
      - /abs/host:/abs
      - foo_nfs:/srv
x-exist-volumes:
  named_vol: {}
  foo_nfs: { nfs: true }
YAML
    echo "$d"
}

# ── Enabled service: merge + path adjustment + bind materialisation ───────────

repo="$(new_repo)"
printf 'EXIST_IS_SERVICES_FOO=true\n' > "$repo/.env.shared"
err="$(tsx "$GC" "$repo" docker-compose.yml "/host/realrepo" 2>&1 >/dev/null)" || true
assert_contains "reports the enabled service" "Enabled (1): services/foo" "$err"
assert_file "writes docker-compose.yml" "$repo/docker-compose.yml"
assert_file "writes master .env" "$repo/.env"

compose="$(cat "$repo/docker-compose.yml" 2>/dev/null || true)"
assert_contains "merged service present" "foo:" "$compose"
assert_contains "relative bind rewritten under service dir" "./services/foo/data:/data" "$compose"
assert_contains "absolute path left unchanged" "/abs/host:/abs" "$compose"
# Named & NFS volumes both materialise as local host bind mounts (no host mount set).
assert_contains "named volume materialised as local bind" "/host/realrepo/volumes/named_vol:/cache" "$compose"
assert_contains "nfs volume materialised as local bind (no host mount)" "/host/realrepo/volumes/foo_nfs:/srv" "$compose"
assert_not_contains "no x-exist-volumes block survives" "x-exist-volumes" "$compose"
assert_not_contains "no volume spec keys survive" "nfs: true" "$compose"
# Top-level volumes section is dropped entirely (no Docker-managed volumes).
assert_not_contains "top-level named_vol declaration removed" "named_vol: {}" "$compose"
assert_contains "default network is a bridge" "driver: bridge" "$compose"
# The local bind directory is created (as the host user) so Docker doesn't make it as root.
assert_dir() { if [[ -d "$2" ]]; then _ok "$1"; else _fail "$1" "no such dir: $2"; fi; }
assert_dir "local bind dir created for named volume" "$repo/volumes/named_vol"
assert_dir "local bind dir created for nfs volume" "$repo/volumes/foo_nfs"

envout="$(cat "$repo/.env" 2>/dev/null || true)"
assert_contains "master .env carries the do-not-edit header" "DO NOT EDIT" "$envout"

# ── NFS volume binds to the host mount when one is configured ──────────────────

repo="$(new_repo)"
printf 'EXIST_IS_SERVICES_FOO=true\nEXIST_NFS_SERVER_ADDRESS=1.2.3.4\nEXIST_NFS_HOST_MOUNT=/mnt/nas\n' > "$repo/.env.shared"
tsx "$GC" "$repo" docker-compose.yml "/host/realrepo" >/dev/null 2>&1 || true
compose="$(cat "$repo/docker-compose.yml" 2>/dev/null || true)"
assert_contains "nfs volume binds to host mount" "/mnt/nas/foo_nfs:/srv" "$compose"
assert_contains "non-nfs volume still binds locally" "/host/realrepo/volumes/named_vol:/cache" "$compose"
assert_not_contains "no Docker-managed volumes remain" "type: nfs" "$compose"

# ── NFS server set without a host mount is a hard error ───────────────────────

repo="$(new_repo)"
printf 'EXIST_IS_SERVICES_FOO=true\nEXIST_NFS_SERVER_ADDRESS=1.2.3.4\n' > "$repo/.env.shared"
rc=0
err="$(tsx "$GC" "$repo" docker-compose.yml "/host/realrepo" 2>&1 >/dev/null)" || rc=$?
assert_contains "errors when NFS server set without host mount" "EXIST_NFS_HOST_MOUNT" "$err"
[[ "$rc" -ne 0 ]] && _ok "NFS-without-host-mount exits non-zero" || _fail "NFS-without-host-mount exits non-zero" "got rc=$rc"

# ── External network mode ─────────────────────────────────────────────────────

repo="$(new_repo)"
printf 'EXIST_IS_SERVICES_FOO=true\nEXIST_NETWORK_EXTERNAL=true\n' > "$repo/.env.shared"
tsx "$GC" "$repo" docker-compose.yml >/dev/null 2>&1 || true
compose="$(cat "$repo/docker-compose.yml" 2>/dev/null || true)"
assert_contains "EXIST_NETWORK_EXTERNAL=true marks network external" "external: true" "$compose"

# ── No services enabled ───────────────────────────────────────────────────────

repo="$(new_repo)"
printf 'EXIST_IS_SERVICES_FOO=false\n' > "$repo/.env.shared"
rc=0
err="$(tsx "$GC" "$repo" docker-compose.yml 2>&1 >/dev/null)" || rc=$?
assert_contains "empty selection reports nothing enabled" "No services enabled" "$err"
[[ "$rc" -eq 0 ]] && _ok "empty selection exits 0" || _fail "empty selection exits 0" "got rc=$rc"
assert_no_file "no compose written when nothing enabled" "$repo/docker-compose.yml"

# ── Existing compose is archived, not clobbered ───────────────────────────────

repo="$(new_repo)"
printf 'EXIST_IS_SERVICES_FOO=true\n' > "$repo/.env.shared"
tsx "$GC" "$repo" docker-compose.yml >/dev/null 2>&1 || true   # first write
tsx "$GC" "$repo" docker-compose.yml >/dev/null 2>&1 || true   # second → archive first
# Archives live under archive/, the same directory `./existential.sh reset`
# uses — not loose in the repo root, where they used to accumulate.
archived="$(find "$repo/archive" -name 'docker-compose-*.yml' -type f 2>/dev/null | head -1)"
if [[ -n "$archived" ]]; then _ok "previous compose archived on regeneration"
else _fail "previous compose archived on regeneration" "no archive/docker-compose-*.yml found"; fi

stray="$(find "$repo" -maxdepth 1 -name 'docker-compose-*.yml' -type f 2>/dev/null | head -1)"
if [[ -z "$stray" ]]; then _ok "archives do not land in the repo root"
else _fail "archives do not land in the repo root" "found ${stray##*/}"; fi

# ── Relative bind sources are created too ─────────────────────────────────────
#
# The one that actually bites. A missing bind source is created by the DAEMON,
# as root:root — which shadows whatever the image had at that mount point and
# leaves a directory the host user cannot delete on the next render. hermes'
# hermes_install/{.venv,ui-tui,gateway,node_modules} is exactly this shape.
# Creating it here, in adhoc under the host uid:gid, gets in first.
assert_dir "relative bind source created under the service dir" "$repo/services/foo/data"

# ── Undeclared volume is a hard error ────────────────────────────────────────
# A bare name with no x-exist-volumes entry used to fall through to a
# Docker-managed volume — opaque, re-inits from the image, wrong UID on NFS.
# It must abort generation with a message naming the fix.
repo="$(mktemp -d "$TMP/repo.XXXXXX")"
mkdir -p "$repo/services/undeclared"
cat > "$repo/services/undeclared/docker-compose.yml" <<'YAML'
services:
  undeclared:
    image: undeclared:1
    volumes:
      - mystery_data:/data
YAML
printf 'EXIST_IS_SERVICES_UNDECLARED=true\n' > "$repo/.env.shared"
set +e
err="$(tsx "$GC" "$repo" docker-compose.yml "/host/realrepo" 2>&1 >/dev/null)"
code=$?
set -e
if [[ $code -ne 0 ]]; then _ok "undeclared volume exits non-zero"; else _fail "undeclared volume exits non-zero" "exit was 0"; fi
assert_contains "undeclared volume names the volume" "mystery_data" "$err"
assert_contains "undeclared volume names the fix" "x-exist-volumes" "$err"
assert_no_file "no compose written for an undeclared volume" "$repo/docker-compose.yml"

repo="$(mktemp -d "$TMP/repo.XXXXXX")"
mkdir -p "$repo/services/bar"
cat > "$repo/services/bar/docker-compose.yml" <<'YAML'
services:
  bar:
    image: bar:1
    volumes:
      - ./dotdir/.venv:/opt/.venv
      - ./bar-config.yml:/etc/bar.yml
      - ../../workspace:/workspace
      - ../../../escapes:/escapes
      - $HOME/envrooted:/env
YAML
printf 'EXIST_IS_SERVICES_BAR=true\n' > "$repo/.env.shared"
tsx "$GC" "$repo" docker-compose.yml "/host/realrepo" >/dev/null 2>&1 || true

# A dot-leading name is a directory, not an extension — .venv must be created.
assert_dir "dot-leading bind source is treated as a directory" "$repo/services/bar/dotdir/.venv"

# A source with a real file extension is a FILE mount. Creating a directory
# there would hand the container an empty dir instead of the config.
assert_no_dir() { if [[ -d "$2" ]]; then _fail "$1" "unexpected dir: $2"; else _ok "$1"; fi; }
assert_no_dir "file-extension bind source is not created as a directory" "$repo/services/bar/bar-config.yml"

# ../../ back to the repo root is legitimate (hermes and code-server share
# workspace/ that way) and resolves inside the repo, so it is created.
assert_dir "repo-root bind source created for a ../.. path" "$repo/workspace"

# A path that escapes the repo is a template bug. Materialising it somewhere
# else on the host would hide that, so it is left alone.
assert_no_dir "escaping bind source is not created outside the repo" "$(dirname "$repo")/escapes"

# Env-rooted sources are Docker's to resolve; we cannot know the value.
assert_no_dir "env-rooted bind source is not created" "$repo/services/bar/\$HOME/envrooted"

# ── GPU vendor: reservation stripping + x-exist-gpu overlays ─────────────────
#
# The stakes: docker refuses to create a container whose device driver it cannot
# satisfy, so leaving a `driver: nvidia` reservation on a non-nvidia host takes
# `docker compose up` down for the whole stack — not just the GPU service.

new_gpu_repo() {
    local d; d="$(mktemp -d "$TMP/gpurepo.XXXXXX")"
    mkdir -p "$d/ai/gpu"
    cat > "$d/ai/gpu/docker-compose.yml" <<'YAML'
services:
  gpu:
    image: gpu:1
    environment:
      - KEEP_ME=yes
      - DEVICE=cuda
    x-exist-gpu:
      amd:
        image: gpu:1-rocm
        privileged: true
        environment:
          DEVICE: vulkan
      none:
        environment:
          DEVICE: cpu
    deploy:
      resources:
        limits:
          memory: 4G
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
YAML
    echo "$d"
}

gpu_render() {   # gpu_render <vendor-env-lines...> — echo the merged compose
    local repo; repo="$(new_gpu_repo)"
    { printf 'EXIST_IS_AI_GPU=true\n'; printf '%s\n' "$@"; } > "$repo/.env.shared"
    tsx "$GC" "$repo" docker-compose.yml "/host/realrepo" >/dev/null 2>&1 || true
    cat "$repo/docker-compose.yml"
}

# nvidia — the templates are already correct, so this must be a no-op beyond
# dropping the overlay key itself.
out="$(gpu_render 'EXIST_GPU_VENDOR=nvidia')"
assert_contains     "nvidia keeps the device reservation"   "driver: nvidia" "$out"
assert_contains     "nvidia keeps the memory limit"         "memory: 4G"     "$out"
assert_not_contains "nvidia drops the x-exist-gpu key"      "x-exist-gpu"    "$out"
assert_not_contains "nvidia does not apply the amd image"   "gpu:1-rocm"     "$out"
assert_not_contains "nvidia does not apply amd privileges"  "privileged"     "$out"

# amd — reservation gone, overlay applied.
out="$(gpu_render 'EXIST_GPU_VENDOR=amd')"
assert_not_contains "amd strips the device reservation"     "driver: nvidia" "$out"
assert_not_contains "amd drops the x-exist-gpu key"         "x-exist-gpu"    "$out"
assert_contains     "amd applies the overlay image"         "gpu:1-rocm"     "$out"
assert_contains     "amd applies the overlay privileges"    "privileged: true" "$out"
assert_contains     "amd applies the overlay env"           "DEVICE: vulkan" "$out"
# The overlay merges into environment rather than replacing it — a vendor block
# that sets one variable must not silently drop the service's other env.
assert_contains     "amd keeps unrelated env from the template" "KEEP_ME" "$out"
# Stripping the devices list must not take the rest of deploy with it.
assert_contains     "amd keeps the memory limit"            "memory: 4G"     "$out"

# none — same strip, its own overlay.
out="$(gpu_render 'EXIST_GPU_VENDOR=none')"
assert_not_contains "none strips the device reservation"    "driver: nvidia" "$out"
assert_contains     "none applies its own overlay env"      "DEVICE: cpu"    "$out"
assert_not_contains "none does not apply the amd image"     "gpu:1-rocm"     "$out"

# Backward compatibility: every .env.shared written before the vendor question
# existed has no EXIST_GPU_VENDOR at all. Those installs must keep generating
# exactly what they generated before — VRAM 0 meant no GPU, anything else nvidia.
out="$(gpu_render 'EXIST_VRAM_GB=0')"
assert_not_contains "legacy EXIST_VRAM_GB=0 still strips the reservation" "driver: nvidia" "$out"
assert_contains     "legacy EXIST_VRAM_GB=0 applies the none overlay"     "DEVICE: cpu"    "$out"

out="$(gpu_render 'EXIST_VRAM_GB=8')"
assert_contains     "legacy EXIST_VRAM_GB=8 keeps the reservation" "driver: nvidia" "$out"

# Both keys blank is NOT a legacy install — it is the shipped default, so it is
# what a fresh clone, CI, and the e2e harness all render. Assuming nvidia there
# put a reservation docker cannot satisfy on every non-nvidia host, and compose
# fails the whole `up`, not just the GPU service. Guess `none` instead: the cost
# is an unanswered nvidia host running on CPU, against a stack that will not
# start for everyone else.
out="$(gpu_render)"
assert_not_contains "no GPU keys at all strips the reservation" "driver: nvidia" "$out"
assert_contains     "no GPU keys at all applies the none overlay" "DEVICE: cpu"  "$out"

# A typo must not fail open. Defaulting to nvidia here would hand an AMD host a
# reservation its daemon cannot satisfy, and the resulting docker error points
# at capabilities, not at the misspelling.
repo="$(new_gpu_repo)"
printf 'EXIST_IS_AI_GPU=true\nEXIST_GPU_VENDOR=nvida\n' > "$repo/.env.shared"
err="$(tsx "$GC" "$repo" docker-compose.yml "/host/realrepo" 2>&1 >/dev/null)" && rc=0 || rc=$?
assert_contains "a misspelled vendor is reported" "not one of" "$err"
[[ "${rc:-0}" -ne 0 ]] \
    && _ok "a misspelled vendor exits non-zero" \
    || _fail "a misspelled vendor exits non-zero" "render continued with an unknown vendor"
assert_no_file "a misspelled vendor writes no compose file" "$repo/docker-compose.yml"

# Self-check canary: TEST_SELFCHECK=1 forces one failure so this suite's own
# FAIL→non-zero-exit path is itself testable (src/test/run-all.sh selfcheck).
[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [[ "${#FAIL_NAMES[@]}" -gt 0 ]]; then
    echo "Failed:"
    printf '  - %s\n' "${FAIL_NAMES[@]}"
fi

[[ "$FAIL" -eq 0 ]]
