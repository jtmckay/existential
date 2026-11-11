---
machine: plugin
automation: update
chart:
  description: Follow this checkout's upstream - pull it fast-forward only, then run ./existential.sh, which installs every plugin you have on at its new version, then docker compose up -d.
  initial: update
  states:
    update:
      invoke:
        script: {name: update, timeout: 30m}
      transitions: {done: done}
    done: {final: true}
    failed: {final: true}
scripts:
  update: |
    #!/usr/bin/env bash
    # The repo is the authority: what lands on its branch is what this install
    # runs. A pull that cannot fast-forward (a local commit, a rewritten
    # upstream) changes nothing, and you are told. Runs in the host project
    # (host/.decree), so the repo is one up.
    set -euo pipefail
    repo="$(cd .. && git rev-parse --show-toplevel)"
    cd "$repo"
    # shellcheck source=/dev/null
    . src/utils/adhoc.sh
    adhoc_detect_runtime
    tell() {  # <title> <body>: to your phone, through the stack's own notify
        printf '%s\n' "$2" | $DOCKER_CMD exec -i automation decree emit --machine notify \
            --param ntfy_title="$1" --param ntfy_tags=arrows_counterclockwise >/dev/null 2>&1 || true
    }
    before="$(git rev-parse HEAD)"
    git fetch --quiet
    if ! out="$(git merge --ff-only '@{u}' 2>&1)"; then
        tell "Update stopped" "$(hostname): $(printf '%s\n' "$out" | tail -3)"
        echo "update: ${out}" >&2; exit 1
    fi
    if [[ "$(git rev-parse HEAD)" == "$before" ]]; then echo "update: up to date"; exit 0; fi
    ./existential.sh </dev/null
    $DOCKER_CMD compose up -d
    tell "Updated" "$(hostname) is at $(git log -1 --format='%h %s')."
    echo "update: $(git log --oneline "${before}..HEAD" | wc -l) commits, now $(git log -1 --format=%h)"
cron:
  update: |
    ---
    machine: update
    cron: "*/15 * * * *"
    ---
---
# update

Keeps this install on its branch: every 15 minutes it pulls, fast-forward only, runs
`./existential.sh` (which installs the new version of every plugin you have on) and
`docker compose up -d`. Your phone hears when it updated, and when a pull could not
fast-forward, which changes nothing.

It runs in the host's own decree project, `host/.decree`, so a decree daemon has to be
running there, started at boot: `./existential.sh` says so while it is not. The `auto-update` flow turns it on:
`./existential.sh flow on auto-update`.
