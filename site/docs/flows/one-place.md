---
sidebar_position: 3
---

# Everything in One Place

Notes in an Obsidian vault, a notes app, voice memos, texts to yourself, forty tabs. These put
what you capture where everything else can find it: plain files in `workspace/`, which search
indexes within a minute and every agent can read.

## Everything you typed to an AI

Every question you ask an agent lands in one place, searchable a year from now.
`workspace/.capture/` keeps what you typed, never the answers, with API keys and passwords
replaced by a marker before anything is written. The morning digest uses it for
*where you left off*.

```bash
./existential.sh plugin on capture
```

- Claude Code and opencode in code-server are captured as soon as it is on (`CODE_SERVER_CAPTURE=false`
  in `services/code-server/.env` leaves them out).
- Claude Code on another computer, with the workspace synced there:
  `bash <workspace>/.decree/lib/capture/capture.sh install <workspace dir>` (`uninstall` removes
  only that hook).
- Anything that can send a web request, like a phone shortcut, can add a line through
  [automation-webhook](../decree/automation-webhook.md):

  ```bash
  curl -X POST https://automation-webhook.<domain>/capture \
    -H "Authorization: Bearer $AUTOMATION_WEBHOOK_SECRET" \
    --data-binary '{"source":"phone","text":"buy filters"}'
  ```

## A newsletter from only the feeds you picked

Every Monday: at most seven items from the blogs, channels and forums you listed, each with one
line on why it matters to you, picked by a paragraph you wrote. A link is never sent twice, and a
quiet week is one line saying so.

```bash
./existential.sh plugin on newsletter
```

Then list your feeds, one RSS or Atom URL per line, in
`workspace/.decree/store/newsletter/feeds.txt`, and say what you care about and what to skip in
`taste.md` beside it. Both are read fresh each week. Issues land in `workspace/newsletter/`.

## Your notes vault

- **Simplest:** keep the vault inside `workspace/`, and open it in [Obsidian](../services/obsidian.md)
  through a sync.
- **Kept somewhere else:** `./existential.sh plugin on notes_pull` pulls it in every 15 minutes
  over SSH. It runs in [automation-backup](../decree/automation-backup.md): set `NOTES_PULL_SOURCE`
  (`user@nas:/path/to/vault/`) in `services/automation-backup/machines/notes_pull/cron/notes-pull.md`
  and put an SSH key at `automation/secrets/notes-pull/id_ed25519`. Until then each run fails and
  says so.

## The workspace on your other devices

`workspace/` kept the same as one other copy, every minute, both ways. A file changed on both
sides keeps the newer edit, and a sync that would delete more than half of one side stops and
asks you first.

```bash
./existential.sh service on automation-backup
./existential.sh plugin on workspace_sync
```

The other copy is a NAS folder (`EXIST_NFS_SHARE_WORKSPACE` in `.env.shared`) or a Nextcloud
folder (`EXIST_NEXTCLOUD_DOMAIN`, `_USER` and `_APP_PASSWORD` in `.env`). With
[Nextcloud](../storage/nextcloud.md) in this stack you don't need it: its `workspace` folder is
the same tree, and its desktop and phone apps sync it.

## Files from your phone

Upload a file through Nextcloud, from its phone app's auto-upload or anywhere else, and every
routine whose pattern matches it runs: the text of a photo, the transcript of a recording
([Voice and Photos](./voice-and-photos.md)), or your own.

```bash
./existential.sh service on nextcloud automation-webhook
./existential.sh plugin on nextcloud_file_events
```

Log in to the Nextcloud app at `https://nextcloud.<domain>` with the admin login in
`nas/nextcloud/.env`. A file saved straight into `workspace/` needs none of this: the stack sees
every change there ([File Handlers](../plugins/file-handlers.md)).

## Email and calendar

- **Gmail:** new mail every 15 minutes, for routines to act on. Grant read-only access once in a
  browser, `./existential.sh run automation gmail-sync`, then `./existential.sh plugin on gmail_sync`.
  More: [Gmail](../integrations/gmail.md).
- **Your calendar, readable by agents:** Nextcloud's calendar, every event mirrored into the
  workspace as a note. `./existential.sh service on nextcloud`, then
  `./existential.sh plugin on calendar_extract`, and set `CALENDAR_EXTRACT_TZ` in
  `machines/calendar_extract/cron/calendar-extract.md` to your time zone.
- **Notes to Dropbox:** every 10 minutes, your Nextcloud notes compiled, indexed and pushed to
  Dropbox. Add the Dropbox remote once (`./existential.sh run rclone`), then
  `./existential.sh plugin on notes`.
