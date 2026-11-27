---
sidebar_position: 13
---

# The Host Daemon

Most of the stack runs in containers. Six plugins run on the host itself, in the host's decree
project, the checkout's own `.decree`: [`report_host`](./controller-and-workers.md), which reports the host,
[`pull_existential`](./updates.md), which keeps the install current, [`boot_daemon`](#boot-daemon),
which runs your own script when the daemon starts, [`check_versions`](./updates.md#pinned-images),
which says when a pinned image is behind, [`update_ubuntu`](./updates.md#ubuntu),
which keeps an Ubuntu host patched, and [`lease_gpu`](./ai-box.md), which shares a GPU box's card. They run only while a decree
daemon runs there: `./existential.sh` offers to start one, now and at every boot.

## Turn one on

Each one is off until you turn it on, from the checkout:

```bash
./existential.sh plugin on pull_existential     # or report_host, boot_daemon, check_versions, update_ubuntu, lease_gpu
```

That puts it in the host project's list, `.decree/plugins/.on`, and installs it into the
checkout's `.decree`. It works on a host with neither docker nor podman, with the host's own
tools; anything missing is offered for install, all of it at once. Then start the daemon,
below. `./existential.sh plugin` shows every plugin, which are on, and the project that
runs each.

## Start it

From the checkout:

```bash
./existential.sh run host-daemon install
```

It needs decree (the version the stack pins) and `tmux` on the host; `./existential.sh` offers to
install both. Then it:

1. writes a systemd user unit, `~/.config/systemd/user/existential-host.service`, for this
   checkout, with the `PATH` decree, git and docker are on (systemd does not read your shell's);
2. enables and starts it (`systemctl --user enable --now existential-host`);
3. turns linger on (`loginctl enable-linger`), so it starts at boot before anyone logs in. Where
   that takes root, it asks before it runs `sudo loginctl enable-linger $USER`.

On a Mac it writes a LaunchAgent instead (`~/Library/LaunchAgents/company.existential.host.plist`),
which starts it when you log in. Anywhere else it starts the daemon now and prints the line to
start it at boot yourself.

The daemon itself is a tmux session, `existential-host`: `tmux attach -t existential-host` shows
it working, and what starts it at boot leaves one that already runs alone. Running `install`
again changes nothing; run it after moving the checkout, since the unit names its folder.

```bash
./existential.sh run host-daemon status      # running? starts at boot? linger? the last report
./existential.sh run host-daemon uninstall   # stop starting it at boot (the running daemon stays)
```

`./existential.sh` offers the same install, with Enter, on any run where a host plugin is on and
no daemon runs, and warns when one runs but nothing would start it after a reboot.

## When decree's version changes

A pull that pins a new decree leaves the host's `.decree` as it is, so the daemon you have
keeps running what it runs (`pull_existential` included), and `./existential.sh` prints the steps
until you take them: install that version (the run offers it), run `./existential.sh`, then
restart the daemon:

```bash
systemctl --user restart existential-host     # or, without the unit: tmux kill-session -t existential-host, then install
```

## Check it's working

```bash
./existential.sh run host-daemon status
```

Each run ends in a line like `✓ <run> done in 0s`. A plugin's own output is in
`.decree/runs/<run>/`. `./existential.sh` also warns while no daemon runs.

## Boot daemon

With the daemon installed, it is the one thing started at boot, and it can start the rest.
`./existential.sh plugin on boot_daemon`, then write `.decree/boot.sh`. It runs once each time the
daemon starts (a cron file of the `boot_daemon` machine's, `cron: "@reboot"`), with [`tmx`](https://github.com/jtmckay/existential/blob/main/services/automation/decree/tmx.sh)
in reach, so each process gets its own tmux session and is left alone if it already runs:

```bash
tmx -d comfyui 'cd ~/ComfyUI && exec .venv/bin/python main.py --listen 0.0.0.0'
```

Its output is in `.decree/runs/`; `tmux attach -t comfyui` shows the process itself. A unit
from before decree 0.6 emitted `boot` itself before `decree daemon`: drop that, or `boot.sh` runs
twice at each start (which `tmx -d` makes harmless).
