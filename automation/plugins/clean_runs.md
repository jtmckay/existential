---
machine: plugin
automation: clean_runs
chart:
  description: Delete this project's finished runs older than OLDER_THAN; Loki keeps the history.
  data:
    OLDER_THAN: {type: string, default: 7d}
  initial: prune
  states:
    prune:
      invoke: clean_runs
      transitions: {done: done}
    done: {final: true}
    failed: {final: true}
scripts:
  clean_runs: |
    #!/usr/bin/env bash
    # clean_runs — delete this project's finished runs older than OLDER_THAN.
    #
    # runs/ is a working copy: alloy ships every run's events.jsonl and script logs
    # to Loki (hosting/loki/loki-alloy-config.alloy), which is the history Grafana's
    # decree dashboards read. decree prune never touches an unfinished run, a failed
    # migration, or a child whose parent still runs.
    set -euo pipefail

    decree prune --no-color --older-than "$DECREE_DATA_OLDER_THAN"
---
# clean_runs

Delete this project's finished runs older than OLDER_THAN; Loki keeps the history.
