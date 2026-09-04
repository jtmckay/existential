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

Everything else in the stack — container names, service choices, routine internals, volume
layout beyond what's below — is free to change. Don't build against it.
:::

## 1. Send something in

`automation-webhook` turns an HTTP POST into work. It is the only inbound entry point you need.

```bash
curl -X POST https://automation-webhook.$EXIST_DOMAIN/notify/Backup%20done \
  -H "Authorization: Bearer $SECRET" \
  -d 'disk 3 is full'
```

- **Auth** is a static bearer token, minimum 32 characters, per endpoint.
- **The body is never parsed.** It's opaque bytes copied verbatim, whatever the
  `Content-Type`. It only has to be non-empty. Post plain text.
- **Path parameters** must match `[A-Za-z0-9_\-!]+`, 200 characters max. Anything else is
  rejected rather than sanitised.

| Status | Meaning |
|---|---|
| `201` | Accepted. Body: `{"file": "notify-143052.md", "path": "/notify"}` |
| `400` | Empty body, or a bad path parameter |
| `401` | Missing or wrong bearer token |
| `404` | Unknown path — **and any non-POST method** |
| `413` | Body too large (256 KB default) |
| `429` | Rate limited (60 requests/minute, global not per-IP) |

`GET /healthz` returns `{"ok": true}` and is never rate limited.

Two requests to the same routine within the same second collide and the second gets a `500`.
That's deliberate — message identity comes from the filename, so overwriting would silently
drop work. Retry with a jitter if you're sending in bursts.

### Adding your own endpoint

Routes are configuration, not code. Add an entry to
`services/automation/webhook/config.exist.yml`, re-run `./existential.sh`, and the route exists:

```yaml
endpoints:
  - path: /note/{id}
    params:
      id: '[0-9a-f]{8,16}'      # optional; may narrow the default charset, never widen it
    frontmatter:
      routine: notes/compile-notes
      note_id: '{{id}}'
```

## 2. The message shape

Every unit of work — whatever created it — is one markdown file with YAML frontmatter. There
is one queue and one format.

```markdown
---
routine: notify
ntfy_title: Backup done
ntfy_priority: high
---

disk 3 is full
```

- **`routine:`** is the only required key. It names the script that will run.
- **Every other key becomes an environment variable** for that routine. That's the whole
  parameter-passing mechanism.
- **The body is the message content**, passed to the routine as-is.

Messages reach the queue from three places, and all three produce this same file:
a webhook POST, a cron schedule, or another routine emitting a follow-up.

:::tip[Files as a trigger]
A fourth, built on the first: the [File Processor](./decree/file-change-processing) turns a
file landing in S3-compatible storage into one of these messages, matched by path against
whichever processors you have registered. It is how [Camera → OCR](./flows/image-ocr) and
[Recording → Transcription](./flows/recording-transcription) start.
:::

## 3. Where the data lives

Two locations, both plain host directories you can read directly.

| What | Where | Use it for |
|---|---|---|
| **Bulk user data** | `volumes/<name>/` | Files, photos, attachments, recordings, documents |
| **Object storage** | MinIO, S3 API | Anything you'd rather reach over a network than a mount |

Everything under `volumes/` is a host bind mount owned by your user — no Docker-managed
volumes, nothing opaque, nothing requiring root to read. Point your front end at the
filesystem or at the S3 endpoint, whichever suits it.

:::warning[Not part of the contract]
Volumes declared `db: true` hold live databases. Read them through their service's API, never
off disk — they're mid-write, and NFS or a concurrent reader will corrupt or mislead you.
:::

## 4. Read the result

Every run writes to `automation/runs/<message-id>/`, from every daemon in the stack, in one
audit trail.

`run.json` lands there once the run finishes:

| Field | Meaning |
|---|---|
| `message_id` | Full message ID |
| `routine` | Which routine ran |
| `trigger` | `inbox`, `cron:<name>`, or `chain` |
| `attempts` | How many tries it took |
| `exit_code` | Exit code of the final attempt |
| `start` / `end` | ISO-8601 timestamps |
| `duration_s` | Elapsed seconds |

`routine.log` sits alongside it with the full output, and exists *during* the run — poll it
if you want progress rather than a result.

Work that fails is retried, then dead-lettered. A missing `run.json` means the run is still
going or the daemon isn't up; it doesn't mean the message was lost.

## What this doesn't give you

Being straight about the edges:

- **No read API.** There is no HTTP endpoint that returns your data. You read the filesystem
  or S3, or you talk to an individual service's own API.
- **No push.** Nothing calls you back when a run finishes. Watch `runs/`, or have your
  routine POST somewhere at the end.
- **No auth model.** One static bearer token per endpoint. No users, no scopes, no rotation.
- **No stability promise beyond the four sections above.** Everything else moves.

If you need more than this, the honest answer is that you're building a service, and it
belongs in the stack as one — see [Flows](./flows/) for how the existing ones are put
together.

And if what you actually want is to run your own code *inside* the stack rather than integrate
with it from outside, you want a routine, not this contract:
[Writing a Routine](./writing-a-routine).
