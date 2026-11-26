---
name: gpu_release
x-exist-topic: host
x-exist-project: automation
machine:
  description: Answer a GPU lease from outside the stack, release or renew, and only a gpu_lease run.
  data:
    lease: {type: string, default: ""}
    answer: {type: string, default: release, enum: [release, renew]}
  initial: answer
  states:
    answer: {invoke: answer, transitions: {done: done}}
    done: {final: true}
    failed: {final: true}
scripts:
  answer.sh: |
    #!/usr/bin/env bash
    # A POST can answer a lease and nothing else: the run must be one of gpu_lease's.
    set -euo pipefail
    [[ "$("${DECREE:-decree}" status "$DECREE_DATA_LEASE" --format json 2>/dev/null | jq -r '.machine // ""')" == gpu_lease ]] ||
        { echo "gpu_release: ${DECREE_DATA_LEASE} is no GPU lease" >&2; exit 1; }
    "${DECREE:-decree}" reply "$DECREE_DATA_LEASE" "$DECREE_DATA_ANSWER"
x-exist-endpoints:
  - path: /gpu/lease/{lease}/{answer}
    patterns: {lease: "[0-9A-Za-z._-]{1,80}", answer: "release|renew"}
    body: optional
    message:
      machine: gpu_release
      params: {lease: "{{lease}}", answer: "{{answer}}"}
---
# gpu_release

How a client outside the stack gives back its GPU lease (`gpu_lease`), or keeps it longer:
`POST /gpu/lease/<id>/release` or `/renew`. It answers a `gpu_lease` run and nothing else.
