---
sidebar_position: 6
---

# Logseq

- Source: https://github.com/logseq/logseq
- License: [AGPL-3](https://www.gnu.org/licenses/agpl-3.0.html)
- Alternative: Obsidian

Logseq is the primary note-taking application in the Existential stack. It serves as the knowledge base that feeds into the AI and automation layer.

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
