---
machine: plugin
automation: knowledgebase
name: Knowledge base
tagline: The workspace indexed into OpenViking every 15 minutes, so pi answers from your material
docs: /docs/ai/openviking
services:
  - EXIST_IS_AI_OPENVIKING
  - EXIST_IS_SERVICES_AUTOMATION
needs:
  - openviking_index_dir
cron:
  openviking-index-knowledgebase: |
    ---
    cron: "*/15 * * * *"
    machine: openviking_index_dir
    params:
      INDEX_DIR: /workspace
      INDEX_PREFIX: "viking://resources/workspace"
      INDEX_EXCLUDE: "(^|/)\\.git/|(^|/)node_modules/|(^|/)\\.venv/"
      # The upload manifest (sha256 → path) so unchanged files are not re-sent.
      # decree_data is the writable volume this container already has; losing it
      # costs one full re-index, nothing more.
      INDEX_STATE_DIR: /data/openviking-index
    ---

    Index the `workspace/` directory at the repo root into OpenViking every 15
    minutes, so anything you or the agents put there becomes searchable by pi
    through the openviking MCP server.

    This is the same tree code-server and automation
    mount at `/workspace` — there is no separate knowledgebase directory to keep in
    step.

    Incremental: files whose contents have not changed since the last run are
    skipped, changed files replace their old copy, and files you delete on disk are
    removed from the index. A first run over a large directory takes a while (each
    file is embedded); later runs cost one hash per file.

    INDEX_EXCLUDE is an extended-regex matched against the path relative to
    INDEX_DIR. It skips churn — git internals, dependency trees — not content.

    `workspace/ai/` is deliberately NOT excluded. That directory holds the output of
    the agent automations, and indexing it is what lets a later run find and build on
    an earlier one. The loop is broken elsewhere: routines write it straight to disk, which
    fires no Nextcloud event, and no file handler should match it.

    To index a second directory, copy this file with a new name and give it its own
    INDEX_DIR and INDEX_PREFIX. The two keep separate manifests.

    `./existential.sh flow on knowledgebase` activates it.
---

Never change EXIST_MODEL_EMBED after the first index: the stored vectors would no
longer match. Deleting a file drops it from the index on the next run.
