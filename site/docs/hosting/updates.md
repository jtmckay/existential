---
sidebar_position: 14
---

# Updates

An install can follow its branch on its own. The `auto-update` [flow](../flows/index.md), off until you
turn it on, runs on the host every 15 minutes:

1. `git pull`, fast-forward only. A checkout with commits of its own, or an upstream that was
   rewritten, is left exactly as it is, and your phone says why.
2. `./existential.sh`, which installs the new version of every plugin you have on.
3. `docker compose up -d`.

Your phone hears each update, with the commit it landed on. The repo is the authority: what is
on its branch is what your install runs.

```bash
./existential.sh flow on auto-update
```

## A decree daemon on the host

`auto-update` is a host flow, in `host/.decree`, so it runs only while a decree daemon runs there,
and so does [`worker`](./controller-and-workers.md).
`./existential.sh` says so until one does. You need [decree](https://github.com/jtmckay/decree)
on the host (the version `services/automation/decree/Dockerfile` pins), then:

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

## Turning it off

```bash
./existential.sh flow off auto-update
```

Then you pull and run `./existential.sh` yourself, as before.
