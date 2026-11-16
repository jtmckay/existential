---
machine: plugin
automation: repo_qa
project: host
needs:
  - agent
  - repo
  - repo_develop
chart:
  description: Attack the project to make it misbehave, and hand each real bug to develop as a failing test; Claude writes tests only and never fixes code.
  onentry: [clean_tree] # the run starts from a clean git work tree
  initial: recon
  states:
    recon: # lists the attack surface in surface.md; fails first if lib/qa/qa.sh has no QA_RUN
      invoke: recon
      transitions: {done: attack}
    attack: # writes chaos tests in QA_DIR, each naming its wrench and invariant
      invoke: attack
      transitions: {done: run}
    run: # runs the chaos suite into chaos.log; a failing test is a finding, not an error
      invoke: run
      transitions: {done: triage}
    triage: # one bug report per root cause, its tests marked expected to fail; writes STOP instead of guessing
      invoke: triage
      transitions: {done: report, stop: failed}
    report: # one develop message per bug report
      invoke: report
      transitions: {done: done}
      emits: [repo_develop]
    done: {final: true, onentry: [commit]} # one commit per run; a migration's processed.md line too
    failed: {final: true, onentry: [keep]} # the run's changes stay in the tree; its attention file holds the queue
scripts:
  attack: |
    #!/usr/bin/env bash
    # qa's attack: Claude writes chaos tests in QA_DIR, each naming its wrench and invariant.
    set -euo pipefail
    . "${DECREE_LIB}/ai.sh"
    . "${DECREE_LIB}/qa/qa.sh"
    qa_ready
    qa_guard

    prompt="You are QA. Your job is to make this project misbehave. You are done when you have
    written tests that fail, or have tried every wrench in ${DECREE_LIB}/qa/wrenches.md.
    Read ${DECREE_RUN_DIR}/surface.md, ${DECREE_LIB}/qa/invariants.md and the tests already in
    ${QA_DIR}/ (do not repeat a wrench and invariant pair tested there). Write new tests in
    ${QA_DIR}/, in the project's language and test framework, run by: ${QA_RUN}
    Each test names its wrench and the invariant it checks. Seed every random choice with a
    constant. A test asserts the invariant, never what the code happens to do now.
    Change only files in ${QA_DIR}/: you find bugs, you never fix them. Do not run the tests.
    Write scratch files only under ${DECREE_RUN_DIR}, never outside the project (not /tmp)."
    echo "=== AI prompt (attack) ==="
    echo "${prompt}"
    ai "${prompt}"
    qa_check
  clean_tree: |
    #!/usr/bin/env bash
    # The repo machines share this step: lib/repo/clean_tree.sh (the repo plugin).
    exec bash "${DECREE_LIB}/repo/clean_tree.sh"
  commit: |
    #!/usr/bin/env bash
    # The repo machines share this step: lib/repo/commit.sh (the repo plugin).
    exec bash "${DECREE_LIB}/repo/commit.sh"
  keep: |
    #!/usr/bin/env bash
    # The repo machines share this step: lib/repo/keep.sh (the repo plugin).
    exec bash "${DECREE_LIB}/repo/keep.sh"
  recon: |
    #!/usr/bin/env bash
    # qa's recon: Claude lists the attack surface, from the docs and the code, in surface.md.
    set -euo pipefail
    . "${DECREE_LIB}/ai.sh"
    . "${DECREE_LIB}/qa/qa.sh"
    qa_ready
    qa_guard

    prompt="You are QA. Read the project's docs and code, ${DECREE_LIB}/qa/invariants.md and
    ${DECREE_LIB}/qa/wrenches.md. Write ${DECREE_RUN_DIR}/surface.md: a short list of the
    attack surface (each input, each piece of saved state, each call to the outside world,
    each limit), and for each, the invariants it could break. Change no other file.
    Write scratch files only under ${DECREE_RUN_DIR}, never outside the project (not /tmp)."
    echo "=== AI prompt (recon) ==="
    echo "${prompt}"
    ai "${prompt}"
    qa_check
  report: |
    #!/usr/bin/env bash
    # qa's report: one develop message per bug report in bugs/. Safe to re-run: a report
    # already queued is listed in emitted.txt.
    set -euo pipefail
    emitted="${DECREE_RUN_DIR}/emitted.txt"
    touch "${emitted}"
    shopt -s nullglob
    for bug in "${DECREE_RUN_DIR}"/bugs/*.md; do
      grep -qxF "${bug}" "${emitted}" && continue
      id=$("${DECREE}" emit --machine repo_develop < "${bug}")
      echo "${bug}" >> "${emitted}"
      echo "queued ${id}: $(head -n 1 "${bug}")"
    done
  run: |
    #!/usr/bin/env bash
    # qa's run: the chaos suite, into chaos.log. A failing test is a finding, so this exits 0
    # either way; only a suite that could not start at all (command not found) is an error.
    set -uo pipefail
    . "${DECREE_LIB}/qa/qa.sh"
    bash -c "${QA_RUN}" 2>&1 | tee "${DECREE_RUN_DIR}/chaos.log"
    status=${PIPESTATUS[0]}
    if [ "${status}" -ge 126 ]; then
      echo "qa: the chaos suite could not run (exit ${status}): ${QA_RUN}" >&2
      exit 1
    fi
    exit 0
  triage: |
    #!/usr/bin/env bash
    # qa's triage: Claude sorts each failure into a real bug, a wrong test or acceptable
    # behaviour. A bug's tests are marked expected to fail and get one report per root cause in
    # bugs/; wrong tests are rewritten; acceptable ones are removed. The chaos suite must then
    # pass, or the step fails. A failure the docs do not settle is a question in STOP; the run
    # fails until a person answers it in plan.md, deletes STOP and runs `decree process --retry`.
    set -euo pipefail
    . "${DECREE_LIB}/ai.sh"
    . "${DECREE_LIB}/qa/qa.sh"

    bugs="${DECREE_RUN_DIR}/bugs"
    plan="${DECREE_RUN_DIR}/plan.md"
    stop="${DECREE_RUN_DIR}/STOP"
    stopped() {
      [ -f "${stop}" ] || return 1
      cat "${stop}" >&2
      echo stop > "${DECREE_EVENT_FILE}"
    }
    stopped && exit 0
    mkdir -p "${bugs}"
    qa_guard

    prompt="You are QA triage. Read ${DECREE_RUN_DIR}/chaos.log, the project's docs,
    ${DECREE_LIB}/qa/invariants.md, and ${plan} if it exists. For each failing test in
    ${QA_DIR}/, decide:
    - Real bug: the project breaks an invariant or its docs. Mark the test expected to fail,
      with the framework's strict marker, so the suite passes now and fails once the bug is
      fixed (Python @unittest.expectedFailure or pytest xfail(strict=True), Playwright
      test.fail(), Jest test.failing, Rust #[should_panic]).
    - Wrong test: it asserts something the docs do not require, or no correct code could pass
      it. Rewrite it to check the invariant, or delete it.
    - Acceptable behaviour: delete the test.
    - Unclear: the docs and invariants do not say. Write the question to ${stop} and stop.
    Then group the real bugs by root cause: tests that fail for the same reason are one bug.
    For each root cause write ${bugs}/<short-slug>.md for the developer: a title line naming
    the broken behaviour; '## Overview': the invariant broken, every test it covers (file and
    name), the wrench, and what happened (the error from chaos.log); '## Outcome': the expected
    behaviour, as the invariant and the docs state it; '## Constraints': the tests' assertions
    do not change; '## Acceptance Criteria': Given those tests, When the chaos suite runs
    (${QA_RUN}), Then they pass with their expected-failure marker removed and their
    assertions unchanged. State what is broken and what is expected, never a fix: name no
    code, file or function to change and no way to change it.
    Write one line per test to ${DECREE_RUN_DIR}/triage.md: test, verdict, root cause, why.
    Change only files in ${QA_DIR}/ and ${DECREE_RUN_DIR}/. Do not run the tests.
    Write scratch files only under ${DECREE_RUN_DIR}, never outside the project (not /tmp)."
    echo "=== AI prompt (triage) ==="
    echo "${prompt}"
    ai "${prompt}"
    stopped && exit 0
    qa_check
    if ! bash -c "${QA_RUN}" > "${DECREE_RUN_DIR}/chaos-after.log" 2>&1; then
      tail -n 20 "${DECREE_RUN_DIR}/chaos-after.log" >&2
      echo "qa: the chaos suite still fails; every failure must be marked, rewritten or removed" >&2
      exit 1
    fi
lib:
  qa/qa.sh: |
    # shellcheck shell=bash
    # qa's settings and its guard, which qa's scripts source.
    #
    # Where the chaos tests live, apart from the project's other tests.
    QA_DIR=tests/chaos
    # The command that runs the chaos suite and exits non-zero if a test fails. qa does not
    # start until it is set. Once qa has found bugs, run it in develop's gate too, so a
    # fixed bug whose test is still marked expected to fail is caught.
    QA_RUN=""
    # QA_RUN="python3 -m unittest discover -s ${QA_DIR} -t . -v"
    # QA_RUN="npx playwright test ${QA_DIR}"
    # QA_RUN="cargo test --test chaos"
    # QA_RUN="go test ./${QA_DIR}/..."

    # Fail unless QA_RUN is set and this is a git work tree (the guard needs git).
    qa_ready() {
      if [ -z "${QA_RUN}" ]; then
        echo "qa: no chaos suite command; set QA_RUN in the lib: qa/qa.sh of automation/plugins/repo_qa.md" >&2
        return 1
      fi
      git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
        echo "qa: not a git work tree; qa's guard needs git" >&2
        return 1
      }
    }

    # QA never fixes code. qa_guard hashes every file outside QA_DIR and .decree/ before the
    # AI runs; qa_check fails the step, naming each file the AI changed. It restores nothing,
    # so it never overwrites work of yours.
    qa_hashes() {
      git ls-files -z -c -o --exclude-standard -- . ":(exclude)${QA_DIR}" ":(exclude).decree" |
        xargs -0 -r sha1sum 2>/dev/null | sort
    }
    qa_guard() { qa_hashes > "${DECREE_RUN_DIR}/guard.txt"; }
    qa_check() {
      local changed
      changed=$(qa_hashes | { diff "${DECREE_RUN_DIR}/guard.txt" - || true; } |
        sed -n 's/^[<>] [0-9a-f]*  //p' | sort -u)
      if [ -n "${changed}" ]; then
        echo "qa: the AI changed files outside ${QA_DIR}; QA writes tests only:" >&2
        echo "${changed}" >&2
        return 1
      fi
    }
  qa/invariants.md: |
    # Invariants

    What must always hold, whatever a user or the world does. qa's tests assert these, never
    what the code happens to do now. Number them, so a test and a bug report can name one.
    Until this lists any, qa takes them from the project's docs and code.

    <!-- For example:
    - I1: Saved data is never lost: after a crash or restart, the user is where they were.
    - I2: Every error the user can cause shows a message and leaves the app usable.
    - I3: Nothing the user does twice in a row has a different effect than doing it once.
    -->
  qa/wrenches.md: |
    # Wrenches

    Ways to make the project misbehave. qa's tests each name one. Add the project's own.

    - W1 Input boundaries: empty, one, huge, negative, zero, non-ASCII, wrong type, malformed.
    - W2 Repetition: the same action twice, fast; double submit; repeat until a limit.
    - W3 Ordering: steps out of order, back and forward, an action before setup is done.
    - W4 Interruption: a crash or kill mid-write, then a restart.
    - W5 Resources: disk or quota full, no network, a slow or failing service, a timeout.
    - W6 Corrupt state: saved data truncated, garbled, from an older version, or missing.
    - W7 Concurrency: two users or processes acting on the same thing at once.
    - W8 Time: clock changes, time zones and daylight saving, dates far in the past or future.
---
# repo_qa

Attack the project to make it misbehave, and hand each real bug to develop as a failing test; Claude writes tests only and never fixes code.
