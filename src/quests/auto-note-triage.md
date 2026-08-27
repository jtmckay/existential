---
name: Note Triage
tagline: Watch your notes for ideas worth acting on, then research and draft them
e2e: false
services:
  - var: EXIST_IS_SERVICES_DECREE
    label: Decree
  - var: EXIST_IS_AI_HERMES
    label: Hermes
  - var: EXIST_IS_NAS_NEXTCLOUD
    label: Nextcloud
copies:
  - src: services/decree/decree/cron.example/note-triage.md
    dst: services/decree/decree/cron/
    label: "decree: note-triage.md (hourly scan of the notes vault)"
    requires: EXIST_IS_SERVICES_DECREE
---

Most notes get written once and never read again. This watches the vault for
new or changed notes, asks the model whether each one is worth acting on, and
chains real work for the few that are — ending with the questions only you can
answer.

Two routines:
  note-triage   scans /data/notes, judges each new or changed note, and
                chains note-develop for the ones that pass
  note-develop  takes one flagged note, optionally researches it, and writes
                a draft plan plus open questions

Pipeline each run:
  1. Hash every .md under /data/notes and diff against the last run
  2. For each new or changed note, one cheap YES/NO call to the gateway
  3. YES  → outbox message → note-develop
  4. note-develop writes <note>.plan.md and notifies you via ntfy

IMPORTANT — the first run is a no-op by design. It records the vault as seen
without triaging, so turning this on with a 5,000-note vault does not fire
5,000 model calls. To scan the backlog once:

  docker exec decree decree run --routine note-triage --param TRIAGE_BOOTSTRAP=true

Prerequisites:
  - Notes landing in /data/notes — activate the auto-notes quest, or point
    NOTES_DIR at wherever your vault already is
  - Hermes running (the gateway the routines call), or set
    TRIAGE_API_URL=http://ollama:11434/v1 in the cron frontmatter to talk to
    Ollama directly
  - Enable both routines in services/decree/decree/config.yml:
      note-triage:
        enabled: true
      note-develop:
        enabled: true

Making it yours — everything below is cron frontmatter, no code changes:

  TRIAGE_CRITERIA   what counts as worth acting on. This IS the feature.
                    Ships looking for a business idea; point it at research
                    questions, writing prompts, house projects, whatever you
                    actually want chased down.
  TRIAGE_DRY_RUN    true = log what it would flag, chain nothing. Run it this
                    way for a few days first — a triage step that fires on
                    everything just makes a folder of unread reports.
  TRIAGE_ROUTINE    what to chain when a note passes (default: note-develop).
                    Swap in your own routine and the triage half still works.
  TRIAGE_MAX_NOTES  ceiling per run (default 20), so a big import cannot
                    run away with your GPU
  TRIAGE_MODEL      leave empty to use the gateway default
  NOTE_OUTPUT_RCLONE_DEST
                    where the draft is copied so it lands beside the original
                    note, e.g. nextcloud:Notes. Without it the draft stays in
                    /data/note-triage/output — do NOT point it at /data/notes,
                    that path is an rclone sync cache and gets wiped.
  FIRECRAWL_URL     set to http://firecrawl:3002 to research before drafting.
                    Without it, note-develop says where it would have looked
                    instead of inventing a market.

After activating the cron, restart decree:
  docker compose restart decree

Logs for each run land in automations/runs/ and are queryable in Grafana
via the Decree Overview dashboard.
