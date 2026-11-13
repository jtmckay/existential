---
sidebar_position: 13
---

# The Host Daemon

Most of the stack runs in containers. Three flows run on the host itself, in its own decree project,
`host/.decree`: [`worker`](./controller-and-workers.md), which reports the host,
[`auto-update`](./updates.md), which keeps the install current, and [`on-boot`](#on-boot),
which runs your own script when the daemon starts. They run only while a decree
daemon runs there, and nothing starts one for you. `./existential.sh` says so until one does.

You need [decree](https://github.com/jtmckay/decree) on the host (the version
`services/automation/decree/Dockerfile` pins), and `tmux`:

```bash
curl -fsSL https://raw.githubusercontent.com/jtmckay/decree/main/install.sh | sh
```

It installs to `~/.local/bin`. If `decree --version` isn't found, that folder isn't on your
`PATH`: `echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc`, then open a new shell.

## Start it

From the checkout:

```bash
tmux new -d -s existential-host -c "$PWD/host" decree daemon
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
WorkingDirectory=%h/existential/host
# Where decree, git and docker are: systemd does not read your shell's PATH.
Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin
# The emit runs host/boot.sh once (the on-boot flow); without that flow it does nothing.
ExecStart=/usr/bin/tmux new -d -s existential-host "echo | decree emit --machine boot >/dev/null 2>&1; exec decree daemon"
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

## Check it's working

```bash
tmux has-session -t =existential-host && echo running
tail -3 host/.decree/process.log
```

Each run ends in a line like `✓ <run> done in 0s`. A flow's own output is in
`host/.decree/runs/<run>/`. `./existential.sh` also warns while no daemon runs.

## On boot

With the unit above, the daemon is the one thing started at boot, and it can start the rest.
`./existential.sh flow on on-boot`, then write `host/boot.sh`. It runs once each time the
daemon starts, with [`tmx`](https://github.com/jtmckay/existential/blob/main/services/automation/decree/tmx.sh)
in reach, so each process gets its own tmux session and is left alone if it already runs:

```bash
tmx -d comfyui 'cd ~/ComfyUI && exec .venv/bin/python main.py --listen 0.0.0.0'
```

Its output is in `host/.decree/runs/`; `tmux attach -t comfyui` shows the process itself.
