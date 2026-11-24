---
name: repo_develop
extends: decree_develop
x-exist-project: host
needs:
  - repo
scripts:
  gate.sh: |
    #!/usr/bin/env bash
    # The repo's gate is its pre-push hook, so the checks live in one place. Names
    # `pass` or `fail`; a non-zero exit (no docker or podman) means they could not run.
    set -euo pipefail
    log="${DECREE_ROOT_RUN_DIR}/gate.log"
    command -v docker >/dev/null || command -v podman >/dev/null || {
      echo "gate: neither docker nor podman on PATH; the checks cannot run" | tee "${log}" >&2
      exit 1
    }
    if bash .githooks/pre-push 2>&1 | tee "${log}"; then
      echo pass > "${DECREE_EVENT_FILE}"
    else
      echo fail > "${DECREE_EVENT_FILE}"
    fi
  conventions.md: |
    # This repo's conventions

    - Read CLAUDE.md first: its rules win over any habit. Delete and simplify before you add.
    - An order file (`order: <machine>/<file>` in the message's frontmatter) declares the state
      the repository must be in for one concern. Parts may already be true; leave those alone.
      If it ran before and was edited since, `git log -p -- .decree/machines/<machine>/order/<file>`
      shows how: make the repository match it as it is now, and undo whatever only the old
      version asked for.
    - Documentation (README.md, site/docs/, the homepage in site/src/) describes the repository
      as it is after your change: update what your change makes untrue, in this run.
  requirements: |
    # What the repo's machines need on the host, checked by decree_infra's `run.sh check`
    # (decree_develop's precheck). kind name version source
    command   claude
    command   git
---
# repo_develop

decree's `decree_develop`, for this repo: an order file in `.decree/machines/repo_develop/order/`
(the repo's migrations) or a message is implemented by Claude, then gated by the repo's own
`.githooks/pre-push`, fixed if that fails, and checked against what the message asks; one
commit per run. What it changes from `decree_develop` is the gate, `conventions.md` (CLAUDE.md
and the declarative order files) and the tools it needs.
