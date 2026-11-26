---
name: notes_pull
x-exist-topic: host
x-exist-project: backup
machine:
  description: Rsync-pull an external notes vault into workspace/notes, one way, without --delete unless asked.
  data:
    # user@host:/path over SSH, or a local path. Required.
    NOTES_PULL_SOURCE: {type: string, default: ""}
    NOTES_PULL_SUBDIR: {type: string, default: notes}
    NOTES_PULL_SSH_KEY: {type: string, default: /secrets/notes-pull/id_ed25519}
    NOTES_PULL_SSH_PORT: {type: int, default: 22}
    # Mirror deletions too — only once you trust the source's uptime.
    NOTES_PULL_DELETE: {type: bool, default: false}
    NOTES_PULL_EXTRA_ARGS: {type: string, default: ""}
  initial: pull
  states:
    pull:
      invoke: notes_pull
      transitions: {done: done}
    done: {final: true}
    failed: {final: true}
scripts:
  notes_pull.sh: |
    #!/usr/bin/env bash
    # Notes Pull
    #
    # Opt-in: rsync-pulls notes (e.g. an Obsidian vault) from an external host
    # into workspace/notes/ (or wherever NOTES_PULL_SUBDIR points), so a vault
    # that lives somewhere else becomes part of the workspace/ knowledgebase —
    # searchable with qmd and synced to Nextcloud clients like anything else
    # under workspace/. It is written straight to disk, so it fires no Nextcloud file
    # events; a file handler whose pattern matches it does run.
    #
    # Why rsync over SSH and not another rclone remote: the source is assumed to
    # be a plain filesystem reachable over SSH (a NAS, a synced folder on another
    # box) rather than an S3-shaped store — rsync is the standard tool for that,
    # and needs no bucket/credential setup on the source side.
    #
    # One-way, and deliberately not --delete by default: this PULLS A COPY in, it
    # does not mirror. A source that goes offline, gets unmounted, or is
    # temporarily empty should never be able to wipe local notes as a side
    # effect — opt into NOTES_PULL_DELETE=true only once you trust the source's
    # uptime as much as you trust decree's cron.
    #
    # SSH key: put a private key at automation/secrets/notes-pull/id_ed25519 (any
    # name — set NOTES_PULL_SSH_KEY to match) and its public half in the source
    # host's authorized_keys. automation/secrets/ is gitignored and mounted into
    # this daemon at /secrets, the same place rclone's config lives.
    #
    # A source without a "host:" prefix (a local path, or a share already mounted
    # into this container) skips SSH entirely — rsync copies it directly.
    #
    # Turn it on, then in services/automation-backup/machines/notes_pull/cron/notes-pull.md set
    # NOTES_PULL_SOURCE (and NOTES_PULL_SSH_KEY, if the key isn't at the default
    # path). The NOTES_PULL_* knobs are the machine's data.
    set -euo pipefail

    WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
    NOTES_PULL_SOURCE="$DECREE_DATA_NOTES_PULL_SOURCE"
    NOTES_PULL_SUBDIR="$DECREE_DATA_NOTES_PULL_SUBDIR"
    NOTES_PULL_SSH_KEY="$DECREE_DATA_NOTES_PULL_SSH_KEY"
    NOTES_PULL_SSH_PORT="$DECREE_DATA_NOTES_PULL_SSH_PORT"
    NOTES_PULL_DELETE="$DECREE_DATA_NOTES_PULL_DELETE"
    NOTES_PULL_EXTRA_ARGS="$DECREE_DATA_NOTES_PULL_EXTRA_ARGS"

    _is_remote_source() {
        # user@host:/path or host:/path — a bare local path never has a ':'
        # before its first '/', and rsync's own "host:" detection works the
        # same way (a Windows-style "C:/" drive letter is not a use case here).
        [[ "${NOTES_PULL_SOURCE}" == *:* && "${NOTES_PULL_SOURCE}" != /* ]]
    }

    [[ -n "${NOTES_PULL_SOURCE}" ]] || { echo "NOTES_PULL_SOURCE not set — see cron/notes-pull.md" >&2; exit 1; }
    if _is_remote_source; then
        [[ -f "${NOTES_PULL_SSH_KEY}" ]] || { echo "${NOTES_PULL_SSH_KEY} not found — see cron/notes-pull.md" >&2; exit 1; }
    fi

    _target="${WORKSPACE_DIR}/${NOTES_PULL_SUBDIR}"
    mkdir -p "${_target}"

    _args=(-a --human-readable --stats)
    [[ "${NOTES_PULL_DELETE}" == "true" ]] && _args+=(--delete)

    if _is_remote_source; then
        _args+=(-e "ssh -i ${NOTES_PULL_SSH_KEY} -p ${NOTES_PULL_SSH_PORT} -o StrictHostKeyChecking=accept-new -o BatchMode=yes")
    fi

    if [[ -n "${NOTES_PULL_EXTRA_ARGS}" ]]; then
        # shellcheck disable=SC2206
        _extra=(${NOTES_PULL_EXTRA_ARGS})
        _args+=("${_extra[@]}")
    fi

    echo "Pulling ${NOTES_PULL_SOURCE} -> ${_target} (delete=${NOTES_PULL_DELETE})"
    rsync "${_args[@]}" "${NOTES_PULL_SOURCE%/}/" "${_target%/}/"
    echo "Pull complete."
cron:
  notes-pull.md: |
    ---
    cron: "*/15 * * * *"
    machine: notes_pull
    params:
      NOTES_PULL_SOURCE: "user@nas.example:/path/to/obsidian-vault"
    ---

    Pull an external notes vault (e.g. Obsidian, synced to a NAS or another box)
    into `workspace/notes/` via `rsync` over SSH, so it becomes part of the
    workspace/ knowledgebase.

    **This has real knock-on effects — know what you're opting into.** Anything
    that lands in `workspace/notes/` is a normal file under `workspace/`, so it
    automatically:
      - gets indexed by qmd and becomes searchable context for
        every agent
      - shows up in Nextcloud's `workspace` folder, and so on every desktop client
        syncing it

    It is written straight to disk, so it fires no Nextcloud file events: a pulled
    vault never triggers a file processor on its own. Edit one of those notes through
    Nextcloud, though, and that upload does. A file handler whose pattern matches
    `notes/` sees the pull like any other change.

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


    Safe by default: pulls are one-way and NEVER delete local files that
    disappeared on the source (NOTES_PULL_DELETE stays false unless you opt in) —
    a source that's temporarily offline or unmounted can only fail to add new
    notes, never wipe the ones already here.

    Other frontmatter keys, all optional: NOTES_PULL_SUBDIR (default "notes"),
    NOTES_PULL_SSH_KEY (default automation/secrets/notes-pull/id_ed25519 inside
    the container, i.e. /secrets/notes-pull/id_ed25519), NOTES_PULL_SSH_PORT
    (default 22), NOTES_PULL_DELETE (default false), NOTES_PULL_EXTRA_ARGS (raw
    extra rsync flags, e.g. "--exclude=.trash/**").

    A vault on your NAS needs no SSH: give `EXIST_NFS_SHARE_NOTES` in .env.shared its
    folder on the export and set NOTES_PULL_SOURCE to "/notes-nas/" (mounted read-only).

    A source with no `host:` prefix — a local path, or a share already mounted
    into the container some other way — skips SSH entirely; rsync just copies it.
---
# notes_pull

Rsync-pull an external notes vault into workspace/notes, one way, without --delete unless asked.
