---
sidebar_position: 13
---

# The Host Daemon

Most of the stack runs in containers. Two flows run on the host itself, in its own decree project,
`host/.decree`: [`worker`](./controller-and-workers.md), which reports the host, and
[`auto-update`](./updates.md), which keeps the install current. They run only while a decree
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
Type=forking
WorkingDirectory=%h/existential/host
# Where decree, git and docker are: systemd does not read your shell's PATH.
Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/usr/bin/tmux new -d -s existential-host decree daemon
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
