#!/usr/bin/env bash
# Clean Runs
#
# Keeps only the most recent N run directories per group, where the group is
# derived from the run directory's OWN name — not from a cron listing.
#
# That distinction is the whole point. This used to enumerate CRON_DIR and clean
# only directories matching a cron file basename, which meant it silently ignored
# everything that did not come from *this* daemon's crons: workspace-sync (whose
# cron lives on automation-backup, while both daemons share one runs/ dir) had
# grown to 796 directories, minio-router to 95 because the service was renamed
# out from under it, and s3-router to 36 because a webhook message is named by
# automation-webhook, not by a cron. Deriving the group from the name means a run
# is cleaned because it exists, not because something else still lists it.
#
# Full routine.log and message.md content is shipped to Loki by alloy
# (hosting/loki/loki-alloy-config.alloy) and kept for 30 days, so what is deleted
# here is a local copy, not the history. Grafana's decree dashboards read Loki,
# not this directory.
#
# Example cron trigger (.decree/cron/clean-runs.md):
#
#   ---
#   cron: "0 4 * * *"
#   routine: clean-runs
#   keep: 10
#   ---
set -euo pipefail

if [ "${DECREE_PRE_CHECK:-}" = "true" ]; then
    # shellcheck source=../lib/precheck.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/precheck.sh"
    precheck_pass "clean-runs"
    exit 0
fi

RUNS_DIR="${RUNS_DIR:-/work/.decree/runs}"
KEEP="${keep:-10}"

# Group key, applied in this order because each strip exposes the next:
#   D0007-1759-note-connect-0  -> note-connect      (decree-minted: D<day>-<HHmm>-)
#   s3-router-225034u1-0       -> s3-router         (webhook-minted: -<HHMMSS>[u<n>])
#   D0006-0553-26-ha-hermes-0  -> 26-ha-hermes      (migration)
# The trailing -<seq> goes first: a chained follow-up (…-1) belongs to the same
# group as the message that spawned it, which is what makes "keep 10" mean ten
# runs rather than ten directories.
#
# Sorted by mtime, never by name: the webhook stamp is HHMMSS with no date, so
# sorting those by name interleaves days and would delete the wrong ones.
#
# Dot-entries are skipped and must stay that way — .workspace-bisync holds
# bisync's prior-run listings and .alert-state the dead-letter alert markers.
# Neither is a run, and deleting either breaks the thing that owns it.
mapfile -t doomed < <(
    find "$RUNS_DIR" -mindepth 1 -maxdepth 1 -type d -not -name '.*' -printf '%T@\t%f\n' 2>/dev/null \
    | awk -F'\t' '{
        g = $2
        sub(/^D[0-9]+-[0-9]+-/, "", g)
        sub(/-[0-9]+$/, "", g)
        sub(/-[0-9][0-9][0-9][0-9][0-9][0-9](u[0-9]+)?$/, "", g)
        print g "\t" $1 "\t" $2
      }' \
    | sort -t"$(printf '\t')" -k1,1 -k2,2nr \
    | awk -F'\t' -v keep="$KEEP" '
        $1 != group { group = $1; n = 0 }
        { n++ }
        n > keep { print $1 "\t" $3 }
      '
)

if [ ${#doomed[@]} -eq 0 ]; then
    echo "Nothing to clean (keeping ${KEEP} per group)."
    exit 0
fi

declare -A removed=()
for entry in "${doomed[@]}"; do
    group="${entry%%$'\t'*}"
    name="${entry#*$'\t'}"
    # Belt and braces: never let a derived name escape RUNS_DIR.
    case "$name" in
        */*|.|..|'') echo "  skipping suspicious entry: ${name}" >&2; continue ;;
    esac
    rm -rf "${RUNS_DIR:?}/${name}"
    removed["$group"]=$(( ${removed["$group"]:-0} + 1 ))
done

total=0
for group in $(printf '%s\n' "${!removed[@]}" | sort); do
    echo "  ${group}: removed ${removed[$group]}, kept ${KEEP}"
    total=$(( total + removed[$group] ))
done

echo "Cleaned ${total} run(s)."
