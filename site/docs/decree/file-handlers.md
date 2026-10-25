---
sidebar_position: 3
---

# File Handlers

Drop a PDF in a folder, or finish a note, and an automation runs on it. The `automation`
container watches the whole workspace (`volumes/workspace_data`), so every change counts,
whoever made it: code-server, Obsidian through a sync, a script, the host. Created,
modified, moved and deleted are all seen.

What runs is up to `workspace/.decree/handlers.yml`. Each handler names a glob, the machine
to run, and optionally which changes it cares about and how long the file must be quiet:

```yaml
- match: notes/to-process/*.md   # relative to the workspace
  machine: note_process
- match: "**/*.pdf"              # quote a pattern that starts with *
  machine: file_pdf
  changes: [created, modified]   # default: created, modified and deleted
  quiet: 10                      # default: 30 seconds
```

Two ship with the stack, in the `handlers.yml` seeded on first install (yours to edit after):
`notes/**/*.md` runs `note_watch`, which offers to automate a standing instruction in a note
([Note → Automation](../flows/note-to-automation)), and `notes/automations/*.md` runs
`reconcile`, which has `develop` build the ones you accept.

- **A change matching no handler does nothing.** A change matching several runs each of them.
- **A handler fires once the file has been quiet** for `quiet` seconds: an editor's autosaves
  while you type reset the clock, so it runs once, after you stop. A delete fires at once.
- **The run gets two params**, `path` (relative to the workspace, `notes/to-process/plan.md`)
  and `change` (`created`, `modified` or `deleted`). The machine declares both:

  ```yaml
  data:
    path: { type: string, default: "" }
    change: { type: string, default: "" }
  ```

  and its script reads the file at `/workspace/$DECREE_DATA_PATH`. A moved file is a delete of
  the old path and a create of the new one; a folder moved in is a create for each file in it.
- **Edits to `handlers.yml` apply on the next change**, no restart. A handler that names a
  machine which does not exist, or one that does not declare `path` and `change`, is logged
  (`docker logs automation`) and skipped.

## What never fires

Anything inside a `.git/` folder, and every path a `.gitignore` in the workspace ignores,
whatever a handler matches. It is the same rule the [Nextcloud sync](../getting-started#syncing-with-a-nextcloud-optional)
uses, and it is why decree's own run state (`.decree/runs/`, `inbox/`) never triggers anything.

Beyond that, the stack filters nothing: keeping a file from triggering is the handlers' job.
Keep a draft out of `to-process/` until it is ready, or add the folder to a `.gitignore`. An
automation whose output lands on a path its own handler matches runs again on that output, so
write output where the pattern does not reach (`workspace/ai/`, for instance, under a handler
for `notes/**`).

## Asking Claude for one

Say "when a PDF lands in `inbox/`, file it by vendor" in code-server's terminal and Claude
writes the machine and the handler. The decree skill in the workspace carries this page's
rules, and it suggests a folder or pattern that keeps the handler off files you are not ready
for.

## Nextcloud's file events

With Nextcloud in the stack, every upload through it, anywhere in Nextcloud and not only the
workspace, can also post a file event to automation-webhook. That older path keeps working;
see [File Processor](./file-change-processing). For files in the workspace, a handler is all
you need, and Nextcloud is optional sync.
