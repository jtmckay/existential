---
sidebar_position: 4
---

# Ideas That Get Followed Up

Three projects started on a clear night, and a folder of them since. These take the note you
meant to come back to and do the part that doesn't need you, so what comes back is a decision,
not a chore.

## The note you meant to come back to

Each new note is asked one question: is there something worth doing here? Most notes are left
alone. For the ones that pass, the work that needs no input from you gets done (who else does
this, what they charge, a draft plan) and you get back the two or three questions only you can
answer.

```bash
./existential.sh plugin on note_triage
```

- **Which notes**: everything in `workspace/notes/`. What comes back is in
  `workspace/ai/note-develop/`, under the note's own path.
- **What counts** is one sentence, `TRIAGE_CRITERIA` in
  `workspace/.decree/machines/note_triage/cron/note-triage.md`. It starts as *a business idea*;
  make it whatever you want followed up. Keep it strict: a triage that passes everything leaves
  you a folder of unread reports.
- **Try it first** with `TRIAGE_DRY_RUN: true` in the same file for a few days: it says what it
  would pick, and does nothing.
- **What you already have** is marked as seen on the first run, so a big vault doesn't fire a
  call per note. To judge the backlog once:
  `echo | decree emit --machine note_triage --param TRIAGE_BOOTSTRAP=true`.

How the machines behind it fit, and how to swap any of them:
[Worked example: Note → Action](../plugins/note-to-action.md).

## Hand a file to an agent

A file matching what you describe is handed to an agent, and its answer lands in
`workspace/ai/`. It rides on [files from your phone](./one-place.md#files-from-your-phone).

```bash
./existential.sh plugin on agent_handoff
```

What it picks is `CRITERIA` in `file-processors/agent-handoff.sh`, inside
`automation/plugins/agent_handoff.md`. It is code, so it is changed in the repo, and
`./existential.sh` installs it: nothing in the workspace can change it.
