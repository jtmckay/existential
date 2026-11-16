---
machine: plugin
automation: repo_develop
project: host
needs:
  - agent
  - repo
chart:
  description: Make the repo match a message with Claude, then run the repo's pre-push gate.
  onentry: [clean_tree] # the run starts from a clean git work tree
  data:
    spec: # the migration file a reconcile re-run is for; a migration's own run needs none
      type: string
      default: ""
  initial: implement
  states:
    implement: # writes STOP instead of guessing
      invoke: implement
      transitions: {done: gate, stop: failed}
    gate: # .githooks/pre-push: pass or fail; error means it could not run
      invoke: gate
      transitions: {pass: done, fail: failed}
    done: {final: true, onentry: [record, commit]} # applied/ copy of the migration, then one commit
    failed: {final: true, onentry: [keep]} # the run's changes stay in the tree; its attention file holds the queue
scripts:
  clean_tree: |
    #!/usr/bin/env bash
    # The repo machines share this step: lib/repo/clean_tree.sh (the repo plugin).
    exec bash "${DECREE_LIB}/repo/clean_tree.sh"
  commit: |
    #!/usr/bin/env bash
    # The repo machines share this step: lib/repo/commit.sh (the repo plugin).
    exec bash "${DECREE_LIB}/repo/commit.sh"
  gate: |
    #!/usr/bin/env bash
    # develop's gate: the repo's own pre-push hook, so the checks live in one place.
    # Names `pass` or `fail`; a non-zero exit (docker missing) means they could not run.
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
  implement: |
    #!/usr/bin/env bash
    # develop's implement: Claude implements the message in small steps, noting
    # each in progress.md, so a retry continues where the last attempt stopped. If
    # the message is unclear, it writes the question to STOP instead of guessing;
    # the run fails until a person answers it in plan.md, deletes STOP and runs
    # `decree process --retry`. Its notes live in the root run's folder
    # ($DECREE_ROOT_RUN_DIR, the run's own unless it is a child run), so a child machine
    # whose steps are develop's scripts shares them.
    set -euo pipefail
    . "${DECREE_LIB}/ai.sh"

    progress="${DECREE_ROOT_RUN_DIR}/progress.md"
    plan="${DECREE_ROOT_RUN_DIR}/plan.md"
    stop="${DECREE_ROOT_RUN_DIR}/STOP"
    stopped() {
      [ -f "${stop}" ] || return 1
      cat "${stop}" >&2
      echo stop > "${DECREE_EVENT_FILE}"
    }
    stopped && exit 0

    # Migrations are declarative: the message is the desired state of its concern.
    # On a reconcile re-run, applied/ holds the version that last landed.
    previous=""
    if [ -n "${DECREE_DATA_SPEC:-}" ] && [ -f "${DECREE_PROJECT_ROOT}/.decree/applied/${DECREE_DATA_SPEC}" ]; then
      previous="
    This message landed before; the version that landed is
    .decree/applied/${DECREE_DATA_SPEC}. Diff the two: make the repository match the
    message as it is now, and undo whatever only the old version asked for."
    fi

    prompt="You are a senior engineer. Read ${DECREE_MESSAGE}: it declares the
    state the repository must be in for one concern. Make the repository match it,
    with tests. Parts may already be true; leave those alone.
    Documentation (README.md, site/docs/, the homepage in site/src/) must describe the
    repository as it is after your change: update what your change makes untrue, in this run.${previous}
    Work in small steps, one requirement at a time, and keep the code building
    between steps. After each step, append a line to ${progress}: what is done
    and what is next. If ${progress} exists, an earlier attempt was cut short:
    check the code against it and continue from there. If ${plan} exists, follow it.
    If the message is ambiguous or conflicts with the code, do not guess: write
    the question to ${stop} and stop.
    Logs of earlier attempts (if any) are in ${DECREE_RUN_DIR}.
    Write scratch files only under ${DECREE_RUN_DIR}, never outside the project (not /tmp)."
    echo "=== AI prompt (implementation) ==="
    echo "${prompt}"
    ai "${prompt}"
    stopped || true
  keep: |
    #!/usr/bin/env bash
    # The repo machines share this step: lib/repo/keep.sh (the repo plugin).
    exec bash "${DECREE_LIB}/repo/keep.sh"
  record: |
    #!/usr/bin/env bash
    # The repo machines share this step: lib/repo/record.sh (the repo plugin).
    exec bash "${DECREE_LIB}/repo/record.sh"
---
# repo_develop

Make the repo match a message with Claude, then run the repo's pre-push gate.

It needs, on the stack that installs it:

- $DECREE_LIB/ai.sh
- $DECREE_LIB/repo/clean_tree.sh
- $DECREE_LIB/repo/commit.sh
- $DECREE_LIB/repo/keep.sh
- $DECREE_LIB/repo/record.sh
