# Logseq
- Source: https://github.com/logseq/logseq
- License: [AGPL-3](https://www.gnu.org/licenses/agpl-3.0.html)

Show stopper that was resolved: there's a difference between typing enter, and hitting the carriage return on mobile (AKA constant format issues). Updating the config.edn resolved this issue.

`config.edn`
```
:shortcuts {
  :editor/new-block "enter"
  :editor/new-line "shift+enter"
}
;; Optionally, set this too:
:shortcut/doc-mode-enter-for-new-block? true
```
