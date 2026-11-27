---
sidebar_position: 8
---

# It Looks After Itself

A system you have to maintain is one more thing to forget. This one says when something needs
you, and otherwise stays quiet.

## When something breaks, your phone says so

**On by default.** A routine that fails, or needs an answer from you, sends one notification:
what happened, and the command that continues it. Every 15 minutes the stack also checks that
notifications themselves still get through.

All of it goes to [ntfy](../services/ntfy.md): install its phone app and subscribe to the topics
on that page. More: [When a run needs you](../decree/decree.md#when-a-run-needs-you).
The 15-minute check is `./existential.sh plugin off service_health` if you'd rather not.

## Every service checked

Each service you have on carries its own check. This runs them all on a schedule and tells your
phone when one breaks, and again when it recovers. Nothing to configure: what is on is what is
checked.

```bash
./existential.sh service on automation-backup
./existential.sh plugin on triage
```

To check by hand: `./existential.sh test services`.

## Backups

Every service's files and databases, nightly and weekly, to a place you choose: another disk,
a NAS, or cloud storage.

```bash
./existential.sh service on automation-backup
./existential.sh plugin on volume_backup db_backup sqlite_backup
./existential.sh run rclone           # where the backups go
```

Restore with `./existential.sh run backup-restore`. Core ships no backups: until you turn these
on, or put `volumes/workspace_data` under git with a remote of your own, your workspace is on one
disk. More: [Automation Backup](../decree/automation-backup.md).

## Staying up to date

All three run on the host itself, in [the host daemon](../hosting/host-daemon.md), which has to
be started once.

- **Follow the release**: every 15 minutes, pull what's new and restart what changed.
  `./existential.sh plugin on pull_existential` ([Updates](../hosting/updates.md)).
- **Know when an app is behind**: Fridays at noon, one notification listing every app with a
  newer version upstream. `./existential.sh plugin on check_versions`
  ([Pinned images](../hosting/updates.md#pinned-images)).
- **Keep an Ubuntu host patched**: security updates daily, the rest weekly, and a reboot at 02:00
  only when one is required. `./existential.sh plugin on update_ubuntu`
  ([Ubuntu](../hosting/updates.md#ubuntu)).

Without them, upgrading is `git pull && ./existential.sh && docker compose up -d`.
