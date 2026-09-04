---
name: Note Triage
tagline: Watch your notes for ideas worth acting on, then research and draft them
e2e: false
services:
  - var: EXIST_IS_SERVICES_AUTOMATION
    label: Decree
  - var: EXIST_IS_AI_HERMES
    label: Hermes
  - var: EXIST_IS_NAS_NEXTCLOUD
    label: Nextcloud
---

Most notes get written once and never read again. This watches the vault for
new or changed notes, asks the model whether each one is worth acting on, and
chains real work for the few that are — ending with the questions only you can
answer.

Three routines — one that judges, and two ways to do the work:
  note-triage   scans /data/notes, judges each new or changed note, checks it
                against the ideas already evaluated, and chains TRIAGE_ROUTINE
                for the ones that are both good and new
  note-develop  (default) takes one flagged note, optionally researches it, and
                writes a draft plan plus open questions
  idea-workup   (alternative) hands the idea to three hermes departments —
                competition and market size to research, value proposition to
                sales — and each answers in its own file

Pipeline each run:
  1. Hash every .md under /data/notes and diff against the last run
  2. For each new or changed note, one cheap YES/NO call to the gateway
  3. YES  → one more cheap call: is this materially new, or an idea already on
     the ledger at /data/note-triage/ideas.tsv? A duplicate stops here
  4. New  → outbox message → TRIAGE_ROUTINE
  5. note-develop writes <note>.plan.md and notifies you via ntfy — or
     idea-workup writes three files into workspace/ai/ and notifies you per file

IMPORTANT — the first run is a no-op by design. It records the vault as seen
without triaging, so turning this on with a 5,000-note vault does not fire
5,000 model calls. To scan the backlog once:

  printf -- '---\nroutine: note-triage\nTRIAGE_BOOTSTRAP: true\n---\n' > automation/inbox/bootstrap.md

Prerequisites:
  - Notes landing in /data/notes — activate the auto-notes quest, or point
    NOTES_DIR at wherever your vault already is
  - Hermes running (the gateway the routines call), or set
    TRIAGE_API_URL=http://ollama:11434/v1 in the cron frontmatter to talk to
    Ollama directly
  - Enable the routines you want in services/automation/decree/config.yml:
      note-triage:
        enabled: true
      note-develop:
        enabled: true

    For the idea-workup path, run the Hermes Departments quest instead of (or
    beside) note-develop — it enables idea-workup with the research and sales
    departments and provisions the profiles they call.

Making it yours — everything below is cron frontmatter, no code changes:

  TRIAGE_CRITERIA   what counts as worth acting on. This IS the feature.
                    Ships looking for a business idea; point it at research
                    questions, writing prompts, house projects, whatever you
                    actually want chased down.
  TRIAGE_DRY_RUN    true = log what it would flag, chain nothing. Run it this
                    way for a few days first — a triage step that fires on
                    everything just makes a folder of unread reports.
  TRIAGE_ROUTINE    what to chain when a note passes (default: note-develop).
                    Set it to idea-workup for the three-department fan-out, or
                    to your own routine — the triage half never changes.
  TRIAGE_LEDGER     true by default. The "is this idea new?" check. Set false
                    to chain every pass, duplicates included.
  TRIAGE_LEDGER_MAX how many previously evaluated ideas that check sees
                    (default 100, most recent first).
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

Activate the hourly scan:
  mkdir -p automation/cron/
  cp automation-examples/cron/note-triage.md automation/cron/
  docker compose restart automation

Logs for each run land in automation/runs/ and are queryable in Grafana
via the Decree Overview dashboard.
