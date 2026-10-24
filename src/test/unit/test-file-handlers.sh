#!/usr/bin/env bash
# test-file-handlers.sh — automation/lib/file-handlers.ts starts a handler's
# machine once a matching workspace file has been quiet, with `path` and
# `change`; a delete fires at once; .gitignore'd paths, .git/ and files no
# handler matches start nothing; an edit to handlers.yml applies without a restart.
#
# Runs the real watcher against a scratch workspace with its own decree project
# and counts what lands in inbox/, so it needs node, yq, decree and git (the adhoc
# image has them all). Quiet periods are a few seconds to keep it short.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
[[ -f "${REPO_DIR}/.env.exist.shared" ]] || REPO_DIR="/repo"
WATCHER="${REPO_DIR}/automation/lib/file-handlers.ts"

PASS=0; FAIL=0; FAIL_NAMES=()
_ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
_fail() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; FAIL=$((FAIL + 1)); FAIL_NAMES+=("$1"); }
check() { if eval "$2"; then _ok "$1"; else _fail "$1" "$2"; fi; }

for _bin in node yq decree git; do
    command -v "$_bin" >/dev/null || { echo "file-handlers: needs ${_bin} (run it through ./existential.sh test unit)"; exit 1; }
done

TMP="$(mktemp -d)"
trap 'kill "$WATCH_PID" 2>/dev/null; rm -rf "$TMP"' EXIT
WS="${TMP}/workspace"
mkdir -p "$WS"/.decree/{machines,scripts,inbox} "$WS"/notes/to-process "$WS"/repo/.git "$WS"/scratch
cat > "$WS/.decree/machines/on_file.yml" << 'EOF'
name: on_file
description: Test machine for file handlers.
data:
  path: { type: string, default: "" }
  change: { type: string, default: "" }
initial: run
states:
  run:
    invoke: on_file
    transitions: { done: done }
  done: { final: true }
  failed: { final: true }
EOF
printf '#!/usr/bin/env bash\n' > "$WS/.decree/scripts/on_file.sh"
chmod +x "$WS/.decree/scripts/on_file.sh"
printf 'inbox/\n' > "$WS/.decree/.gitignore"
cat > "$WS/.decree/handlers.yml" << 'EOF'
- match: notes/to-process/*.md
  machine: on_file
  quiet: 2
- match: "**/*.pdf"
  machine: on_file
  quiet: 1
- match: slow/*.txt
  machine: on_file
EOF

runs() {         # <path> [change]: how many runs were queued for it
    grep -lx "  path: $1" "$WS"/.decree/inbox/*.md 2>/dev/null \
        | xargs -r grep -lx "  change: ${2:-.*}" | wc -l
}

env -u DECREE_DIR FILE_HANDLERS_WORKSPACE="$WS" node "$WATCHER" > "${TMP}/watcher.log" 2>&1 &
WATCH_PID=$!
for _ in $(seq 100); do grep -q watching "${TMP}/watcher.log" && break; sleep 0.1; done

# Five writes in two seconds, then quiet: one run, after the last write.
for i in 1 2 3 4 5; do echo "draft $i" > "$WS/notes/to-process/a.md"; sleep 0.4; done
sleep 1
check "no run while the file is still settling" "[[ \$(runs notes/to-process/a.md) == 0 ]]"
sleep 2.5
check "five quick writes start exactly one run" "[[ \$(runs notes/to-process/a.md) == 1 ]]"
check "the run gets path and change=created" "[[ \$(runs notes/to-process/a.md created) == 1 ]]"

mkdir -p "$WS/deep/er" "$WS/slow"
echo pdf > "${TMP}/doc.pdf"
cp "${TMP}/doc.pdf" "$WS/deep/er/doc.pdf"
cp "${TMP}/doc.pdf" "$WS/repo/.git/inside.pdf"
echo x > "$WS/unmatched.txt"
echo x > "$WS/slow/a.txt"
sleep 2.5
check "a PDF copied anywhere starts one run" "[[ \$(runs deep/er/doc.pdf created) == 1 ]]"
check "nothing inside .git/ starts a run" "[[ \$(runs repo/.git/inside.pdf) == 0 ]]"
check "a file matching no handler starts nothing" "[[ \$(runs unmatched.txt) == 0 ]]"
check "the default quiet period is longer than a few seconds" "[[ \$(runs slow/a.txt) == 0 ]]"

rm "$WS/deep/er/doc.pdf"
sleep 0.5
check "a delete fires without waiting" "[[ \$(runs deep/er/doc.pdf deleted) == 1 ]]"

mkdir "${TMP}/incoming"
cp "${TMP}/doc.pdf" "${TMP}/incoming/doc.pdf"
mv "${TMP}/incoming" "$WS/incoming"
sleep 2
check "a folder moved in starts a run per matching file" "[[ \$(runs incoming/doc.pdf created) == 1 ]]"
mv "$WS/incoming" "${TMP}/gone"
sleep 0.5
check "a folder moved out is a delete per file" "[[ \$(runs incoming/doc.pdf deleted) == 1 ]]"

# A new handler and a .gitignore, no restart.
printf 'scratch/\n' > "$WS/.gitignore"
cat >> "$WS/.decree/handlers.yml" << 'EOF'
- match: "**/*.md"
  machine: on_file
  quiet: 1
EOF
sleep 0.5
echo a > "$WS/scratch/a.md"
echo b > "$WS/notes/b.md"
sleep 2
check "an edit to handlers.yml applies without a restart" "[[ \$(runs notes/b.md created) == 1 ]]"
check "a .gitignore'd path starts nothing" "[[ \$(runs scratch/a.md) == 0 ]]"
echo b2 > "$WS/notes/b.md"
sleep 2
check "a second change to a known file is change=modified" "[[ \$(runs notes/b.md modified) == 1 ]]"

# Claude in the workspace is told how to write one (entrypoint.sh appends the notes to the decree skill).
NOTES="${REPO_DIR}/automation/lib/skill-notes.md"
check "the skill notes describe handlers.yml" "grep -qF 'handlers.yml' '$NOTES' && grep -qiF 'folder or a pattern' '$NOTES'"
check "the entrypoint appends the notes to the skill" \
    "grep -qF 'cat .decree/lib/skill-notes.md >> /workspace/.claude/skills/decree/SKILL.md' '${REPO_DIR}/services/automation/decree/entrypoint.sh'"
check "the automation container starts the watcher" "grep -qx '      - FILE_HANDLERS=1' '${REPO_DIR}/services/automation/docker-compose.exist.yml'"

[[ "${TEST_SELFCHECK:-}" == 1 ]] && _fail "selfcheck canary (deliberate failure)"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then
    printf 'Failed: %s\n' "${FAIL_NAMES[*]}"
    echo "--- watcher.log"; cat "${TMP}/watcher.log"
    exit 1
fi
