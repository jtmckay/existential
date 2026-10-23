#!/usr/bin/env bash
# onentry script of `done`: commit the run's work, titled with the message's first `# `
# heading. For a migration, decree has already added it to processed.md, so the one commit
# holds the work and the ledger line, and the title ends with the migration's file name
# (`migration:` in the run's message.md), as its run id is a time id. Nothing changed is nothing to commit. If the commit
# fails, the run ends in `failed`, not `done`. Only the project folder is committed (`-- .`),
# even if something else in a larger repository is staged.
set -euo pipefail
git add -A -- .
if git diff --cached --quiet -- .; then
  echo "nothing to commit"
  exit 0
fi
title=$(sed -n 's/^# //p' "${DECREE_MESSAGE}" | head -n 1)
title=${title:-${DECREE_MACHINE}: ${DECREE_MESSAGE_ID}}
migration=$(sed -n '2,/^---$/s/^migration: //p' "${DECREE_MESSAGE}" | head -n 1)
if [ -n "${migration}" ]; then
  title="${title} (${migration})"
fi
git commit -q -m "${title}" \
  -m "decree run ${DECREE_MESSAGE_ID} (${DECREE_MACHINE})" -- .
git log -1 --format='committed %h %s'
