---
sidebar_position: 6
---

# Logseq

- Source: https://github.com/logseq/logseq
- License: [AGPL-3](https://www.gnu.org/licenses/agpl-3.0.html)
- Alternative: Obsidian
- Status: RIP — replaced by [Obsidian](../../services/obsidian)

Outliner-style note-taking over plain markdown files. It was the stack's primary notes app; [Obsidian](../../services/obsidian) now fills that role, reading the same kind of vault.

Logseq was never a container here — only a `config.edn`, now kept at `graveyard/logseq/config.edn`. Your notes are plain markdown and are unaffected by this change.

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
