#!/usr/bin/env bash
# results.sh — turn an e2e run's evidence into a directory you can read.
# Sourced by e2e.sh and by harness-selftest.sh; running it directly does
# nothing. Everything here is functions — keep it that way.
#
# The problem it solves: the e2e clone is deleted on the way out, so for a long
# time the only way to see WHY something failed was to print it first (the flow
# test's _diagnose dump) or to skip teardown entirely (E2E_KEEP=1). Every run's
# evidence already exists in a good shape — decree writes
# runs/<id>/{message.md,events.jsonl,<NNNN>-<state>-<script>.log} per run — it
# was just being thrown away. This copies it out before teardown and writes an
# index.
#
# Verdict rule: decree mirrors each run's state into its message.md, so
#     state: done            → PASS
#     anything else, or none → FAIL
# A message naming an unknown machine is a `failed` run too (invalid_message),
# so there is no dead-letter case left to look for, and one failure never hides
# the others: the daemon reports a failed inbox run and carries on. Checks are
# messages rather than migrations because a failed migration blocks every
# migration after it, and because a check is dropped once the stack is up.
#
# Every run in the clone is graded, not just the checks e2e staged: a check
# can only prove it ENQUEUED work (decree runs one message at a time and the
# check is that message), so the run that work produces is where its success or
# failure actually shows up. The daemon's own crons fire too; under e2e the stack
# lives for a single run, so none of them has any business failing either, and a
# red row from one is a finding rather than noise.
#
# `e2e_check:` therefore only supplies a friendly name. It is used in preference
# to decree's message id because ids come from a chain counter and the clock —
# an id scheme this has no business depending on.

# Read one frontmatter value out of a message.md. Frontmatter only — a check's
# prose body is free-form and must never be parsed as data (same rule quest_fm
# applies in e2e.sh).
e2e_fm_get() {
    local file="$1" key="$2"
    [ -f "$file" ] || return 0
    # Trailing whitespace is trimmed as well as leading: a caller comparing
    # against a literal (`[ "$(e2e_fm_get "$f" e2e)" = true ]`) would otherwise
    # match NEITHER branch on `e2e:  true   `, and a quest would vanish from the
    # run list and the excluded list at once, with no warning.
    awk -v k="^${2}:" 'NR==1 && /^---$/{f=1;next} f && /^---$/{exit} f && $0 ~ k' "$file" \
        | head -1 | sed "s/^${key}:[[:space:]]*//; s/[[:space:]]*\$//"
}

# collect_results <out_dir> <runs_dir>...
#
# Copies every run dir into <out_dir> and writes <out_dir>/results.md. Returns 0
# when every run ended in `done`, 1 otherwise — including when there were no
# runs at all, because an e2e run that produced no evidence has not
# demonstrated anything and must not read as a pass.
#
# One runs/ per daemon: each decree project keeps its own.
collect_results() {
    local out="$1"; shift
    mkdir -p "$out"

    local -a rows=()
    local failed=0 total=0

    local runs d name state verdict dur
    for runs in "$@"; do
        for d in "$runs"/*/; do
            # message.md is what makes a directory a decree run — anything else
            # under runs/ is not a result and must not be graded as one.
            [ -f "${d}message.md" ] || continue
            # EVERY run counts, not only the checks e2e staged itself. The work a
            # check triggers — a router matching, a processor running — lands here
            # as its own run, and grading only the named checks let a live run
            # report PASS while the router was failing on every event it routed.
            #
            # e2e_check just supplies a friendly name; anything else is named by
            # the machine it ran, which is what makes the failure legible.
            name="$(e2e_fm_get "${d}message.md" e2e_check)"
            [ -n "$name" ] || name="$(e2e_fm_get "${d}message.md" machine)"
            [ -n "$name" ] || name="$(basename "$d")"

            cp -r "$d" "$out/" 2>/dev/null || true
            total=$(( total + 1 ))

            # decree mirrors the run's state into message.md; only a final
            # `done` is a pass. A run still active, waiting, or `failed` is not.
            # grep rather than jq for the duration: jq is not guaranteed on the
            # host, and this runs host-side.
            state="$(e2e_fm_get "${d}message.md" state)"
            dur="$(grep '"type":"run_finished"' "${d}events.jsonl" 2>/dev/null \
                   | grep -o '"duration_ms":[0-9]*' | grep -o '[0-9]*$' | tail -1)"

            if [ "$state" = "done" ]; then
                verdict="PASS"
            else
                verdict="FAIL"
                failed=$(( failed + 1 ))
            fi
            rows+=("${verdict}|${name}|${state:-—}|${dur:+$(( dur / 1000 ))}|$(basename "$d")")
        done
    done

    {
        printf '# e2e results\n\n'
        printf '%s — %s of %s runs passed.\n\n' \
            "$(date -u '+%Y-%m-%d %H:%M UTC')" "$(( total - failed ))" "$total"
        if [ "$total" -eq 0 ]; then
            printf 'No checks produced a result. The stack came up but nothing was\n'
            printf 'verified — treat this as a failure of the harness, not a pass.\n'
        else
            printf '| | Check | state | secs | Run |\n|---|---|---|---|---|\n'
            printf '%s\n' "${rows[@]}" | sort | while IFS='|' read -r v n c s r; do
                printf '| %s | %s | %s | %s | `%s` |\n' \
                    "$([ "$v" = PASS ] && echo '✓' || echo '✗')" "$n" "$c" "${s:-—}" "$r"
            done
            printf '\nEach run keeps its events.jsonl and script logs in `%s/<run>/`.\n' \
                "$(basename "$out")"
        fi
    } > "$out/results.md"

    [ "$total" -gt 0 ] && [ "$failed" -eq 0 ]
}
