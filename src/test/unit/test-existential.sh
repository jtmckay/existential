#!/usr/bin/env bash
# test-existential.sh — unit tests for existential.sh pure-bash functions and CLI.
#
# Strategy: combination approach.
#   - Pure helpers (_enable_var_for, _has_any_enabled, service_is_enabled,
#     _find_service_dir_for_slug) are tested by sourcing existential.sh with
#     Docker stubbed out so the runtime-detection block is harmless.
#   - CLI behaviour (--help, unknown actions, run dispatch)
#     is tested by invoking existential.sh as a subprocess.
#
# Rules (from .claude/reference/testing.md):
#   - Read-only.  No stacking state.  Cleanup via trap.
#   - Exit non-zero on failure.
#   - Print clear pass/fail per test.
#
# Runs on the host (no Docker, no adhoc container needed).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Inside existential-adhoc the full repo is mounted at /repo; on the host,
# navigate up from src/test/unit/ to the repo root.
if [[ -n "${IN_CONTAINER:-}" ]]; then
    REPO="/repo"
else
    REPO="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
fi
EXISTENTIAL="${REPO}/existential.sh"

# Export docker/podman stubs so CLI subprocess invocations (bash "$EXISTENTIAL"
# --help, etc.) don't hit the real runtime-detection block. The stubs are also
# re-declared inside _source_existential's subshell, which is harmless.
docker()             { :; }
podman()             { :; }
distrobox-host-exec() { return 1; }
export -f docker podman distrobox-host-exec 2>/dev/null || true

# ── Temp fixture dir ──────────────────────────────────────────────────────────

TMPDIR_ROOT="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR_ROOT"; }
trap cleanup EXIT

# ── Counters ──────────────────────────────────────────────────────────────────

PASS=0
FAIL=0
FAIL_NAMES=()

_ok() {
    local name="$1"
    printf '  PASS  %s\n' "$name"
    (( PASS++ )) || true
}

_fail() {
    local name="$1" reason="${2:-}"
    printf '  FAIL  %s\n' "$name"
    [ -n "$reason" ] && printf '        %s\n' "$reason"
    (( FAIL++ )) || true
    FAIL_NAMES+=("$name")
}

# assert_eq TESTNAME EXPECTED ACTUAL
assert_eq() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        _ok "$name"
    else
        _fail "$name" "expected=$(printf '%q' "$expected")  got=$(printf '%q' "$actual")"
    fi
}

# assert_exit TESTNAME EXPECTED_RC CMD [ARGS...]
assert_exit() {
    local name="$1" expected_rc="$2"
    shift 2
    local actual_rc=0
    "$@" >/dev/null 2>&1 || actual_rc=$?
    if [[ "$actual_rc" == "$expected_rc" ]]; then
        _ok "$name"
    else
        _fail "$name" "expected exit $expected_rc  got exit $actual_rc  (cmd: $*)"
    fi
}

# assert_output_contains TESTNAME NEEDLE CMD [ARGS...]
assert_output_contains() {
    local name="$1" needle="$2"
    shift 2
    local out
    out=$( "$@" 2>&1 ) || true
    if echo "$out" | grep -qF -- "$needle"; then
        _ok "$name"
    else
        _fail "$name" "output did not contain: $needle"
    fi
}

# ── Source helpers ────────────────────────────────────────────────────────────
#
# We source existential.sh with Docker/podman stubbed and SCRIPT_DIR overridden
# so the runtime-detection block (which calls docker --version) never reaches
# real Docker.  We also stub ensure_adhoc_built and run_adhoc so that any test
# accidentally reaching those helpers fails loudly rather than trying to spawn
# a container.

_source_existential() {
    local fake_repo="$1"    # the fake SCRIPT_DIR to inject
    local expr="${2:-:}"    # bash expression to eval after sourcing
    # Sub-shell: source, then emit the function body we want to call via eval.
    # We can't easily share functions across sub-shells, so instead we run the
    # entire test expression inside a sub-shell that has sourced the file.
    (
        # Stub out the things that would fail outside Docker.
        docker()  { :; }
        podman()  { :; }
        distrobox-host-exec() { return 1; }
        export -f docker podman 2>/dev/null || true

        # Source the definitions only: everything above the "Entry point"
        # marker, so the dispatch at the bottom never runs.
        local src_lines
        src_lines=$(grep -n '^# ── Entry point' "$EXISTENTIAL" | head -1 | cut -d: -f1)
        # shellcheck disable=SC1090
        . <(head -n "$(( src_lines - 1 ))" "$EXISTENTIAL")

        # existential.sh line 15 sets SCRIPT_DIR to the real repo path — override
        # it now so the helpers see the fake tree we built for this test.
        SCRIPT_DIR="$fake_repo"

        # The shared service-enablement helpers live in src/utils/service-common.sh.
        # existential.sh sources them guarded by [[ -f "$SCRIPT_DIR/..." ]], which
        # is false during the process-substitution source above (SCRIPT_DIR was the
        # /dev/fd path then), so load them here from the real repo. They read
        # $SCRIPT_DIR (now the fake tree) at call time.
        # shellcheck source=../../utils/service-common.sh
        . "${REPO}/src/utils/service-common.sh"
        # shellcheck source=../../utils/adhoc.sh
        . "${REPO}/src/utils/adhoc.sh"

        # Now the functions are defined.  Run the expression the caller provided.
        eval "$expr"
    )
}

# ── Build a minimal fake repo tree ────────────────────────────────────────────

make_fake_repo() {
    # Creates a fake repo rooted at $TMPDIR_ROOT/<name> with the category dirs
    # existential.sh expects.  Returns the path via stdout.
    local name="$1"; shift
    local root="${TMPDIR_ROOT}/${name}"
    mkdir -p "${root}/hosting/caddy"
    mkdir -p "${root}/hosting/pihole"
    mkdir -p "${root}/ai/hermes"
    mkdir -p "${root}/ai/ollama"
    mkdir -p "${root}/services/automation"
    mkdir -p "${root}/services/mealie"
    mkdir -p "${root}/nas/nextcloud"
    mkdir -p "${root}/src/lib"
    # create stub src/lib scripts so _list_setup_actions has something to list
    touch "${root}/src/lib/rclone.sh"
    echo "$root"
}

# ── Section: _enable_var_for ──────────────────────────────────────────────────

echo ""
echo "=== _enable_var_for ==="

FAKE_REPO="$(make_fake_repo enable_var)"

_run_enable_var_for() {
    local path="$1"
    _source_existential "$FAKE_REPO" "_enable_var_for '${path}'"
}

assert_eq "_enable_var_for ai/hermes → EXIST_IS_AI_HERMES" \
    "EXIST_IS_AI_HERMES" \
    "$(_run_enable_var_for "${FAKE_REPO}/ai/hermes")"

assert_eq "_enable_var_for services/automation → EXIST_IS_SERVICES_AUTOMATION" \
    "EXIST_IS_SERVICES_AUTOMATION" \
    "$(_run_enable_var_for "${FAKE_REPO}/services/automation")"

assert_eq "_enable_var_for hosting/caddy → EXIST_IS_HOSTING_CADDY" \
    "EXIST_IS_HOSTING_CADDY" \
    "$(_run_enable_var_for "${FAKE_REPO}/hosting/caddy")"

assert_eq "_enable_var_for nas/nextcloud → EXIST_IS_NAS_NEXTCLOUD" \
    "EXIST_IS_NAS_NEXTCLOUD" \
    "$(_run_enable_var_for "${FAKE_REPO}/nas/nextcloud")"

# Hyphenated slug: actual-budget → EXIST_IS_SERVICES_ACTUAL_BUDGET
FAKE_REPO2="$(make_fake_repo enable_var2)"
mkdir -p "${FAKE_REPO2}/services/actual-budget"
assert_eq "_enable_var_for services/actual-budget → EXIST_IS_SERVICES_ACTUAL_BUDGET" \
    "EXIST_IS_SERVICES_ACTUAL_BUDGET" \
    "$(_source_existential "$FAKE_REPO2" "_enable_var_for '${FAKE_REPO2}/services/actual-budget'")"

# ── Section: _find_service_dir_for_slug ───────────────────────────────────────

echo ""
echo "=== _find_service_dir_for_slug ==="

FAKE_FIND="$(make_fake_repo find_svc)"

_run_find_slug() {
    local slug="$1"
    _source_existential "$FAKE_FIND" "_find_service_dir_for_slug '${slug}'"
}

assert_eq "_find_service_dir_for_slug hermes → ai/hermes path" \
    "${FAKE_FIND}/ai/hermes" \
    "$(_run_find_slug "hermes")"

assert_eq "_find_service_dir_for_slug caddy → hosting/caddy path" \
    "${FAKE_FIND}/hosting/caddy" \
    "$(_run_find_slug "caddy")"

assert_eq "_find_service_dir_for_slug automation → services/automation path" \
    "${FAKE_FIND}/services/automation" \
    "$(_run_find_slug "automation")"

# Unknown slug: function should exit non-zero (returns 1 in sub-shell)
_slug_missing_rc=0
(
    _source_existential "$FAKE_FIND" "_find_service_dir_for_slug 'does-not-exist'" 2>/dev/null
) || _slug_missing_rc=$?
if [[ "$_slug_missing_rc" -ne 0 ]]; then
    _ok "_find_service_dir_for_slug unknown slug → non-zero exit"
else
    _fail "_find_service_dir_for_slug unknown slug → non-zero exit" "expected non-zero, got 0"
fi

# ── Section: _has_any_enabled ─────────────────────────────────────────────────

echo ""
echo "=== _has_any_enabled ==="

FAKE_HAS="$(make_fake_repo has_enabled)"

_has_enabled_with_env() {
    local env_content="$1"
    local env_file="${FAKE_HAS}/.env.shared"
    printf '%s\n' "$env_content" > "$env_file"
    local rc=0
    _source_existential "$FAKE_HAS" "_has_any_enabled" >/dev/null 2>&1 || rc=$?
    rm -f "$env_file"
    return $rc
}

# At least one EXIST_IS_*=true → should return 0 (true)
if _has_enabled_with_env "EXIST_IS_AI_HERMES=true"; then
    _ok "_has_any_enabled: single true entry → exits 0"
else
    _fail "_has_any_enabled: single true entry → exits 0" "returned non-zero"
fi

# Multiple entries, one true
if _has_enabled_with_env $'EXIST_IS_AI_HERMES=false\nEXIST_IS_SERVICES_AUTOMATION=true'; then
    _ok "_has_any_enabled: mixed entries with one true → exits 0"
else
    _fail "_has_any_enabled: mixed entries with one true → exits 0" "returned non-zero"
fi

# All false → should return non-zero
if ! _has_enabled_with_env $'EXIST_IS_AI_HERMES=false\nEXIST_IS_SERVICES_AUTOMATION=false'; then
    _ok "_has_any_enabled: all false → exits non-zero"
else
    _fail "_has_any_enabled: all false → exits non-zero" "unexpectedly returned 0"
fi

# No .env.shared → should return non-zero (grep fails on missing file)
rm -f "${FAKE_HAS}/.env.shared"
if ! _source_existential "$FAKE_HAS" "_has_any_enabled" >/dev/null 2>&1; then
    _ok "_has_any_enabled: no .env.shared → exits non-zero"
else
    _fail "_has_any_enabled: no .env.shared → exits non-zero" "unexpectedly returned 0"
fi

# Commented-out line should NOT count
if ! _has_enabled_with_env "# EXIST_IS_AI_HERMES=true"; then
    _ok "_has_any_enabled: commented-out line → exits non-zero"
else
    _fail "_has_any_enabled: commented-out line → exits non-zero" "comment was matched"
fi

# Default-enabled services must NOT count as a user choice: a flag that ships
# true would otherwise report an untouched clone as configured, and the
# first-run quest would never fire. (Caddy used to ship true.)
_has_enabled_with_tmpl() {
    local env_content="$1" tmpl_content="$2"
    printf '%s\n' "$env_content"  > "${FAKE_HAS}/.env.shared"
    printf '%s\n' "$tmpl_content" > "${FAKE_HAS}/.env.exist.shared"
    local rc=0
    _source_existential "$FAKE_HAS" "_has_any_enabled" >/dev/null 2>&1 || rc=$?
    rm -f "${FAKE_HAS}/.env.shared" "${FAKE_HAS}/.env.exist.shared"
    return $rc
}

if ! _has_enabled_with_tmpl "EXIST_IS_HOSTING_CADDY=true" "EXIST_IS_HOSTING_CADDY=true"; then
    _ok "_has_any_enabled: only a default-enabled service → exits non-zero"
else
    _fail "_has_any_enabled: only a default-enabled service → exits non-zero" \
          "a shipped default was counted as a user choice"
fi

if _has_enabled_with_tmpl $'EXIST_IS_HOSTING_CADDY=true\nEXIST_IS_AI_HERMES=true' \
                          $'EXIST_IS_HOSTING_CADDY=true\nEXIST_IS_AI_HERMES=false'; then
    _ok "_has_any_enabled: default plus one user choice → exits 0"
else
    _fail "_has_any_enabled: default plus one user choice → exits 0" "returned non-zero"
fi

# A trailing comment in the template must not stop the default from matching.
if ! _has_enabled_with_tmpl "EXIST_IS_SERVICES_IMMICH=true" \
                            "EXIST_IS_SERVICES_IMMICH=true # run this from its own dir"; then
    _ok "_has_any_enabled: default with a trailing comment → exits non-zero"
else
    _fail "_has_any_enabled: default with a trailing comment → exits non-zero" \
          "the trailing comment defeated the default match"
fi

# ── Section: service_is_enabled ───────────────────────────────────────────────

echo ""
echo "=== service_is_enabled ==="

FAKE_SVC="$(make_fake_repo svc_enabled)"

_svc_enabled_with_env() {
    local env_content="$1" path="$2"
    printf '%s\n' "$env_content" > "${FAKE_SVC}/.env.shared"
    local rc=0
    _source_existential "$FAKE_SVC" "service_is_enabled '${path}'" >/dev/null 2>&1 || rc=$?
    rm -f "${FAKE_SVC}/.env.shared"
    return $rc
}

# hermes enabled
if _svc_enabled_with_env "EXIST_IS_AI_HERMES=true" "${FAKE_SVC}/ai/hermes"; then
    _ok "service_is_enabled: hermes=true → exits 0"
else
    _fail "service_is_enabled: hermes=true → exits 0" "returned non-zero"
fi

# hermes disabled
if ! _svc_enabled_with_env "EXIST_IS_AI_HERMES=false" "${FAKE_SVC}/ai/hermes"; then
    _ok "service_is_enabled: hermes=false → exits non-zero"
else
    _fail "service_is_enabled: hermes=false → exits non-zero" "unexpectedly returned 0"
fi

# var missing entirely (should default to false)
if ! _svc_enabled_with_env "SOME_OTHER_VAR=true" "${FAKE_SVC}/ai/hermes"; then
    _ok "service_is_enabled: var absent → exits non-zero (defaults false)"
else
    _fail "service_is_enabled: var absent → exits non-zero (defaults false)" "unexpectedly returned 0"
fi

# No .env.shared → defaults to false
rm -f "${FAKE_SVC}/.env.shared"
if ! _source_existential "$FAKE_SVC" "service_is_enabled '${FAKE_SVC}/ai/hermes'" >/dev/null 2>&1; then
    _ok "service_is_enabled: no .env.shared → exits non-zero"
else
    _fail "service_is_enabled: no .env.shared → exits non-zero" "unexpectedly returned 0"
fi

# ── Section: CLI — --help ─────────────────────────────────────────────────────

echo ""
echo "=== CLI: --help ==="

assert_exit    "existential.sh --help → exit 0"      0 bash "$EXISTENTIAL" --help
assert_output_contains "existential.sh --help → prints Actions" \
    "Actions:" bash "$EXISTENTIAL" --help
assert_output_contains "existential.sh --help → mentions reset" \
    "reset" bash "$EXISTENTIAL" --help

# ── Section: _report_login — the end of a first run ──────────────────────────
#
# A first run where both defaults were accepted has to say what the username is
# and where both live, next to ntfy's phone-app login — and never the password.

FAKE_LOGIN="$(make_fake_repo login)"
printf 'EXIST_USERNAME=admin\nEXIST_PASSWORD=s3cretPassw0rdValue\nEXIST_IS_SERVICES_NTFY=true\nEXIST_TAILNET_NAME=box.tail1.ts.net\n' \
    > "${FAKE_LOGIN}/.env.shared"
_login_out="$(_source_existential "$FAKE_LOGIN" "_report_login" 2>&1)"
for _want in "admin" "EXIST_USERNAME in .env.shared" "EXIST_PASSWORD in .env.shared" \
             "https://box.tail1.ts.net:8443" "services/ntfy/.env"; do
    if grep -qF -- "$_want" <<<"$_login_out"; then _ok "_report_login names: ${_want}"
    else _fail "_report_login names: ${_want}" "$_login_out"; fi
done
if grep -qF "s3cretPassw0rdValue" <<<"$_login_out"; then
    _fail "_report_login never prints the password" "$_login_out"
else
    _ok "_report_login never prints the password"
fi

# ── Section: _start_on_boot — the stack comes back after a reboot ────────────
#
# systemctl and loginctl are stubbed: each call is logged, and the answers say
# nothing is enabled yet. Rootless Podman gets both turned on; Docker gets the
# one root command printed, never run.

FAKE_BOOT="$(make_fake_repo boot)"
_boot_stubs='CALLS="${TMPDIR_ROOT}/boot-calls"; : > "$CALLS"
systemctl() { echo "systemctl $*" >> "$CALLS"; [[ " $* " == *" enable "* ]]; }
loginctl()  { echo "loginctl $*" >> "$CALLS"; [[ "$1" == enable-linger ]]; }
id() { [[ "$1" == -un ]] && echo alice || command id "$@"; }'
_boot_out="$(_source_existential "$FAKE_BOOT" "${_boot_stubs}
DOCKER_CMD=podman ROOTLESS_PODMAN=true _start_on_boot; cat \"\$CALLS\"" 2>&1)"
for _want in "systemctl --user -q enable podman-restart.service" "loginctl enable-linger alice"; do
    if grep -qF -- "$_want" <<<"$_boot_out"; then _ok "_start_on_boot, rootless Podman → ${_want}"
    else _fail "_start_on_boot, rootless Podman → ${_want}" "$_boot_out"; fi
done
_boot_out="$(_source_existential "$FAKE_BOOT" "${_boot_stubs}
DOCKER_CMD=docker; docker() { echo Ubuntu; }; _start_on_boot; cat \"\$CALLS\"" 2>&1)"
if grep -qF "sudo systemctl enable docker" <<<"$_boot_out"; then _ok "_start_on_boot, Docker not enabled → prints the one command"
else _fail "_start_on_boot, Docker not enabled → prints the one command" "$_boot_out"; fi
if grep -q "^systemctl.* enable " <<<"$_boot_out"; then _fail "_start_on_boot never enables a system unit itself" "$_boot_out"
else _ok "_start_on_boot never enables a system unit itself"; fi

# ── Section: CLI — refuses sudo ───────────────────────────────────────────────

_fakeroot="${TMPDIR_ROOT}/fakeroot-bin"
mkdir -p "$_fakeroot"
printf '#!/bin/sh\necho 0\n' > "${_fakeroot}/id"
chmod +x "${_fakeroot}/id"
assert_exit "existential.sh under sudo → exits 1" 1 \
    env PATH="${_fakeroot}:$PATH" SUDO_USER=someone bash "$EXISTENTIAL" --help
assert_output_contains "existential.sh under sudo → points at the docker group" "usermod -aG docker" \
    env PATH="${_fakeroot}:$PATH" SUDO_USER=someone bash "$EXISTENTIAL" --help

# ── Section: CLI — unknown actions ────────────────────────────────────────────

echo ""
echo "=== CLI: unknown actions ==="

assert_exit "existential.sh foobar → exit 1"         1 bash "$EXISTENTIAL" foobar
assert_exit "existential.sh 123abc → exit 1"         1 bash "$EXISTENTIAL" 123abc
(
    out=$(bash "$EXISTENTIAL" foobar 2>&1) || true
    if echo "$out" | grep -qF "Unknown action"; then
        _ok "existential.sh foobar → stderr mentions 'Unknown action'"
    else
        _fail "existential.sh foobar → stderr mentions 'Unknown action'" \
              "output: $(echo "$out" | head -3)"
    fi
)

# ── Section: CLI — `run` with no args prints usage ────────────────────────────

echo ""
echo "=== CLI: run (no args) ==="

# `run` with no args calls _list_setup_actions, which does NOT touch Docker.
# It only scans SCRIPT_DIR/src/lib and the service dirs — safe to call.
(
    out=$(bash "$EXISTENTIAL" run 2>&1) || true
    if echo "$out" | grep -qF "Usage:"; then
        _ok "existential.sh run (no args) → prints Usage"
    else
        _fail "existential.sh run (no args) → prints Usage" \
              "output: $(echo "$out" | head -5)"
    fi
    # reset has one entry point (./existential.sh reset); backup-config is gone.
    for gone in reset backup-config; do
        if echo "$out" | grep -qE "run ${gone}\$"; then
            _fail "existential.sh run (no args) → does not list ${gone}"
        else
            _ok "existential.sh run (no args) → does not list ${gone}"
        fi
    done
)

# ── Section: CLI — `test <name>` finds a suite by file name ──────────────────

echo ""
echo "=== CLI: test <name> dispatch ==="

# DOCKER_CMD=echo makes run_adhoc print the command it would run in adhoc.
assert_output_contains "test existential → runs src/test/unit/test-existential.sh" \
    "/src/test/unit/test-existential.sh" env DOCKER_CMD=echo bash "$EXISTENTIAL" test existential

# ── Section: CLI — `run` with two args dispatches to service action ───────────

echo ""
echo "=== CLI: run <slug> <action> dispatch ==="

# Create a fake service script in the real repo tree — but we don't want to
# modify the real repo.  Instead we invoke existential.sh with a nonexistent
# slug+action combination and verify it exits 1 with a useful error.

assert_exit "run nonexistent-slug action → exit 1"   1 bash "$EXISTENTIAL" run nonexistent-slug someaction

(
    out=$(bash "$EXISTENTIAL" run nonexistent-slug someaction 2>&1) || true
    if echo "$out" | grep -q "Unknown run target\|No script at"; then
        _ok "run nonexistent-slug → helpful error message"
    else
        _fail "run nonexistent-slug → helpful error message" \
              "output: $(echo "$out" | head -5)"
    fi
)

# ── Section: CLI — `run` with one utility arg (src/lib) ──────────────────────

echo ""
echo "=== CLI: run <utility> dispatch ==="

# A utility that does NOT exist in src/lib should fall through to service
# lookup and fail with "Unknown run target".
assert_exit "run nonexistent-utility → exit 1"       1 bash "$EXISTENTIAL" run totally-fake-utility

# A slug that matches a real service dir should NOT reach Docker — it should
# fail because there's no exist.initial.sh.  We test with a slug that has no
# exist.initial.sh so _run_service_action errors cleanly.
# Verify "No script at" is emitted rather than a Docker error.
(
    # 'hermes' has no exist.initial.sh in the repo.
    # Check dynamically so the test stays accurate even if that changes.
    if [[ ! -f "${REPO}/ai/hermes/exist.initial.sh" ]]; then
        out=$(bash "$EXISTENTIAL" run hermes 2>&1) || true
        if echo "$out" | grep -qF "No script at"; then
            _ok "run hermes (no initial.sh) → 'No script at' error"
        else
            _fail "run hermes (no initial.sh) → 'No script at' error" \
                  "output: $(echo "$out" | head -5)"
        fi
    else
        printf '  SKIP  run hermes (no initial.sh) → ai/hermes/exist.initial.sh now exists, skipping\n'
    fi
)

# ── Section: CLI — validate subcommand unknown name ──────────────────────────

echo ""
echo "=== CLI: validate unknown name ==="

assert_exit "validate unknown-name → exit 1"         1 bash "$EXISTENTIAL" validate unknown-name
(
    out=$(bash "$EXISTENTIAL" validate unknown-name 2>&1) || true
    if echo "$out" | grep -q "Unknown validation"; then
        _ok "validate unknown-name → mentions 'Unknown validation'"
    else
        _fail "validate unknown-name → mentions 'Unknown validation'" \
              "output: $(echo "$out" | head -3)"
    fi
)

# ── Section: Core's membership ───────────────────────────────────────────────
# Core is "open the work dir, talk to an AI, have decree automate it". The
# partition and tour count are validate-conventions' job; this pins WHAT is in
# it, so a service creeping back into Core is a deliberate edit here too.

echo ""
echo "=== Core quest: membership ==="

CORE_MD="${REPO}/src/quests/00-core.md"
_core_fm="$(awk 'NR==1 && /^---$/{f=1;next} f && /^---$/{exit} f' "$CORE_MD")"
assert_eq "Core enables exactly its three services" \
    "EXIST_IS_SERVICES_AUTOMATION EXIST_IS_SERVICES_CODE_SERVER EXIST_IS_SERVICES_NTFY" \
    "$(awk '/^services:/{f=1;next} /^[^ ]/{f=0} f && /var:/{print $3}' <<< "$_core_fm" | sort | xargs)"
assert_eq "Core copies no ollama, homeassistant, openviking or nextcloud template" \
    "" "$(grep -E '^\s*-?\s*src:' <<< "$_core_fm" | grep -iE 'ollama|homeassistant|openviking|nextcloud|note-connect' || true)"

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
