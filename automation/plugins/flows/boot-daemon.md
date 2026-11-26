---
name: boot-daemon
x-exist-title: Boot daemon
x-exist-tagline: Your .decree/boot.sh, run once when the host daemon starts, to start what you run on the host in tmux sessions
x-exist-docs: /docs/hosting/host-daemon#boot-daemon
x-exist-project: host
needs:
  - boot_daemon
  - decree_prune   # the host's runs, pruned like every project's (clean-runs is not the host's)
---
It runs when the host daemon starts, from the unit https://existential.company/docs/hosting/host-daemon
gives. Put what to start in .decree/boot.sh; tmx is there, so one line per process:

  tmx -d comfyui 'cd ~/ComfyUI && exec .venv/bin/python main.py --listen 0.0.0.0'
