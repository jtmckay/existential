---
name: note-to-automation
x-exist-project: automation
x-exist-title: Notes become automations
x-exist-tagline: Write "next time X, do Y" in a note, accept what is proposed, and it runs
x-exist-docs: /docs/flows/note-to-automation
x-exist-services:
  - EXIST_IS_SERVICES_AUTOMATION
needs:
  - note_watch
  - automation_propose
  - reconcile
  - develop
---

A note with a standing instruction becomes a proposal in ai/proposed/. Move it into
notes/automations/ to accept it; develop builds it, and editing or deleting the file
rebuilds or removes it.
