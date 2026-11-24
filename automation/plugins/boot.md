---
name: boot
x-exist-project: host
machine:
  description: Run .decree/boot.sh, once each time the host daemon starts.
  initial: run
  states:
    run:
      # A boot.sh that does not return (a process started without tmx -d)
      # would hold the host queue; this ends it as failed instead.
      invoke:
        script: {name: boot, timeout: 5m}
      transitions: {done: done}
    done: {final: true}
    failed: {final: true}
scripts:
  boot.sh: |
    #!/usr/bin/env bash
    # boot — run .decree/boot.sh, yours, once each time the host daemon starts: its
    # cron file is `@reboot`, which decree fires when `decree daemon` starts.
    # tmx is exported to it, so a line like
    #   tmx -d comfyui 'cd ~/ComfyUI && exec .venv/bin/python main.py'
    # starts a process in its own tmux session unless that session already runs.
    # Runs in the host project (the repo's own .decree), so it runs in the repo. On the
    # host, so bash 3.2 on a Mac.
    set -euo pipefail
    repo="$(pwd)"
    [ -f "${repo}/.decree/boot.sh" ] || { echo "boot: no .decree/boot.sh, nothing to run"; exit 0; }
    # shellcheck source=/dev/null
    . "${repo}/services/automation/decree/tmx.sh"
    export -f tmx
    bash "${repo}/.decree/boot.sh"
cron:
  boot.md: |
    ---
    cron: "@reboot"
    machine: boot
    ---
    Run .decree/boot.sh, once, as the host daemon starts.
---
# boot

Runs `.decree/boot.sh` once each time the host daemon starts, so the daemon is the one thing
started at boot and your script starts the rest.
