---
sidebar_position: 14
---

# Updates

An install can follow its branch on its own. The `auto-update` [flow](../flows/index.md), off until you
turn it on, runs on the host every 15 minutes:

1. `git pull`, fast-forward only. A checkout with commits of its own, or an upstream that was
   rewritten, is left exactly as it is, and your phone says why.
2. `./existential.sh`, which installs the new version of every plugin you have on, and moves
   your rendered compose files to every image the pull changed (in a terminal it asks first).
3. `docker compose up -d`, then `docker image prune -a`: every image no container uses, old
   versions included, is deleted.

Your phone hears each update, with the commit it landed on. The repo is the authority: what is
on its branch is what your install runs.

```bash
./existential.sh flow on auto-update
```

`auto-update` is a host flow: it runs in [the host daemon](./host-daemon.md), so start that
once, and have it start at boot. `./existential.sh` says so until one runs.

## Turning it off

```bash
./existential.sh flow off auto-update
```

Then you pull and run `./existential.sh` yourself, as before.

## Pinned images {#pinned-images}

Every image the stack runs is pinned to a tag in the repo, so nothing moves until the pin does.
The `check-versions` flow says when one is behind: Fridays at noon it runs
`./existential.sh run check-versions`, which compares every pinned tag and base image against
upstream, and sends one notification listing each that has a newer version. Nothing is changed,
and a week with nothing behind is silent.

```bash
./existential.sh flow on check-versions
```

It is a host flow too. When a notification arrives:

```bash
./existential.sh run check-versions --update     # moves the pins in the templates
./existential.sh && docker compose up -d         # offers them to your rendered files, pulls, restarts
docker image prune -a                            # deletes the old versions, which keep their tags
```

For another day or time, edit `cron:` in `host/.decree/cron/check-versions.md`.

## Ubuntu {#ubuntu}

`auto-update` keeps the stack current. The `update-ubuntu` flow does the same for an Ubuntu
host under it, also from [the host daemon](./host-daemon.md):

| | When |
|---|---|
| Check for updates | Daily, by Ubuntu's own `unattended-upgrades` |
| Security updates | Daily, by `unattended-upgrades` |
| Every other package update | Sundays at 01:00, by the flow (`apt-get upgrade`: nothing is removed) |
| Reboot | At 02:00, only when an installed update requires one |
| Ubuntu release upgrades | Never. `do-release-upgrade` is yours to schedule |

```bash
./existential.sh flow on update-ubuntu
./existential.sh
sudo bash host/.decree/lib/ubuntu_upgrade/setup.sh
```

The last line is the one step that needs root, once. It turns `unattended-upgrades` on, and
lets the host daemon run one root-owned script, `/usr/local/sbin/existential-ubuntu-upgrade`,
without a password, and nothing else. Until it has run, the weekly run fails and says so.

Your phone hears when the weekly run failed, and when a reboot is coming. The failed run is in
`host/.decree/runs/`; fix what apt complained about, then `decree process --retry` in `host/`.

Reboots are `unattended-upgrades`' own setting, in `/etc/apt/apt.conf.d/52existential-updates`,
which is yours once written. On a host whose work can't be interrupted, set
`Unattended-Upgrade::Automatic-Reboot "false";` there: nothing reboots it, and your phone says
when a reboot is due.
