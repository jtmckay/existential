---
cron: "0 * * * *"
routine: note-connect
CONNECT_PROFILE: "research"
CONNECT_MIN_SCORE: "7"
CONNECT_MAX_NOTES: "20"
# CONNECT_OUTPUT_RCLONE_DEST: "nextcloud:Notes"   # copy the writeup back beside the vault
---

Hourly scan of workspace/ (NOTES_DIR's default) for new or changed notes with a genuinely
interesting, non-obvious connection to something already in your knowledge base.

Different question than note-triage: not "is this worth acting on" but "does anything you
already know connect to this". The search runs through the `research` hermes profile
(ai/hermes/profiles/research/profile.yml) so it can reach OpenViking as a tool — a plain
completion cannot search the knowledge base.

The first run records the tree as seen WITHOUT scanning, so enabling this over an existing
workspace does not fire a call per note. To scan the backlog once, run it by hand with
CONNECT_BOOTSTRAP=true:

  printf -- '---\nroutine: note-connect\nCONNECT_BOOTSTRAP: true\n---\n' > automation/inbox/bootstrap.md

CONNECT_MIN_SCORE is the part worth tuning — raise it if too many topical-but-boring
connections get through, lower it if nothing ever clears the bar. Try CONNECT_DRY_RUN=true
for a few runs to see what it would have surfaced before it starts writing files and
notifying.

The same source-note-to-target pairing is never surfaced twice; editing the source note
again can surface a new pairing, just not the same one.

Requires hermes and openviking both enabled, and workspace/ actually indexed
(openviking-index-knowledgebase — on by default with Core). Point NOTES_DIR at /data/notes
instead to scan a note-triage-style vault mirror there.
