---
sidebar_position: 4
---

# Build On It

:::info[Level 4 of 4 · Code]
The contract you write against. Back out to [Level 3 · Flows](./flows/) for worked examples of
everything below.
:::

To build your own front end (a phone app, a dashboard), use the four things on this page. They
won't change. Everything else (container names, services, machine internals, volume layout) may.

## 1. Send something in

`automation-webhook` ([decree-go-rest](https://github.com/jtmckay/decree-go-rest)) turns an
HTTP POST into work. Add-on: `EXIST_IS_SERVICES_AUTOMATION_WEBHOOK=true`. See
[Automation Webhook](./decree/automation-webhook).

```bash
curl -X POST https://automation-webhook.$EXIST_DOMAIN/notify/Backup_done \
  -H "Authorization: Bearer $SECRET" \
  --data-binary 'disk 3 is full'
```

- **Auth** is a static bearer token, minimum 32 characters, per endpoint.
- **The body is passed through as is**, whatever the `Content-Type`. Post plain text.
- **Path parameters** must match `[A-Za-z0-9_\-!]+` (or the endpoint's pattern), 200 bytes max,
  or the request is rejected.

Shipped endpoints:

- `POST /capture` with `{"source": "...", "text": "..."}`: a line in your
  [capture stream](./getting-started#capture).
- `POST /you-were-here`: the [digest](./getting-started#you-were-here), now.
- `POST /look-back`, `/look-back/{period}` (`week`, `month`, `quarter`, `year`),
  `/look-back/{period}/work`: a [look back](./getting-started#look-back).

| Status | Meaning |
|---|---|
| `201` | Queued. Body: `{"id": "20261005T073848Z-734a8f", "path": ".decree/inbox/….md", "machine": "notify"}` |
| `400` | A bad path parameter, a missing required body, or decree rejected the message |
| `401` | Missing or wrong bearer token |
| `404` | Unknown path |
| `405` | Known path, wrong method |
| `413` | Body too large (256 KiB) |
| `429` | Rate limited (60 authenticated requests a minute, all endpoints together) |

Every error is JSON, `{"error": "…"}`. `GET /healthz` is never rate limited, and
`GET /openapi.json` describes every endpoint.

The `id` becomes the run's id; use it to find the result (section 4).

### Adding your own endpoint

Add an entry to `automation/decree-go-rest.yml`; no restart:

```yaml
endpoints:
  - path: /note/{id}
    patterns: { id: '[0-9a-f]{8,16}' }   # optional; replaces the default pattern
    message:
      machine: my_job                   # declares note_id in its data:
      params: { note_id: '{{id}}' }
```

A request can't choose the machine. Every key: decree-go-rest's SPEC.md §3.

## 2. The message shape

Every unit of work is one markdown file with YAML frontmatter, in one queue.

```markdown
---
machine: notify
params:
  ntfy_title: Backup done
  ntfy_priority: high
---

disk 3 is full
```

- **`machine:`** is the only required key. It names the machine that will run.
- **`params:`** are that machine's settings. Each must be one the machine declares, or the run
  fails and says which.
- **The body is the message content**, passed to the machine as-is.

Messages come from a webhook, a cron schedule, another machine, or a file landing in Nextcloud
([File Processor](./decree/file-change-processing)).

## 3. Where the data lives

Plain host directories:

| What | Where | Use it for |
|---|---|---|
| **Bulk user data** | `volumes/<name>/` | Files, photos, attachments, recordings, documents |
| **Synced files** | Nextcloud (WebDAV) | Anything you'd rather reach over a network than a mount |

Everything under `volumes/` is a host directory owned by your user.

:::warning[Not part of the contract]
Volumes declared `db: true` are live databases. Read them through the service's API, not off
disk.
:::

## 4. Read the result

Every run writes to `volumes/workspace_data/.decree/runs/<id>/` (`services/automation-backup/runs/<id>/` for the
backup daemon's), with the `id` the webhook returned.

- `message.md`: the message, with the run's `state` in its frontmatter. `done` and `failed` are
  final.
- `events.jsonl`: one line per step; the last, `"type":"run_finished"`, has the final `state` and
  `duration_ms`.
- `<NNNN>-<state>-<script>.log`: each script's output, written live.
- A `failed` run can be retried (`decree status` prints the command).
- No run directory yet: the message is still queued or the daemon is down.

## What this doesn't give you

- **No read API.** Read the filesystem, Nextcloud, or a service's own API.
- **No push.** Watch `runs/`, or have your script POST somewhere at the end.
- **No auth model.** One static bearer token per endpoint.
- **No stability promise** beyond the four sections above.

Need more? Build it as a service in the stack. To run code inside the stack, write a machine:
[Writing an Automation](./writing-a-routine).
