---
sidebar_position: 5
---

# Tell It Once

Every system you tried needed you to remember to use it. Here a decision is a file, and it runs
whether or not you remember it.

## Write "next time…", and it offers to do it

**On by default.** Write how you want something handled next time, in any note:

> **notes/process.md:** Next time I have a business idea, look up competitors and do a market
> analysis, so I know whether it's worth building.

A minute after you stop typing, your phone offers to automate it, with the steps listed. Nothing
is built yet: the offer is a plain-words spec in `workspace/ai/proposed/`, which you can edit.

1. **To have it built**, move the spec into `notes/automations/`. A moment later your phone says
   it's ready to review.
2. **To turn it on**, read what was built, then in code-server's terminal:

   ```bash
   mv ai/proposed/<name>.md .decree/plugins/ && decree install <name>
   ```

From then on every business idea you write is researched on the web, and your phone gets the
verdict first: favorable, unfavorable, or already done and by whom, every figure linked to its
source. The full write-up is in `workspace/ai/automations/<name>/`.

- Needs a chat model. Web research needs [Firecrawl](../ai/firecrawl.md), which is in Core.
- Nothing runs before you move it, and it runs with access to your workspace, so read it first.
- To change one, edit its spec in `notes/automations/` and a new version is offered. To stop one:
  `rm .decree/plugins/<name>.md && decree install`.
- For something bigger, ask Claude in code-server: it knows how to write one.
- To stop offering altogether: `./existential.sh plugin off note_watch reconcile`.

What happens underneath: [Your Own Plugins](../plugins/offer-and-accept.md#built-from-a-note).

## Drop a file in a folder, and the next step happens

**On by default.** Each file you add is read once. If a routine you have off would handle it, or
one nobody has written yet plainly should, your phone says so: the line that turns it on, or what
to ask Claude for. A folder of PDFs is one message, not fifty.

It starts from the day it is on: what is already in the workspace is never read. Each suggestion
is sent once; `workspace/.decree/store/file_advise/` lists what was read and suggested, and
deleting a line there asks again. Off: `./existential.sh plugin off file_advise`.

To have a file start a routine of your own, tell Claude in code-server *"when an invoice lands
in invoices/, file it and tell me"*, and it writes the routine:
[File Handlers](../plugins/file-handlers.md).

## Routines you write yourself

A routine of your own is one file in `workspace/.decree/plugins/`, written by you or by an agent,
and installed from code-server's terminal: [Your Own Plugins](../plugins/offer-and-accept.md).
Everything the stack ships is a routine like that, off until you turn it on.
