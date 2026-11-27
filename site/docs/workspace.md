---
sidebar_position: 3
---

# Your Workspace

Everything you and the stack write is one folder, `workspace/` (`volumes/workspace_data` on the
computer), of plain files you can read without Existential.

| Folder | What's in it |
|---|---|
| `notes/` | Your notes, plain markdown. Automations can read them and never change them. |
| `ai/` | What the stack writes for you: the morning digest, look backs, research, offers waiting in `ai/proposed/`. |
| `.decree/` | Your routines, and the ones you turned on. |
| `.capture/` | What you typed to an agent, with [Capture](./flows/one-place.md#everything-you-typed-to-an-ai) on. |

## Where you open it

- **In a browser:** [code-server](./services/code-server.md), Core's editor, with `claude`,
  `opencode` and `pi` in its terminal. Claude there already knows how to write a routine.
- **On your other computers and phone:** sync it, through [Nextcloud](./storage/nextcloud.md) in
  the stack or [one you already have](./flows/one-place.md#the-workspace-on-your-other-devices).
- **In Obsidian:** keep the vault in `notes/` and open the synced folder:
  [Obsidian](./services/obsidian.md).

## What the stack does with it

- **Search** reads all of it within a minute of a change, for you and every agent
  ([qmd](./ai/qmd.md)). Anything `.gitignore`'d and hidden folders are left out.
- **Every change is seen.** A routine can start when a file lands or a note settles, but only
  one you turned on or wrote ([File Handlers](./plugins/file-handlers.md)).
- **Nothing leaves** unless a routine you turned on sends it.
