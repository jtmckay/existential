---
sidebar_position: 9
---

# OpenViking

- Source: https://github.com/volcengine/OpenViking
- License: [AGPL-3](https://www.gnu.org/licenses/agpl-3.0.html)
- Status: RIP, replaced by [qmd](../../ai/qmd.md)

Retired 2026-11. Everything the stack used it for, searching the workspace, qmd does on the CPU
with no embedding model, no API key and no backup, matching exact words as well as meaning and
fresher (60 seconds, not 15 minutes). Its own extras, a memory agents write to and a web UI,
were never used, and a memory kept outside your Markdown files is against how the stack keeps
knowledge. What follows is the page as it was.

Context database for AI agents: a `viking://` filesystem of memory, resources and skills that
persists between sessions.

## Containers

| Container | Role |
|---|---|
| `openviking` | REST API, MCP server, and Web Studio (port 1933) |

The knowledgebase indexer cron runs in the main `automation` daemon, and the backup of
`openviking_data` in `automation-backup` — OpenViking ships no container of its own for either.

## Access

- Containers: `http://openviking:1933` on the `exist` network
- Browser (Web Studio): `https://openviking.EXIST_DOMAIN`
- Agents: [pi](../../ai/pi.md) connects to it as an MCP server

## Enable

```bash
EXIST_IS_AI_OPENVIKING=true
```

Then `./existential.sh && docker compose up -d` from the repo root.

## What it indexes

The workspace (`volumes/workspace_data`) — the same tree Nextcloud serves and code-server mounts
at `/workspace`. Everything you actually
work on is searchable without a second knowledgebase directory to keep in step.

The `openviking_index_dir` machine uploads it into `viking://resources/workspace` every
15 minutes. It is incremental: unchanged files are skipped, changed files replace their
old copy, and files you delete on disk leave the index on the next run. A first pass over
a large tree takes a while — each file is embedded on the way in.

The directory is mounted on the **automation daemon**, not on `openviking`. OpenViking's HTTP
and MCP APIs both refuse host filesystem paths outright, so content only ever reaches it by
upload — which is also why there is no watched-directory setup.

`workspace/ai/` — where the agent automations write — is indexed like everything else, so
an agent can find and build on what an earlier run produced. Writing there
starts nothing unless a [file handler](../../decree/file-handlers.md) matches it, so keep handler
patterns off `ai/` and that output never triggers more runs.

## What it stores

| Volume | Tier | Contents |
|---|---|---|
| `openviking_data` | 2 — local, backed up | Vector store and workspace. Embedded DB, never NFS. |

The upload manifest that keeps unchanged files from being re-embedded lives in the decree
daemon's own `decree_data` volume (`/data/openviking-index`), not in a volume of its own. It
is a cache: losing it costs one full re-index, not any content.
