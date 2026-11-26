---
sidebar_position: 13
---

# The Host Daemon

Most of the stack runs in containers. Five flows run on the host itself, in the host's decree
project, the checkout's own `.decree`: [`worker`](./controller-and-workers.md), which reports the host,
[`pull-existential`](./updates.md), which keeps the install current, [`boot-daemon`](#boot-daemon),
which runs your own script when the daemon starts, [`check-versions`](./updates.md#pinned-images),
which says when a pinned image is behind, and [`update-ubuntu`](./updates.md#ubuntu),
which keeps an Ubuntu host patched. They run only while a decree
daemon runs there, and nothing starts one for you. `./existential.sh` says so until one does.

## Turn a flow on

Each one is off until you turn it on, from the checkout:

```bash
./existential.sh flow on pull-existential     # or report-host, boot-daemon, check-versions, update-ubuntu
```

That puts it in `automation/plugins.yml` and installs it into the checkout's `.decree`. It works on
a host with neither docker nor podman, with the host's own tools; anything missing is named,
all of it at once, with how to install it. Then start the daemon, below.
`./existential.sh flow list` shows which flows are on; `./existential.sh run plugin list`
shows every plugin, with the project that runs it.

## What it needs

You need [decree](https://github.com/jtmckay/decree) on the host (the version
`services/automation/decree/Dockerfile` pins), and `tmux`:

```bash
curl -fsSL https://raw.githubusercontent.com/jtmckay/decree/main/install.sh | sh -s -- v0.6.1
```

`./existential.sh` prints this line with the version it pins. It installs to `~/.local/bin`. If `decree --version` isn't found, that folder isn't on your
`PATH`: `echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc`, then open a new shell.

## Start it

From the checkout:

```bash
tmux new -d -s existential-host -c "$PWD" decree daemon
```

That lasts until the next reboot. To start it at boot, on Linux with systemd, a user unit,
`~/.config/systemd/user/existential-host.service` (change the path to your checkout):

```ini
[Unit]
Description=existential host decree daemon

[Service]
# oneshot and KillMode=process: the tmux server outlives this unit, so stopping it
# ends the daemon's session and no other.
Type=oneshot
RemainAfterExit=yes
KillMode=process
WorkingDirectory=%h/existential
# Where decree, git and docker are: systemd does not read your shell's PATH.
Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/usr/bin/tmux new -d -s existential-host "exec decree daemon"
ExecStop=/usr/bin/tmux kill-session -t existential-host

[Install]
WantedBy=default.target
```

```bash
systemctl --user enable --now existential-host
sudo loginctl enable-linger "$USER"     # start without a login
```

On a Mac, a LaunchAgent that runs the same `tmux new` line at login does the same.
`tmux attach -t existential-host` shows it working.

An install from before the host's project was the checkout's `.decree` ran this daemon in
`host/`. `./existential.sh` moves what was there, stops that daemon and says so: start it
again as above, and change `WorkingDirectory` in the unit to the checkout.

## When decree's version changes

A pull that pins a new decree leaves the host's `.decree` as it is, so the daemon you have
keeps running what it runs (`pull-existential` included), and `./existential.sh` prints the steps
until you take them: install that version as above, run `./existential.sh`, then restart the
daemon:

```bash
tmux kill-session -t existential-host; tmux new -d -s existential-host -c "$PWD" decree daemon
```

## Check it's working

```bash
tmux has-session -t =existential-host && echo running
tail -3 .decree/process.log
```

Each run ends in a line like `✓ <run> done in 0s`. A flow's own output is in
`.decree/runs/<run>/`. `./existential.sh` also warns while no daemon runs.

## Boot daemon

With the unit above, the daemon is the one thing started at boot, and it can start the rest.
`./existential.sh flow on boot-daemon`, then write `.decree/boot.sh`. It runs once each time the
daemon starts (a cron file of the `boot_daemon` machine's, `cron: "@reboot"`), with [`tmx`](https://github.com/jtmckay/existential/blob/main/services/automation/decree/tmx.sh)
in reach, so each process gets its own tmux session and is left alone if it already runs:

```bash
tmx -d comfyui 'cd ~/ComfyUI && exec .venv/bin/python main.py --listen 0.0.0.0'
```

Its output is in `.decree/runs/`; `tmux attach -t comfyui` shows the process itself. A unit
from before decree 0.6 emitted `boot` itself before `decree daemon`: drop that, or `boot.sh` runs
twice at each start (which `tmx -d` makes harmless).
