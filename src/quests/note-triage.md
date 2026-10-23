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
done:
  files:
    - volumes/workspace_data/.decree/cron/note-triage.md
---

Most notes get written once and never read again. This watches the vault for
new or changed notes, asks the model whether each one is worth acting on, and
chains real work for the few that are — ending with the questions only you can
answer.

Three machines — one that judges, and two ways to do the work:
  note_triage   scans /data/notes, judges each new or changed note, checks it
                against the ideas already evaluated, and chains TRIAGE_ROUTINE
                for the ones that are both good and new
  note_develop  (default) takes one flagged note, optionally researches it, and
                writes a draft plan plus open questions
  idea_workup   (alternative) hands the idea to three hermes departments —
                competition and market size to research, value proposition to
                sales — and each answers in its own file

Pipeline each run:
  1. Hash every .md under /data/notes and diff against the last run
  2. For each new or changed note, one cheap YES/NO call to the gateway
  3. YES  → one more cheap call: is this materially new, or an idea already on
     the ledger at /data/note-triage/ideas.tsv? A duplicate stops here
  4. New  → decree emit → TRIAGE_ROUTINE
  5. note_develop writes <note>.plan.md and notifies you via ntfy — or
     idea_workup writes three files into workspace/ai/ and notifies you per file

IMPORTANT — the first run is a no-op by design. It records the vault as seen
without triaging, so turning this on with a 5,000-note vault does not fire
5,000 model calls. To scan the backlog once:

  echo | docker exec -i automation decree emit --machine note_triage --param TRIAGE_BOOTSTRAP=true

Prerequisites:
  - Notes landing in /data/notes — activate the Notes Sync quest, or point
    NOTES_DIR at wherever your vault already is
  - A model at the chat endpoint (EXIST_MODEL_URL_CHAT, or EXIST_MODEL_URL):
    triage and note_develop call it directly, no hermes needed
  - For the idea_workup path, run the Hermes Departments quest — it
    provisions the research and sales profiles idea_workup calls.

Making it yours — the cron file's params, no code changes:

  TRIAGE_CRITERIA   what counts as worth acting on. This IS the feature.
                    Ships looking for a business idea; point it at research
                    questions, writing prompts, house projects, whatever you
                    actually want chased down.
  TRIAGE_DRY_RUN    true = log what it would flag, chain nothing. Run it this
                    way for a few days first — a triage step that fires on
                    everything just makes a folder of unread reports.
  TRIAGE_ROUTINE    what to chain when a note passes (default: note_develop).
                    Set it to idea_workup for the three-department fan-out.
  TRIAGE_LEDGER     true by default. The "is this idea new?" check. Set false
                    to chain every pass, duplicates included.
  TRIAGE_MAX_NOTES  ceiling per run (default 20), so a big import cannot
                    run away with your GPU

And in automation/.env, for every run (these are environment, not params):

  NOTE_OUTPUT_RCLONE_DEST
                    where the draft is copied so it lands beside the original
                    note, e.g. nextcloud:Notes. Without it the draft stays in
                    /data/note-triage/output — do NOT point it at /data/notes,
                    that path is an rclone sync cache and gets wiped.
  FIRECRAWL_URL     set to http://firecrawl:3002 to research before drafting.
                    Without it, note_develop says where it would have looked
                    instead of inventing a market.

Activate the hourly scan:
  mkdir -p volumes/workspace_data/.decree/cron/
  cp automation-examples/cron/note-triage.md volumes/workspace_data/.decree/cron/

Logs for each run land in volumes/workspace_data/.decree/runs/ and are queryable in Grafana
via the Decree Overview dashboard.
