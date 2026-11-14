#!/usr/bin/env bash
# test-update.sh — the update plugin keeps an install on its branch, against a
# local bare remote, with ./existential.sh and docker stubbed:
#
#   current    nothing new: nothing is run
#   behind     a fast-forward: pulled, ./existential.sh then compose up, you are told
#   diverged   a local commit: nothing changes, and you are told why
#
# Everything is written under a temp dir, removed in the trap.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
[[ -f "${REPO_DIR}/.env.exist.shared" ]] || REPO_DIR="/repo"
for _t in git yq; do
    command -v "$_t" >/dev/null 2>&1 || { echo "skipped — ${_t} not available (run inside existential-adhoc)"; exit 0; }
done

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }
assert_eq()  { if [[ "$2" == "$3" ]]; then _ok "$1"; else _fail "$1" "expected=$2 got=$3"; fi; }
assert_has() { if [[ "$2" == *"$3"* ]]; then _ok "$1"; else _fail "$1" "missing: $3"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null

# The upstream, and an install cloned from it whose ./existential.sh only says it ran.
git init -q --bare "${TMP}/upstream.git"
U="${TMP}/author"; git clone -q "${TMP}/upstream.git" "$U" 2>/dev/null
mkdir -p "${U}/src/utils"; cp "${REPO_DIR}/src/utils/adhoc.sh" "${U}/src/utils/"
# A worker with no services (the no-services file) gets no docker-compose.yml.
printf '#!/usr/bin/env bash\necho ran >> "%s/existential-ran"\n[[ -f "%s/no-services" ]] || touch docker-compose.yml\n' "$TMP" "$TMP" > "${U}/existential.sh"; chmod +x "${U}/existential.sh"
printf 'host/\ndocker-compose.yml\n' > "${U}/.gitignore"
(cd "$U" && git add -A && git commit -qm one && git push -q origin HEAD 2>/dev/null)
I="${TMP}/install"; git clone -q "${TMP}/upstream.git" "$I"

# The plugin, unpacked into the install's host project as the stack installs it.
( source "${REPO_DIR}/automation/lib/automations/registry.sh"; source "${REPO_DIR}/automation/lib/automations/plugin.sh"
  plugin_unpack update "${I}/host" ) >/dev/null
UPDATE="${I}/host/.decree/scripts/update/update.sh"

# docker: `info` answers, everything else is written down.
mkdir -p "${TMP}/bin"
printf '#!/usr/bin/env bash\n[[ "$1" == --version || "$1" == info ]] && exit 0\necho "$*" >> "%s/docker"; cat >> "%s/told" 2>/dev/null || true\n' "$TMP" "$TMP" > "${TMP}/bin/docker"
chmod +x "${TMP}/bin/docker"
run() { (cd "${I}/host" && env PATH="${TMP}/bin:${PATH}" bash "$UPDATE") > "${TMP}/log" 2>&1; echo $?; }
reset() { rm -f "${TMP}/existential-ran" "${TMP}/docker" "${TMP}/told" "${I}/docker-compose.yml"; }

echo ""; echo "=== current ==="
assert_eq "an install with nothing new" "0" "$(run)"
assert_has "...says so" "$(cat "${TMP}/log")" "up to date"
assert_eq "...and runs nothing" "no" "$([[ -e "${TMP}/existential-ran" || -e "${TMP}/docker" ]] && echo yes || echo no)"

echo ""; echo "=== behind ==="
(cd "$U" && echo two > two && git add two && git commit -qm "two" && git push -q origin HEAD 2>/dev/null)
reset
assert_eq "an install behind its branch updates" "0" "$(run)"
assert_eq "...to the branch" "$(git -C "$U" rev-parse HEAD)" "$(git -C "$I" rev-parse HEAD)"
assert_eq "...then runs ./existential.sh" "ran" "$(cat "${TMP}/existential-ran" 2>/dev/null)"
assert_has "...then brings the stack up" "$(cat "${TMP}/docker" 2>/dev/null)" "compose up -d"
assert_has "...and tells you, through the stack's notify" "$(cat "${TMP}/docker" 2>/dev/null)" "exec -i automation decree emit --machine notify --param ntfy_title=Updated"
assert_has "...naming the commit" "$(cat "${TMP}/told" 2>/dev/null)" "two"

echo ""; echo "=== worker, engine and no services ==="
(cd "$U" && echo w > w && git add w && git commit -qm w && git push -q origin HEAD 2>/dev/null)
reset; touch "${TMP}/no-services"
assert_eq "a host with no docker-compose.yml updates" "0" "$(run)"
assert_eq "...without compose" "0" "$(grep -c 'compose' "${TMP}/docker" 2>/dev/null || true)"
rm -f "${TMP}/no-services"

echo ""; echo "=== diverged ==="
(cd "$U" && echo three > three && git add three && git commit -qm three && git push -q origin HEAD 2>/dev/null)
(cd "$I" && echo mine > mine && git add mine && git commit -qm mine)
mine="$(git -C "$I" rev-parse HEAD)"; reset
assert_eq "an install with a commit of its own does not update" "1" "$(run)"
assert_eq "...nothing changes" "$mine" "$(git -C "$I" rev-parse HEAD)"
assert_eq "...nothing runs" "no" "$([[ -e "${TMP}/existential-ran" ]] && echo yes || echo no)"
assert_has "...and you are told" "$(cat "${TMP}/docker" 2>/dev/null)" "ntfy_title=Update stopped"

[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then echo "Failed:"; for n in "${FAIL_NAMES[@]}"; do echo "  - $n"; done; exit 1; fi
