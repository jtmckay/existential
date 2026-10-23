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
    echo "qa: no chaos suite command; set QA_RUN in .decree/lib/qa/qa.sh" >&2
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
