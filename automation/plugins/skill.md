---
name: skill
extends: decree_skill
x-exist-project: automation
scripts:
  dirs: |
    # The workspace root, where code-server's `claude` starts: not /work, this project's root.
    /workspace/.claude/skills/decree
---
# skill

decree's `decree_skill`, writing the decree skill into the workspace at each daemon start, so
`claude` started in `/workspace` (code-server's terminal) knows how to write a machine. This
project's own notes on it (`automation/lib/skill-notes.md`: a machine made here is offered, not
installed) are the `existential` skill beside it, which the decree image's entrypoint writes.
