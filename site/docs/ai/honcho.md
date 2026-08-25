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
| `honcho-postgres` | PostgreSQL + pgvector for vector storage |

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

Its Postgres volume is tier 2 (`volumes_local/honcho_postgres_data`) — pgvector on an
embedded database, so local only and never NFS.
