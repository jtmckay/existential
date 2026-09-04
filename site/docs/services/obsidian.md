---
sidebar_position: 5
---

# Obsidian

- Source: https://obsidian.md (proprietary)
- License: Proprietary — free without limits for personal *and* commercial use since
  February 2025. Not open source. Sync, Publish and a commercial licence are optional paid
  ways to support the developers.
- Alternatives: Logseq, Notion, Roam Research, Joplin

**Recommended for notes and tasks.** Obsidian is the one deliberate exception to the
open-source rule in this stack. It is still free — free without limits, no sign-up, nothing
to buy — it just isn't *open source*. That distinction is the whole of the exception: your
notes are plain `.md` files in a directory you already own and sync, so the editor is
replaceable. Nothing you write is locked inside it.

:::info[Not a container]
Obsidian is a desktop and mobile app, not a service the stack runs. There is no compose file
and no `<slug>.EXIST_DOMAIN` hostname. It reads a vault directory that Nextcloud syncs, which
is what connects it to everything else here.
:::

## Why it's the recommendation

The vault is a folder of markdown. That means every automation in this stack can read and
write your notes with no API, no export step, and no vendor in the middle — the same way
[LightRAG indexed a vault](../flows/) and the same way any routine you write can drop a file
into it.

It also replaces a second app: with the Kanban plugin below, tasks live in the vault too,
so there's no separate task service, database, or backup sidecar to maintain.

## Kanban

Task boards live in the vault as markdown, via the community **Kanban** plugin.

1. Settings → Community plugins → Browse → **Kanban** → Install → Enable
2. Create a note, then right-click it → **New Kanban board** (or use the command palette)
3. Cards are list items; columns are markdown headings

Because the board is a `.md` file, the same automations that touch notes can add cards.
Appending a checklist line to the file adds a card to that column.

This replaces [Vikunja](../graveyard/tasks/vikunja), which was retired from the stack — it
was a second app, database, and backup sidecar for something the vault now does.

## Plugins in use

Core:

- Unique note creator

Community:

- Excalidraw — drawing and diagramming
- Kanban — task boards (see above)

## Sync to your phone

Obsidian's own paid sync is not required — Nextcloud handles it.

1. Install the Obsidian app
2. Install the Nextcloud app
3. Install FolderSync (if Obsidian can't reach Nextcloud files directly)
4. Set up two-way sync between the Nextcloud vault directory and the directory Obsidian can
   access

This is about reading and editing your vault from other devices. To make it part of what the
AI agent actually knows — searchable, citable — pull it into `workspace/notes/` instead; see
[Workspace](../getting-started#workspace).

See [Nextcloud](../storage/nextcloud) for the server side.
