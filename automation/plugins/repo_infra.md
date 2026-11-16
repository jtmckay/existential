---
machine: plugin
automation: repo_infra
project: host
needs:
  - agent
  - repo
chart:
  description: Add to the environment the project needs, the first time and every time after; Claude declares each resource in .decree/requirements, then apply installs what is missing and checks every line.
  onentry: [clean_tree] # the run starts from a clean git work tree
  initial: declare
  states:
    declare: # edits .decree/requirements, installs nothing; writes STOP instead of guessing
      invoke: declare
      transitions: {done: apply, stop: failed}
    apply: # each line: ok, or installed and checked again; a person's step (root) fails, naming it
      invoke: apply
      transitions: {done: done}
    done: {final: true, onentry: [commit]} # one commit per run; a migration's processed.md line too
    failed: {final: true, onentry: [keep]} # the run's changes stay in the tree; its attention file holds the queue
scripts:
  apply: |
    #!/usr/bin/env bash
    # infra's apply: install what .decree/requirements declares and is missing.
    exec "${DECREE_LIB}/infra/run.sh" apply
  clean_tree: |
    #!/usr/bin/env bash
    # The repo machines share this step: lib/repo/clean_tree.sh (the repo plugin).
    exec bash "${DECREE_LIB}/repo/clean_tree.sh"
  commit: |
    #!/usr/bin/env bash
    # The repo machines share this step: lib/repo/commit.sh (the repo plugin).
    exec bash "${DECREE_LIB}/repo/commit.sh"
  declare: |
    #!/usr/bin/env bash
    # infra's declare: Claude changes .decree/requirements to meet the message, and
    # installs nothing; apply does. If the change needs a choice the message does not make,
    # it writes the question to STOP instead of guessing; the run fails until a person
    # answers it in plan.md, deletes STOP and runs `decree process --retry`.
    set -euo pipefail
    . "${DECREE_LIB}/ai.sh"

    infra="${DECREE_LIB}/infra"
    plan="${DECREE_RUN_DIR}/plan.md"
    stop="${DECREE_RUN_DIR}/STOP"
    stopped() {
      [ -f "${stop}" ] || return 1
      cat "${stop}" >&2
      echo stop > "${DECREE_EVENT_FILE}"
    }
    stopped && exit 0

    prompt="You maintain this project's environment. Read ${DECREE_MESSAGE}.
    The environment is declared: .decree/requirements lists each resource the project
    needs (kind, name, version, source), in order, and ${infra}/kinds/<kind>.sh says how
    to check and install that kind. Read both, then change the lines of requirements to
    meet the message. Put a line after the lines it relies on, and pin every version the
    kind takes. Only if no kind fits, add one as a lib: entry infra/kinds/<kind>.sh of automation/plugins/repo_infra.md (${infra}/ is its installed copy, never edited), a check and an install
    function like the others: it installs into the project, never with sudo, and a step
    only a person can do (root, an account) prints the command and returns 1. A kind that
    downloads a file checks it against the sha256 in its line's source (<url>#sha256=<hex>)
    and fails on a mismatch; take the hash from what the project publishes (a SHA256SUMS
    file, the release page), never by downloading the file and hashing it yourself.
    Change nothing else. Do not run anything that installs; the next step does. You may
    look at this host read-only to find what a line relies on, and declare that too.
    If ${plan} exists, follow it. If the message needs a choice it does not make, do not
    guess: write the question to ${stop} and stop.
    Write scratch files only under ${DECREE_RUN_DIR}, never outside the project (not /tmp)."
    echo "=== AI prompt (declare) ==="
    echo "${prompt}"
    ai "${prompt}"
    stopped || true
  keep: |
    #!/usr/bin/env bash
    # The repo machines share this step: lib/repo/keep.sh (the repo plugin).
    exec bash "${DECREE_LIB}/repo/keep.sh"
lib:
  infra/run.sh: |
    #!/usr/bin/env bash
    # Check or apply each line of requirements, as Ansible applies a play: `check` reports
    # each resource ok or missing and changes nothing; `apply` installs a missing one and
    # checks it again (changed), and stops at the first that fails, naming it.
    # Usage: run.sh check|apply
    set -euo pipefail
    here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    mode=${1:?usage: run.sh check|apply}
    # One stream, so a failure prints after the lines before it.
    exec 2>&1

    missing=0
    while read -r kind name version source; do
      [[ -z ${kind} || ${kind} == \#* ]] && continue
      label="${kind} ${name}${version:+ ${version}}"
      [ -f "${here}/kinds/${kind}.sh" ] || { echo "FAILED   ${label}: no kinds/${kind}.sh" >&2; exit 1; }
      # A subshell keeps one kind's functions from the next.
      # shellcheck source=/dev/null
      if (. "${here}/kinds/${kind}.sh" && check "${name}" "${version}" "${source}"); then
        echo "ok       ${label}"
      elif [ "${mode}" = check ]; then
        echo "missing  ${label}"
        missing=1
      elif (. "${here}/kinds/${kind}.sh" && install "${name}" "${version}" "${source}" &&
        check "${name}" "${version}" "${source}"); then
        echo "changed  ${label}"
      else
        echo "FAILED   ${label}" >&2
        exit 1
      fi
    done < "${here}/../../requirements"
    exit "${missing}"
  infra/kinds/command.sh: |
    # shellcheck shell=bash
    # A command that must be on PATH, at the version if the line gives one (found in the output
    # of `<name> --version`). install cannot know this system's package manager, so it names the
    # command for a person to install, and fails.
    # A kind defines check and install, each called with the line's name, version and source.
    check() { command -v "$1" >/dev/null && { [ -z "$2" ] || "$1" --version 2>&1 | grep -qF "$2"; }; }
    install() {
      echo "$1${2:+ $2} is not on PATH: install it, then continue the run" >&2
      return 1
    }
---
# repo_infra

Add to the environment the project needs, the first time and every time after; Claude declares each resource in .decree/requirements, then apply installs what is missing and checks every line.
