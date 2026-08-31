---
cron: "*/15 * * * *"
routine: openviking-index-dir
INDEX_DIR: /workspace
INDEX_PREFIX: "viking://resources/workspace"
INDEX_EXCLUDE: "(^|/)\\.git/|(^|/)node_modules/|(^|/)\\.venv/|^opencode\\.json$"
# The upload manifest (sha256 → path) so unchanged files are not re-sent.
# decree_data is the writable volume this container already has; losing it
# costs one full re-index, nothing more.
INDEX_STATE_DIR: /data/openviking-index
---

Index the `workspace/` directory at the repo root into OpenViking every 15
minutes, so anything you or the agents put there becomes searchable by hermes
through the openviking MCP server.

This is the same tree hermes mounts at `/opt/data/workspace` and code-server
mounts at `/workspace` — there is no separate knowledgebase directory to keep in
step.

Incremental: files whose contents have not changed since the last run are
skipped, changed files replace their old copy, and files you delete on disk are
removed from the index. A first run over a large directory takes a while (each
file is embedded); later runs cost one hash per file.

INDEX_EXCLUDE is an extended-regex matched against the path relative to
INDEX_DIR. It skips churn — git internals, dependency trees, the rendered
opencode config — not content.

`workspace/ai/` is deliberately NOT excluded. That directory holds the output of
the agent automations, and indexing it is what lets a later run find and build on
an earlier one. The loop is broken elsewhere: `workspace-sync` excludes `ai/`, so
that output never becomes a MinIO event and never triggers another run.

To index a second directory, copy this file with a new name and give it its own
INDEX_DIR and INDEX_PREFIX. The two keep separate manifests.

Copy to services/decree/decree/cron/ and restart decree to activate.
