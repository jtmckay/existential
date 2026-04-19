---
sidebar_position: 6
---

# Logseq

- Source: https://github.com/logseq/logseq
- License: [AGPL-3](https://www.gnu.org/licenses/agpl-3.0.html)
- Alternative: Obsidian

Logseq is the primary note-taking application in the Existential stack. It serves as the knowledge base that feeds into the AI and automation layer.

## Features

- **Outline-First Structure**: Every block is a bullet, making hierarchical and networked thinking natural
- **Bidirectional Linking**: `[[page]]` references with automatic backlinks and a visual knowledge graph
- **Daily Journal**: Built-in daily pages as the default capture point for notes and tasks
- **Queries**: Datalog-based queries to filter and surface blocks and pages across the entire graph
- **Local Markdown Files**: All data stored as plain `.md` files — no proprietary format, fully portable
- **Plugin Ecosystem**: Community plugins for extensions, themes, and integrations

## Mobile Enter Key Fix

There is a difference between typing enter and hitting the carriage return on mobile (causing constant format issues). Updating `config.edn` resolves this:

```clojure
:shortcuts {
  :editor/new-block "enter"
  :editor/new-line "shift+enter"
}
;; Optionally:
:shortcut/doc-mode-enter-for-new-block? true
```
