---
sidebar_position: 10
---

# Honcho

- Source: https://github.com/plastic-labs/honcho
- License: [AGPL-3](https://www.gnu.org/licenses/agpl-3.0.html)
- Alternatives: Mem0, Zep, Letta (MemGPT)

Cross-session memory for [Hermes](./hermes). Without it, every agent conversation starts
cold; with it, what the agent learned about you last week is still there this week.

## Containers

| Container | Role |
|---|---|
| `honcho` | FastAPI memory server (port 8000) |
| `honcho-deriver` | Background queue worker — turns messages into the user representation |
| `honcho-postgres` | PostgreSQL + pgvector for vector storage |

The API and the deriver are separate processes by upstream's design: the API only
enqueues work. If `honcho-deriver` is not running, honcho keeps answering and keeps
recording messages, but nothing is ever derived from them — `./existential.sh run
honcho test` warns when the queue has stalled.

The deriver batches per conversation, and by default waits for 1024 tokens to pile up
in one before spending an LLM call on it. That suits a busy multi-tenant server and
strands short chats here, so `config.toml` sets `FLUSH_ENABLED = true`: every
conversation is derived as soon as it has anything to derive, at the cost of more,
smaller calls to the extract model.

## Access

Internal only — `http://honcho:8000` on the `exist` network. There is no Caddy hostname for
it by default; add a `reverse_proxy` block if you want the API docs at
`https://honcho.EXIST_DOMAIN/docs`.

## Enable

```bash
EXIST_IS_AI_HONCHO=true
```

Then `./existential.sh && docker compose up -d` from the repo root.

## Activation

Honcho needs to be registered with Hermes once, after both containers are healthy:

```bash
docker exec -it hermes-agent hermes memory setup honcho
```

## Notes

Its Postgres volume is `volumes/honcho_postgres_data`, declared `db: true` — pgvector on an
embedded database, so local only and never NFS. Back it up by copying
`honcho-db-backup-{nightly,weekly}.md` from `services/automation/backup/cron.example/`
into `cron/` and restarting `decree-backup`.

The embedding dimension is not free to change. `EXIST_MODEL_EMBED_DIM` becomes the
`vector(N)` column type the first time honcho starts; after that, honcho refuses to boot
on a mismatch rather than storing wrong-sized vectors, and its resize script refuses to
alter a column that already holds embeddings. Changing the embedding model means
restoring the old `EXIST_MODEL_EMBED`/`_DIM` or discarding the stored memory.

There is no authentication (`USE_AUTH = false`) and no Caddy hostname, so honcho is
reachable by anything on the `exist` network and nothing outside it. It holds
conversation memory — keep it that way unless you add auth first.
