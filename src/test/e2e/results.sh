#!/usr/bin/env bash
# results.sh — turn an e2e run's evidence into a directory you can read.
# Sourced by e2e.sh and by harness-selftest.sh; running it directly does
# nothing. Everything here is functions — keep it that way.
#
# The problem it solves: the e2e clone is deleted on the way out, so for a long
# time the only way to see WHY something failed was to print it first (the flow
# test's _diagnose dump) or to skip teardown entirely (E2E_KEEP=1). Every run's
# evidence already exists in a good shape — decree writes
# runs/<message_id>/{message.md,routine.log,run.json} per check — it was just
# being thrown away. This copies it out before teardown and writes an index.
#
# Verdict rule, and the whole reason checks are inbox messages rather than
# migrations: decree writes run.json only when a routine SUCCEEDS, and
# dead-letters the message after max_attempts when it does not. So
#     run.json with exit_code 0  → PASS
#     no run.json, or non-zero   → FAIL
#     message in inbox/dead/     → FAIL
# and one failure never hides the others, because `decree daemon` keeps draining
# the inbox past a dead letter (unlike `decree process`, which stops).
#
# Every run in the clone is graded, not just the messages e2e dropped: a check
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
    awk -v k="^${2}:" 'NR==1 && /^---$/{f=1;next} f && /^---$/{exit} f && $0 ~ k' "$file" \
        | head -1 | sed "s/^${key}:[[:space:]]*//"
}

# exit_code out of a run.json, or empty when there is none. grep rather than jq:
# jq is in the decree and adhoc images but is not guaranteed on the host, and
# this runs host-side.
e2e_exit_code() {
    grep -o '"exit_code"[[:space:]]*:[[:space:]]*-\?[0-9]*' "$1" 2>/dev/null \
        | grep -o -- '-\?[0-9]*$' | head -1
}

# collect_results <runs_dir> <dead_dir> <out_dir>
#
# Copies the run dirs and any dead letters into <out_dir> and writes
# <out_dir>/results.md. Returns 0 when every check passed, 1 otherwise —
# including when there were no checks at all, because an e2e run that produced
# no evidence has not demonstrated anything and must not read as a pass.
collect_results() {
    local runs="$1" dead="$2" out="$3"
    mkdir -p "$out"

    local -a rows=()
    local failed=0 total=0

    local d name code verdict dur
    for d in "$runs"/*/; do
        # message.md is what makes a directory a decree run — anything else under
        # runs/ is not a result and must not be graded as one.
        [ -f "${d}message.md" ] || continue
        # EVERY run counts, not only the messages e2e dropped itself. The work a
        # check triggers — a router matching, a processor running — lands here as
        # its own run, and grading only the named checks let a live run report
        # PASS while minio-router was failing on every event it routed.
        #
        # e2e_check just supplies a friendly name; anything else is named by the
        # routine it ran, which is what makes the failure legible in results.md.
        name="$(e2e_fm_get "${d}message.md" e2e_check)"
        [ -n "$name" ] || name="$(e2e_fm_get "${d}message.md" routine)"
        [ -n "$name" ] || name="$(basename "$d")"

        cp -r "$d" "$out/" 2>/dev/null || true
        total=$(( total + 1 ))

        if [ -f "${d}run.json" ]; then
            code="$(e2e_exit_code "${d}run.json")"
            dur="$(grep -o '"duration_s"[[:space:]]*:[[:space:]]*[0-9.]*' "${d}run.json" 2>/dev/null \
                   | grep -o '[0-9.]*$' | head -1)"
        else
            code=""; dur=""
        fi

        if [ "$code" = "0" ]; then
            verdict="PASS"
        else
            verdict="FAIL"
            failed=$(( failed + 1 ))
        fi
        rows+=("${verdict}|${name}|${code:-—}|${dur:-—}|$(basename "$d")")
    done

    # Dead letters. A check that dead-lettered has a run dir too (decree creates
    # it before the first attempt), so it is already counted above — this is for
    # the case where it never got that far, and to keep the message itself.
    local m dname
    if [ -d "$dead" ]; then
        for m in "$dead"/*.md; do
            [ -f "$m" ] || continue
            mkdir -p "$out/dead"
            cp "$m" "$out/dead/" 2>/dev/null || true
            dname="$(e2e_fm_get "$m" e2e_check)"
            [ -n "$dname" ] || dname="$(e2e_fm_get "$m" routine)"
            [ -n "$dname" ] || dname="$(basename "$m" .md)"
            printf '%s\n' "${rows[@]+"${rows[@]}"}" | grep -q "|${dname}|" && continue
            rows+=("FAIL|${dname}|dead-lettered|—|—")
            total=$(( total + 1 )); failed=$(( failed + 1 ))
        done
    fi

    {
        printf '# e2e results\n\n'
        printf '%s — %s of %s checks passed.\n\n' \
            "$(date -u '+%Y-%m-%d %H:%M UTC')" "$(( total - failed ))" "$total"
        if [ "$total" -eq 0 ]; then
            printf 'No checks produced a result. The stack came up but nothing was\n'
            printf 'verified — treat this as a failure of the harness, not a pass.\n'
        else
            printf '| | Check | exit | secs | Run |\n|---|---|---|---|---|\n'
            printf '%s\n' "${rows[@]}" | sort | while IFS='|' read -r v n c s r; do
                printf '| %s | %s | %s | %s | `%s` |\n' \
                    "$([ "$v" = PASS ] && echo '✓' || echo '✗')" "$n" "$c" "$s" "$r"
            done
            printf '\nA failing check keeps its full output in `%s/<run>/routine.log`.\n' \
                "$(basename "$out")"
        fi
    } > "$out/results.md"

    [ "$total" -gt 0 ] && [ "$failed" -eq 0 ]
}
