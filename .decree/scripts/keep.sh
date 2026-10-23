#!/usr/bin/env bash
# onentry script of `failed`: leave the run's changes in the work tree, so a retry builds on
# the last attempt (the agent sees them in `git status` and decides what to keep), and write
# the run's `hold`, so its file in .decree/attention/ holds the queue and no other run starts
# on them. `decree process --retry` of this run removes both; to set the changes aside
# instead, stash them and delete the run's attention file.
# Only the project folder counts (`-- .`): a decree project can be a subfolder of a larger
# repository. A run that failed because a person's own changes were there from the start
# (`clean_tree` did not pass) leaves them alone and holds nothing.
set -euo pipefail
[ -f "${DECREE_RUN_DIR}/clean_tree" ] || exit 0
changes=$(git status --porcelain -- .)
if [ -z "${changes}" ]; then
  echo "no changes to keep"
  exit 0
fi
title=$(sed -n 's/^# //p' "${DECREE_MESSAGE}" | head -n 1)
attention=".decree/attention/${DECREE_MESSAGE_ID}.md"
{
  echo "run ${DECREE_MESSAGE_ID} (${title:-${DECREE_MACHINE}}) failed and kept its changes in the work tree:"
  echo "${changes}"
  echo "to continue the run on them: \`decree process --retry ${DECREE_MESSAGE_ID}\`"
  echo "to set them aside instead: \`git stash push --include-untracked -m \"decree ${DECREE_MESSAGE_ID}\" -- .\`, then delete ${attention}"
} > "${DECREE_RUN_DIR}/hold"
cat "${DECREE_RUN_DIR}/hold"
echo "no other run starts until then (${attention})"
