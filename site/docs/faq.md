---
sidebar_position: 2
---

# FAQ

Answers to the objections people actually raise before trying this.

### Why not just use cloud AI and a bunch of SaaS apps?

Because none of them see the whole picture. A cloud chat assistant doesn't know what's in your
notes vault or your bank alerts unless you paste it in by hand, every time. A budgeting app
doesn't know about the note you wrote last week. Each one is a separate subscription, a separate
account, and a separate place your data lives — and a provider can change or degrade the product
under you at any point.

Existential's agent sits behind [one local endpoint](./how-it-works#the-ai-spine-slot-by-slot)
with your files already in reach — [OpenViking](./ai/openviking) indexes `workspace/`, so
anything you write down is something it can already read and cite, no upload step required — and
[Honcho](./ai/honcho) gives it memory of *you* across sessions, not just within one. It runs on
your hardware, with your data, and no subscription.

### Isn't this too complex to set up?

The plumbing — hostnames, TLS, storage tiers, secrets, backups, logging, the automation engine —
is [solved once, for everything](./how-it-works), not once per app. Setting it up is mostly
answering `./existential.sh quest` and flipping a `true`/`false` flag per service. Turning on an
automation is usually a line of prompt in a cron file's frontmatter, not writing code — see
[the four knobs](./flows/#the-four-knobs).

### Does this only help homelab nerds?

The flows are chores, not infrastructure: a bank alert email
[becomes a budget entry](./flows/transaction-gmail-actual-budget) without you opening an app; a
stray idea in your notes gets [triaged and researched](./flows/note-to-action), coming back with
only the questions you actually have to answer; a photograph of something
[becomes searchable text](./flows/image-ocr). None of that requires knowing what a Docker
container is to benefit from — that part is what Existential handles for you.

### What if I don't have a GPU?

Set the GPU vendor to `external` during setup and point `EXIST_OLLAMA_URL` at another machine
that has one, or use the CPU-only model tier. See
[the hardware questions](./getting-started#the-hardware-questions).

### Do I have to turn everything on?

No — every service is a flag, and disabled services render nothing and cost nothing. The
`quest` picker offers **Core** (files, house, agent, memory, voice, monitoring) as one yes/no, or
you can go service by service. See [Enable/Disable Services](./getting-started#enabledisable-services).

### What happens to my data if I stop using Existential?

It was never anywhere else. Everything lives as plain files on disks you own — readable,
copyable, and greppable with Existential not running at all.

### Is this finished, or actively changing?

Actively changing — it's a curated stack, not a frozen product, and services get added,
replaced, or moved to the [graveyard](./graveyard/) when something better comes along. The
[flows](./flows/) documented here are the ones that ship and run today; nothing on this site is
aspirational.

### Can I use the stack's own agent to change the stack?

Not recommended at 64k context or less — use a dedicated coding agent against a frontier model, on the machine that holds the repo.
Hermes is an agent running its own tool loop behind an OpenAI-compatible endpoint, which is the
wrong shape for a coding agent to drive (the concrete failure:
[Why not OpenCode](./decree/routing#why-not-opencode)), and a local model at 64k context is the
wrong size for editing a repo this large.

Hermes earns its keep on the other side of that line: inside a container, on `workspace/` — the
[agent automations](./flows/note-to-action) that write into `workspace/ai/`, not the repo.
