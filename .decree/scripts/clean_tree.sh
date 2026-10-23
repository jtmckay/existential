#!/usr/bin/env bash
# Root onentry script: the run starts from a clean git work tree, so the commit at `done`
# holds this run's work only, and a failed run's changes never mix into the next one.
# It runs again when `decree process --retry` continues the run; by then the tree holds
# the run's own work, so it checks only the first time. Only the project folder counts
# (`-- .`): a decree project can be a subfolder of a larger repository.
# When it finds changes, it names each run that passed here and is now `interrupted` or
# `failed` (an interrupted run never reaches `keep`), with the commands that continue it or
# set its changes aside, and writes those lines to the run's `leftovers`, which decree
# quotes in this run's file in .decree/attention/. It reads `decree status --format json`
# with `jq`; without `jq` on PATH it names no run.
set -euo pipefail
mark="${DECREE_RUN_DIR}/clean_tree"
leftovers="${DECREE_RUN_DIR}/leftovers"
[ -f "${mark}" ] && exit 0
command -v git >/dev/null || { echo "clean_tree: git not found on PATH" >&2; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "clean_tree: not a git work tree; run \`git init\` and commit first" >&2
  exit 1
}

# The runs that passed `clean_tree` and stopped before `done`, one line each:
# `<id> <status>`.
stopped_runs() {
  command -v jq >/dev/null || return 0
  local json
  json=$("${DECREE}" status --all --format json 2>/dev/null) || return 0
  jq -r '(.runs.interrupted // [] | map([.id, "interrupted"]))
    + (.runs.finished.failed // [] | map([.id, "failed"]))
    | .[] | @tsv' <<<"${json}" 2>/dev/null || return 0
}

# What to tell the person about each run that may have left the changes.
named_runs() {
  local id status dir title
  while IFS=$'\t' read -r id status; do
    [ -n "${id}" ] && [ "${id}" != "${DECREE_MESSAGE_ID:-}" ] || continue
    dir=".decree/runs/${id}"
    [ -f "${dir}/clean_tree" ] || continue
    title=$(sed -n 's/^# //p' "${dir}/message.md" 2>/dev/null | head -n 1)
    echo "run ${id} (${title:-no heading}) started from a clean tree and is ${status}; it may have left them:"
    echo "  to continue it on them: \`decree process --retry ${id}\`"
    echo "  to set them aside: \`git stash push --include-untracked -m \"decree ${id}\" -- .\`"
  done < <(stopped_runs)
}

rm -f "${leftovers}"
changes=$(git status --porcelain -- .)
if [ -n "${changes}" ]; then
  echo "clean_tree: uncommitted changes; commit or stash them, then run the message again:" >&2
  echo "${changes}" | head -n 20 >&2
  n=$(echo "${changes}" | wc -l)
  [ "${n}" -le 20 ] || echo "… and $((n - 20)) more" >&2
  named=$(named_runs)
  if [ -n "${named}" ]; then
    echo "${named}" >&2
    echo "${named}" > "${leftovers}"
  fi
  echo "if a failed run left them, its file in .decree/attention/ names it; continue it with \`decree process --retry <id>\`" >&2
  exit 1
fi
git rev-parse HEAD > "${mark}"
echo "clean at $(git rev-parse --short HEAD)"
