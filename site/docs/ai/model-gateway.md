---
service: ai/model-gateway
sidebar_position: 4
---

# Model Gateway

The controller's model endpoint: one OpenAI-compatible `/v1` URL for every host. A call names a
model, and the gateway leases whichever GPU host offers it, holds the lease while calls come,
and gives it back a few seconds after the last one. Coding in opencode on any host takes the GPU
when it needs it and hands it back when you stop.

- Source: `ai/model-gateway/gateway.ts` (this repo)
- Telemetry: none; it sends nothing anywhere but to the GPU host it leases.

## Turn it on

On the controller, `./existential.sh run fleet controller` turns
it on with Loki. Then `docker compose up -d`. It is the fleet's API: besides `/v1` it serves
`GET /plugins/fleet_gpu.md`, the fleet lib as a decree plugin for a project of your own
([Controller and Workers](../hosting/controller-and-workers.md#a-decree-project-of-your-own)).
It also fronts the controller's Loki for the hosts on your own network (`/loki/api/v1/push`,
`query_range`, `labels`, `status/buildinfo`), so Loki itself, which has no login, never leaves
loopback. Every path but `/health` and `/ready` takes the fleet secret, and a body is capped at
64 MB. It reads the fleet lib from the repo's own plugin file (`automation/plugins/fleet.md`,
read-only), never the workspace's copy, which an automation or a synced device could change,
and nothing of the host's.

On every host that should use it, in `.env.shared`:

```
EXIST_MODEL_URL=http://<controller>:4400/v1
EXIST_MODEL_KEY=
```

`EXIST_MODEL_KEY` stays blank: the key is the fleet secret (`EXIST_FLEET_SECRET`), which every
host in the fleet has. `EXIST_MODEL_CHAT` blank means the first model the fleet offers.

## What it does with a call

| Call | |
|---|---|
| `GET /v1/models` | Every model a GPU host offers now (its `lease_gpu` plugin reports them to the controller). |
| `POST /v1/...` | Finds the host whose offer lists `model`, leases it (`fleet_use`, the same lib decree scripts use) and streams that host's answer back. |
| No host offers the model | 404, saying so. |
| The host would not lease it | 503, saying why. |

Calls in a burst share one lease, given back 5 seconds after the last (`FLEET_IDLE`). Decree
scripts on the controller lease the same way, so they wait their turn with your editor.

## Check it

```bash
./existential.sh run model-gateway test
curl -H "Authorization: Bearer $EXIST_FLEET_SECRET" http://<controller>:4400/v1/models
```
