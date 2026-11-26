---
name: check_versions
x-exist-topic: host
x-exist-project: host
machine:
  description: Compare every pinned image tag and base image against upstream, and notify once when any has an update.
  initial: check
  states:
    check:
      invoke:
        script: {name: check_versions, timeout: 30m}
      transitions: {done: done}
    done: {final: true}
    failed: {final: true}
scripts:
  check_versions.sh: |
    #!/usr/bin/env bash
    # check_versions — run the repo's one version checker
    # (./existential.sh run check-versions, src/lib/check-versions.sh: its table
    # is every pin there is) and send one ntfy notification listing each pin
    # that is behind or no longer pullable. Silent when all are current.
    #
    # The pins are the checkout's templates, so this runs in the host project
    # (the repo's own .decree), in the repo. On the host, so bash 3.2 on a Mac.
    set -euo pipefail
    repo="$(pwd)"
    # shellcheck source=/dev/null
    . "${repo}/src/utils/adhoc.sh"
    adhoc_detect_runtime
    out="$(cd "$repo" && ./existential.sh run check-versions </dev/null 2>&1)" || { printf '%s\n' "$out" >&2; exit 1; }
    printf '%s\n' "$out"
    # A row is name, current, latest, status, two or more spaces apart.
    behind="$(printf '%s\n' "$out" | awk -F'  +' '
        $4 ~ /^→/ { printf "  • %s: %s → %s\n", $1, $2, $3 }
        $4 ~ /^✗/ { printf "  • %s: %s %s\n", $1, $2, $4 }')"
    [ -n "$behind" ] || exit 0
    body="$(hostname): $(printf '%s\n' "$behind" | wc -l | tr -d ' ') pinned image(s) behind
    ${behind}

    Apply: ./existential.sh run check-versions --update
    Then:  ./existential.sh && docker compose up -d"
    printf '%s\n' "$body" | $DOCKER_CMD exec -i automation decree emit --machine notify --param ntfy_topic=host \
        --param ntfy_title="Image updates available" --param ntfy_tags=arrow_up >/dev/null
cron:
  check-versions.md: |
    ---
    cron: "0 12 * * FRI"
    machine: check_versions
    ---

    Fridays at 12:00, every pinned image against upstream. One ntfy notification
    lists each that is behind; silent when all are current.
---
# check_versions

Compare every pinned image tag and base image against upstream, and notify once when any has
an update. The checker is the repo's own, `./existential.sh run check-versions`, so it runs in
the host's decree project, the repo's own `.decree`. `./existential.sh plugin on check_versions` turns it on.
