---
sidebar_position: 4
---

# Build On It

:::info[Level 4 of 4 · Code]
The contract you write against. Back out to [Level 3 · Flows](./flows/) for worked examples of
everything below.
:::

Existential is usable as a backend. The stack stores your data in one place and runs work
against it; if you want a different front end — a phone app, a single dashboard, a text box
in a terminal — you can build one against the pieces documented here without touching the
stack itself.

:::info[What this page is]
This is a deliberately **small, frozen contract**. Four things. They are the parts you can
build against without expecting them to move.

Everything else in the stack — container names, service choices, machine internals, volume
layout beyond what's below — is free to change. Don't build against it.
:::

## 1. Send something in

`automation-webhook` ([decree-go-rest](https://github.com/jtmckay/decree-go-rest)) turns an
HTTP POST into work. It is the only inbound entry point you need.

```bash
curl -X POST https://automation-webhook.$EXIST_DOMAIN/notify/Backup_done \
  -H "Authorization: Bearer $SECRET" \
  --data-binary 'disk 3 is full'
```

- **Auth** is a static bearer token, minimum 32 characters, per endpoint.
- **The body is never parsed.** It's opaque bytes handed to the message verbatim, whatever the
  `Content-Type`. Post plain text.
- **Path parameters** must match `[A-Za-z0-9_\-!]+` (or the endpoint's own pattern), 200 bytes
  max. Anything else is rejected rather than sanitised.

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

The `id` is the run's id once decree claims the message, so it is how you find the result
(section 4).

### Adding your own endpoint

Endpoints are configuration, not code. Add an entry to `automation/decree-go-rest.yml` and it
is live, no restart:

```yaml
endpoints:
  - path: /note/{id}
    patterns: { id: '[0-9a-f]{8,16}' }   # optional; replaces the default pattern
    message:
      machine: my_job                   # declares note_id in its data:
      params: { note_id: '{{id}}' }
```

An endpoint fixes its machine; a request can never choose one. Every key, with its default:
decree-go-rest's SPEC.md §3.

## 2. The message shape

Every unit of work — whatever created it — is one markdown file with YAML frontmatter. There
is one queue and one format.

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

Messages reach the queue from three places, and all three produce this same file:
a webhook POST, a cron schedule, or another machine emitting a follow-up.

:::tip[Files as a trigger]
A fourth, built on the first: the [File Processor](./decree/file-change-processing) turns a
file landing in Nextcloud into one of these messages, matched by path against
whichever processors you have registered. It is how [Camera → OCR](./flows/image-ocr) and
[Recording → Transcription](./flows/recording-transcription) start.
:::

## 3. Where the data lives

Two locations, both plain host directories you can read directly.

| What | Where | Use it for |
|---|---|---|
| **Bulk user data** | `volumes/<name>/` | Files, photos, attachments, recordings, documents |
| **Synced files** | Nextcloud (WebDAV) | Anything you'd rather reach over a network than a mount |

Everything under `volumes/` is a host bind mount owned by your user — no Docker-managed
volumes, nothing opaque, nothing requiring root to read. Point your front end at the
filesystem or at Nextcloud, whichever suits it.

:::warning[Not part of the contract]
Volumes declared `db: true` hold live databases. Read them through their service's API, never
off disk — they're mid-write, and NFS or a concurrent reader will corrupt or mislead you.
:::

## 4. Read the result

Every run writes to `volumes/workspace_data/.decree/runs/<id>/` (`services/automation/backup/runs/<id>/` for the
backup daemon's), with the `id` the webhook returned.

`message.md` is the message, with the run's current `state` mirrored into its frontmatter:
`done` and `failed` are final, anything else means it is still going. `events.jsonl` is the
full record, one JSON line per step, and its last line, `"type":"run_finished"`, carries the
final `state` and `duration_ms`. Each script's output is `<NNNN>-<state>-<script>.log`
alongside, written live — tail it if you want progress rather than a result.

A run that fails stays `failed` and can be retried (`decree status` prints the command). A
missing run directory means the message is still queued or the daemon isn't up; it doesn't
mean the message was lost.

## What this doesn't give you

Being straight about the edges:

- **No read API.** There is no HTTP endpoint that returns your data. You read the filesystem
  or Nextcloud, or you talk to an individual service's own API.
- **No push.** Nothing calls you back when a run finishes. Watch `runs/`, or have your
  script POST somewhere at the end.
- **No auth model.** One static bearer token per endpoint. No users, no scopes, no rotation.
- **No stability promise beyond the four sections above.** Everything else moves.

If you need more than this, the honest answer is that you're building a service, and it
belongs in the stack as one — see [Flows](./flows/) for how the existing ones are put
together.

And if what you actually want is to run your own code *inside* the stack rather than integrate
with it from outside, you want a machine, not this contract:
[Writing an Automation](./writing-a-routine).
