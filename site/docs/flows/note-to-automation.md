---
sidebar_position: 1.8
---

# Note → Automation

Write down how you want something handled next time, and the stack offers to do it for you.

> **notes/process.md:** Next time I have a business idea, look up competitors and do a full
> market analysis, TAM included, so I know whether it's worth building.

A minute after you stop typing, your phone says: *When I write down a new business idea, I
can look up competitors; do a market analysis with TAM; say whether it's worth building. To
build it, move notes/automations/proposed/business_idea_research.md up to
notes/automations/.* Move it, and a moment later: *Automation built.*

From then on, every business idea you write down is researched in the background. A few
minutes after the note settles, your phone shows the verdict first, *favorable*,
*unfavorable*, or *already done, by these people*, so a solved problem never costs you a
weekend. The whole analysis, every claim linked to the page it came from, is in
`ai/automations/business_idea_research/`, where you can open it in code-server and ask Claude
to go deeper on any of it.

It runs on Core plus a chat model, local or on another machine (see
[Model endpoints](../configuration#endpoints--putting-roles-on-different-machines)), and reads
the web through [Firecrawl](../ai/firecrawl) when that is enabled. With no model it reads
nothing and does nothing. Without Firecrawl it still builds, but a step that needs the web
comes back as "where to look", never as an invented market.

## The proposal is a migration

What lands in `notes/automations/proposed/` is a decree migration for the `develop` machine:
the automation's intent and its requirements, never its code. **Overview** quotes what you
asked for, **Outcome** says what starts it, what it produces and where the results go,
**Constraints** says what it must not do, and **Acceptance Criteria** says how you'd know it
works. Edit any of it before you accept, in plain words: that file is the automation's
desired state from then on.

## How it works

| Step | Machine | What happens |
|---|---|---|
| A note settles | `note_watch` | The [file handler](../decree/file-handlers) for `notes/**/*.md` runs it a minute after the last save. One model call asks two things: is there a standing instruction here ("next time…", "whenever…"), and is this note the event an automation you accepted is waiting for? |
| A standing instruction | `automation_propose` | The model writes the migration, and you are told. Nothing is built. |
| You accept | `reconcile` | Moving the file to `notes/automations/<name>.md` files it as `.decree/migrations/A<stamp>-<name>.md`, which the daemon runs. |
| It is built | `develop` | The model reads the migration and answers with the trigger and the steps. `develop` writes `.decree/machines/<name>.yml` and `.decree/scripts/<name>.sh` and the trigger: a note event (`note_watch` matches your notes against it), a file handler in `.decree/handlers.yml`, or a schedule in `.decree/cron/<name>.md`. It must pass `decree check` and the trigger's own rules (a file trigger never matches its own output). A failed check is undone and shown to the model once more; a second failure reaches your phone like any failed run. |
| It runs | `<name>` | Its trigger starts it. It writes its results to `ai/automations/<name>/<date>-<note>.md` and sends their first lines to ntfy. |

## Research on the web, with Firecrawl

Turn on Firecrawl (`EXIST_IS_AI_FIRECRAWL=true`) and every automation can read the web. It
needs no search account or API key: Firecrawl searches the web itself and returns each
result's page as text, so one search is a set of sources, not a list of links. The steps
`develop` writes for the business-idea example look like this:

```bash
steps() {
    local sources
    sources="$(web_search "$(head -1 <<<"$NOTE") competitors" 5
               web_search "$(head -1 <<<"$NOTE") market size TAM" 5)"
    echo "## Verdict"
    ask "Favorable, unfavorable, or already done (by whom). One line, then why. \
Use only the sources below; cite URLs." "$NOTE

$sources"
    echo "## Existing solutions"
    ask "List who already does this, with what they charge. Cite URLs." "$sources"
    echo "## Market"
    ask "TAM, SAM and SOM, each with its source and how it was worked out." "$NOTE

$sources"
}
```

`web_search` and `web_read` come from `automation/lib/firecrawl.sh`, which any decree script
can source, not just a built automation. When Firecrawl is off, `develop` doesn't offer the
model those two, and refuses steps that use them.

The verdict comes first because the first lines of the result are what reach your phone. For
a decision you'll act on, that line is often all you need, and the rest is there when it isn't.

## Changing or removing one

The file in `notes/automations/` is the automation's desired state, the way a migration is in
this repo's own `.decree/`. Edit it and `reconcile` runs its migration again, so `develop`
rebuilds the automation to match. Delete it and the machine, its script, its trigger and its
migration are removed. Edit that file, never `.decree/`: everything there is rebuilt from it.

## What it can do, and what to read first

A built automation is a real decree machine. The model writes only its `steps` function; the
frame around it (`automation/lib/automations/run.sh`) is the same for every one, and gives it
the note or file that started it, `ask` (one answer from the chat model), `web_search` and
`web_read` (with Firecrawl), `curl` and `jq`.
Steps that need you (pay, sign up, send, decide) come back as a "For you" section.

It runs unattended in the `automation` container, which can read and write your workspace and
reach the stack's services, so its code is worth a look: `.decree/scripts/<name>.sh`, in
code-server. A name decree already uses (`notify`, a machine you wrote) is refused, so an
automation can never replace one.

`develop` here builds with the chat model, not with Claude Code: no AI CLI runs inside the
automation container, because its machines read your notes, and a note is the easiest place
to hide an instruction. For anything bigger than a few steps, ask Claude in code-server, which
writes the same kind of machine with you watching.
