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

`auto-update` is a host flow: it runs in [the host daemon](./host-daemon.md), so start that
once, and have it start at boot. `./existential.sh` says so until one runs.

## Turning it off

```bash
./existential.sh flow off auto-update
```

Then you pull and run `./existential.sh` yourself, as before.
