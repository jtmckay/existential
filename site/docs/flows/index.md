---
sidebar_position: 1
---

# What It Does

Each page here is one problem, what the stack does about it, the line that turns it on, and
what is left for you to do.

| When… | It… | |
|---|---|---|
| the thread is gone by Friday | brings yesterday back every morning, looks back over the week and the year, and finds the note you already wrote | [Pick Up the Thread](./pick-up-the-thread.md) |
| your notes are in five places | puts what you capture, type, read and upload in one folder search can find | [Everything in One Place](./one-place.md) |
| ideas die in a note | does the part that doesn't need you, and comes back with the questions that do | [Ideas That Get Followed Up](./ideas.md) |
| every system needed you to remember it | turns "next time…" into a routine that runs whether or not you remember | [Tell It Once](./tell-it-once.md) |
| voice memos and photos pile up unread | turns them into text beside them | [Voice and Photos](./voice-and-photos.md) |
| money, photos and the house are elsewhere | brings them onto the same hardware | [Money, Photos and the House](./home.md) |
| you don't want another thing to maintain | checks itself, backs up and stays current, and only speaks up when it matters | [It Looks After Itself](./looks-after-itself.md) |

## On from the start

The morning digest, *next time…* offers, file advice and the health check are on in a new
install. Everything else is off until you turn it on.

## Turning one on

Each page has its lines. They are of two kinds:

```bash
./existential.sh service on whisperx      # an app, which runs from the next: docker compose up -d
./existential.sh plugin on transcribe     # a routine, installed at once with what it needs
```

- `./existential.sh plugin` lists every routine and which are on.
- `plugin off <name>` and `service off <name>` turn one off. Your files, and any schedule you
  edited, are kept.
- Most routines need a chat model: [Getting Started](../getting-started.md#point-it-at-a-model).

What a routine is, and how to write your own: [Plugins](../plugins/index.md).
