---
sidebar_position: 6
---

# ONLYOFFICE Desktop

- Source: https://github.com/ONLYOFFICE/DesktopEditors
- License: [AGPL-3](https://www.gnu.org/licenses/agpl-3.0.html)
- Alternatives: LibreOffice, Collabora (in-browser), Microsoft Office

**Recommended for documents, spreadsheets, and slides.** A desktop office suite with the
best `.docx` / `.xlsx` / `.pptx` fidelity of the free options — it opens Microsoft formats
without the layout drift you get elsewhere.

:::info[Not a container]
Like [Obsidian](./obsidian), this is a desktop app rather than a service the stack runs.
There is no compose file and no `<slug>.EXIST_DOMAIN` hostname. It edits files in place, in
the directory [Nextcloud](../storage/nextcloud) syncs.
:::

## Why the desktop app rather than a hosted one

The stack already has an in-browser editor: [Collabora](../storage/collabora) is wired into
Nextcloud and handles quick edits from any device. ONLYOFFICE Desktop covers the other case
— long editing sessions, heavy documents, and full Office format fidelity — running locally
against the same synced folder.

ONLYOFFICE's own document server was
[tried and retired](../graveyard/file-editors/only-office) from this stack; Collabora fills
that role now. The desktop editors are a separate product and a separate decision.

## Setup

1. Download from [onlyoffice.com/desktop.aspx](https://www.onlyoffice.com/desktop.aspx), or
   install the Flatpak: `flatpak install flathub org.onlyoffice.desktopeditors`
2. Point it at your synced Nextcloud directory and open files directly
3. No account and no sign-in required for local editing

Because it edits the files in place, the same automations that touch anything else in the
vault or share can read and write these documents too.
