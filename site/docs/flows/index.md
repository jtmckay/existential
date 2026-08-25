---
sidebar_position: 1
---

# Flows

A flow is one complete path from *something happened* to *it was handled*.

That's the level Existential is meant to be understood at. Underneath, a flow might touch
half a dozen services — but you set it up once and then think about it as a single thing:
**a recording becomes a transcript**, **a receipt becomes a budget entry**, **a file becomes
a filed file**.

## How every flow works

All of them have the same three parts. Once you've seen one, you've seen all of them.

```
  something lands  →  a routine runs  →  the result goes somewhere useful
```

1. **Something lands.** A file appears, an email arrives, you talk to your phone, a service
   fires a webhook. Everything ends up as a message in one queue.
2. **A routine runs.** One script, picked by name from that message. It does the work —
   transcribe, extract, sort, file, notify.
3. **The result goes somewhere useful.** A note, a task, a budget line, a notification —
   or another message, which starts the next flow.

There is only one queue and one kind of message, so there is only one thing to learn. Adding
a new flow means writing one more routine, not learning a new system.

## The three that matter most

### Capture → one place

Anything you throw at it gets picked up, understood, and filed — without you choosing a
destination each time.

- [File Processor](./file-change-processing) — a file appears anywhere, and gets handled by rule
- [Telegram Image → OCR](./image-ocr) — photograph something, get back its text

### Voice → action

Say it out loud and have it turn into something real, without opening an app.

- [Recording → Transcription](./recording-transcription) — recordings become searchable, speaker-labelled text
- [AutoVoice — Voice Triggers](./autovoice) — speak a phrase, trigger a routine
- [HAwake — Custom Wake Word](./hawake) — train your own wake word
- [HAwake → Home Assistant → Tasker](./hawake-homeassistant) — wake word to phone action, end to end

### Money → budget

The most tedious recurring paperwork in most people's lives, handled without attention.

- [Bank Alert → Gmail → Budget](./transaction-gmail-actual-budget) — transaction emails become budget entries
- [Bank Alert → Receipt Split](./receipt-split) — one charge, split into its real line items

## Building your own

Every flow above is a routine plus a trigger. The contract for both — how to send something
in, what a message looks like, how to read the result — is documented in
[Build On It](../build-on-it).
