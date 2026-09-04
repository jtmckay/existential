---
cron: "*/15 * * * *"
routine: notes-pull
NOTES_PULL_SOURCE: "user@nas.example:/path/to/obsidian-vault"
---

Pull an external notes vault (e.g. Obsidian, synced to a NAS or another box)
into `workspace/notes/` via `rsync` over SSH, so it becomes part of the
workspace/ knowledgebase.

**This has real knock-on effects — know what you're opting into.** Anything
that lands in `workspace/notes/` is a normal file under `workspace/`, so it
automatically:
  - gets indexed by OpenViking and becomes searchable/citable context for
    every hermes agent (see openviking-index-knowledgebase.md)
  - gets bisynced to the `nextcloud` MinIO bucket by workspace-sync, and from
    there is browsable through Nextcloud's own /S3 folder
  - fires MinIO webhook events once workspace-sync has subscribed the bucket
    (its own first-run behavior — see workspace-sync.sh) — if any file
    processor is active with a broad enough PATTERN, your notes can trigger it

If you don't want your vault driving automation, don't activate any file
processor with a PATTERN that would match `nextcloud:S3/workspace/notes/...`.

Setup:

1. Generate a key pair for this, and add the public half to the source host's
   `~/.ssh/authorized_keys`:
     ssh-keygen -t ed25519 -f automation/secrets/notes-pull/id_ed25519 -N ""
   automation/secrets/ is gitignored and mounted into automation-backup at
   /secrets — nothing here needs to be committed.

2. Set NOTES_PULL_SOURCE above to your real `user@host:/path/` (trailing
   slash matters to rsync the same way it always does — with it, the
   directory's *contents* land in workspace/notes/; without it, the directory
   itself is created one level down).

3. Copy to services/automation/backup/cron/ and restart automation-backup to
   activate.

Safe by default: pulls are one-way and NEVER delete local files that
disappeared on the source (NOTES_PULL_DELETE stays false unless you opt in) —
a source that's temporarily offline or unmounted can only fail to add new
notes, never wipe the ones already here.

Other frontmatter keys, all optional: NOTES_PULL_SUBDIR (default "notes"),
NOTES_PULL_SSH_KEY (default automation/secrets/notes-pull/id_ed25519 inside
the container, i.e. /secrets/notes-pull/id_ed25519), NOTES_PULL_SSH_PORT
(default 22), NOTES_PULL_DELETE (default false), NOTES_PULL_EXTRA_ARGS (raw
extra rsync flags, e.g. "--exclude=.trash/**").

A source with no `host:` prefix — a local path, or a share already mounted
into the container some other way — skips SSH entirely; rsync just copies it.
