---
sidebar_position: 2
---

# FAQ

### Why not cloud AI and a few SaaS apps?

- Each app sees only its own data. A chat assistant doesn't know your notes unless you paste them in.
- Each one is a separate account and subscription, and can change under you.
- Here everything works on one folder, `workspace/`: code-server with `claude` and `opencode`,
  automated by decree, using [one model URL](./how-it-works#the-ai-slot-by-slot).
- With **Local AI**, [OpenViking](./ai/openviking) indexes `workspace/` and
  [Honcho](./ai/honcho) remembers you across sessions.
- It runs on your hardware. No subscription.

### Is it hard to set up?

Hostnames, TLS, secrets, logging and the automation engine are [set up once for every
service](./how-it-works). Setup is `./existential.sh`, then `./existential.sh flow on` for each
thing you want. Most automations are configured in a cron file's frontmatter, not code: see
[the four knobs](./flows/#the-four-knobs).

### Is it only for homelab people?

The flows are chores:

- a bank alert [becomes a budget entry](./flows/transaction-gmail-actual-budget)
- an idea in your notes [gets researched](./flows/note-to-action), coming back with only the
  questions you need to answer
- a photo [becomes searchable text](./flows/image-ocr)

### What if I don't have a GPU?

Core doesn't need one. For AI flows, answer `external` when asked and point `EXIST_MODEL_URL` at
a machine that has one, or use the CPU tier. See
[the hardware questions](./getting-started#the-hardware-questions).

### Do I have to turn everything on?

No. Every service is a flag, and a disabled one writes nothing. The first run builds **Core**
(work dir, terminal, automation, notifications). See
[Enable/Disable Services](./getting-started#enabledisable-services).

### What happens to my data if I stop using it?

It's plain files on your disks, readable without Existential running.

### Is it finished?

No. Services are added, replaced, or moved to the [graveyard](./graveyard/). The
[flows](./flows/) documented here all run today.

### Can the stack's own agent change the stack?

Not recommended. Use a coding agent against a frontier model, on the machine with the repo.

- opencode can't drive Hermes ([why](./decree/routing#why-not-opencode)).
- A local model at 64k context is too small for this repo.
- Hermes works on `workspace/`: the [agent automations](./flows/note-to-action) that write into
  `workspace/ai/`.
