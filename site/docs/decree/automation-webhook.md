---
service: services/automation-webhook
sidebar_position: 2
---

# Automation Webhook

`automation-webhook` ([decree-go-rest](https://github.com/jtmckay/decree-go-rest)) turns an
authenticated HTTP POST into a message in the `automation` daemon's inbox. It runs no work
itself and can write nothing but `inbox/`; decree runs what it queues.

It is an add-on, not part of Core: `EXIST_IS_SERVICES_AUTOMATION_WEBHOOK=true`, or a flow that
needs it (`nextcloud-capture`).

```bash
EXIST_IS_SERVICES_AUTOMATION_WEBHOOK=true
```

Then `./existential.sh && docker compose up -d` from the repo root.

## Endpoints

The endpoints are `workspace/.decree/decree-go-rest.yml`, seeded once from
`automation/decree-go-rest.yml`; edits are picked up without a restart, and
`GET /openapi.json` lists them all. Among them:

| Endpoint | Runs |
|---|---|
| `/capture` | `capture`: a line in the [capture stream](../getting-started#capture) |
| `/you-were-here` | `you_were_here`: [the digest](../getting-started#you-were-here), now |
| `/look-back`, `/look-back/{period}`, `/look-back/{period}/{scope}` | `look_back`: [a look back](../getting-started#look-back) |
| `/notify`, `/notify/{title}` | `notify`: an ntfy push |
| `/files` | `file_router`: Nextcloud's file events ([File Change Processing](./file-change-processing)) |
| `/hermes/*` | Follow-up work [Hermes](../ai/hermes) asks decree for |

Every request carries `Authorization: Bearer <secret>`. The default secret is
`AUTOMATION_WEBHOOK_SECRET` in `services/automation-webhook/.env`; `/files` and `/hermes/*`
each have their own.

```bash
curl -X POST https://automation-webhook.<domain>/notify/backup \
  -H "Authorization: Bearer $AUTOMATION_WEBHOOK_SECRET" --data-binary 'The backup finished.'
```

Containers reach it at `http://automation-webhook:8801`; a browser or phone needs the
[Caddy](../hosting/caddy) add-on for `https://automation-webhook.<domain>`.

## Without it

Everything it triggers can also be started from code-server's terminal, over the work dir:

```bash
cd /workspace && echo | decree emit --machine you_were_here
```

## Check it

```bash
./existential.sh test automation-webhook
```

The test is read-only: it probes `/healthz` and the rejection paths, and never sends an
authenticated POST.
