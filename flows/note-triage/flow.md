---
name: The note you meant to come back to
tagline: Each new note is asked one question, worth doing?, and the few that are get drafted
docs: /docs/flows/note-to-action
services:
  - EXIST_IS_SERVICES_AUTOMATION
  - EXIST_IS_NAS_NEXTCLOUD
---

The first run records your notes as seen without judging them, so a big vault costs
nothing. TRIAGE_CRITERIA in volumes/workspace_data/.decree/cron/note-triage.md is the
whole judgment: point it at what you actually want chased down, and run with
TRIAGE_DRY_RUN: true for a few days first. To judge the backlog once:
  echo | docker exec -i automation decree emit --machine note_triage --param TRIAGE_BOOTSTRAP=true
