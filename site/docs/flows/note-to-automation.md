---
sidebar_position: 1.8
---

# Note → Automation

Write down how you want something handled next time, and the stack offers to do it for you.

> **notes/process.md:** Next time I have a business idea, look up competitors and do a full
> market analysis, TAM included, so I know whether it's worth building.

A minute after you stop typing, your phone says: *When I write down a new business idea, I
can look up competitors; do a market analysis with TAM; say whether it's worth building. To
have it built, move ai/proposed/business_idea_research.md into
notes/automations/.* Move it, and a moment later: *Automation ready to review*, with where to
read what was built. Read it, then in code-server's terminal:

```bash
mv ai/proposed/business_idea_research.md .decree/plugins/ && decree install business_idea_research
```

Nothing `develop` builds runs before you move it: [Your Own Plugins](../plugins/offer-and-accept.md).

After that, each business idea you write is researched. Your phone gets the verdict first:
*favorable*, *unfavorable*, or *already done, by these people*. The full analysis, with sources,
is in `ai/automations/business_idea_research/`.

- Needs Core plus a chat model ([Model endpoints](../configuration.md#endpoints--putting-roles-on-different-hosts)).
  With no model it does nothing.
- Reads the web through [Firecrawl](../ai/firecrawl.md) when enabled. Without it, web steps come back
  as "where to look".

## The proposal is a spec

`ai/proposed/` first gets a spec for the `develop` machine: what you want, not code.

- **Overview**: what you asked for
- **Outcome**: what starts it, what it produces, where results go
- **Constraints**: what it must not do
- **Acceptance Criteria**: how you'd know it works

Edit it in plain words before moving it. It stays the automation's desired state.

## How it works

| Step | Machine | What happens |
|---|---|---|
| A note settles | `note_watch` | The [file handler](../decree/file-handlers.md) for `notes/**/*.md` runs it a minute after the last save. One model call asks two things: is there a standing instruction here ("next time…", "whenever…"), and is this note the event an automation you accepted is waiting for? |
| A standing instruction | `automation_propose` | The model writes the spec, and you are told. Nothing is built. |
| You say "build this" | `reconcile` | Moving the spec to `notes/automations/<name>.md` hands it to `develop`. |
| It is built, as an offer | `develop` | The model reads the spec and answers with the trigger and the steps. `develop` writes them as one plugin file: a machine, its script, and the trigger as `when:` (a note event `note_watch` matches your notes against), `handlers:` (a file change) or `cron:` (a schedule). It must pass `decree check`, in a scratch copy, and the trigger's own rules (a file trigger never matches its own output). A failed check is shown to the model once more; a second failure reaches your phone like any failed run. The file goes to `ai/proposed/<name>.md`. **Nothing is installed.** |
| You install it | `mv ai/proposed/<name>.md .decree/plugins/ && decree install <name>` | You read the file, and only then is it installed and on. |
| It runs | `<name>` | Its trigger starts it. It writes its results to `ai/automations/<name>/<date>-<note>.md` and sends their first lines to ntfy. |

## Research on the web, with Firecrawl

With Firecrawl on (`EXIST_IS_AI_FIRECRAWL=true`), automations can search and read the web, with
no API key. Each search returns the pages' text. The steps `develop` writes for the example:

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

- `web_search` and `web_read` come from `workspace/.decree/lib/firecrawl.sh`; any decree script can use
  them. With Firecrawl off, `develop` refuses steps that use them.
- The verdict comes first because the first lines are what reach your phone.

## An automation that arrives already written

A [plugin](../plugins/index.md) another stack offers, or one an agent in code-server wrote for
you, also waits in `ai/proposed/`, and is accepted with the same command. Moving a plugin file
into `notes/automations/` installs nothing.

## Changing or removing one

- Edit the spec in `notes/automations/` and `develop` offers a new version to install.
- To turn one off: `rm .decree/plugins/<name>.md && decree install`. Deleting the spec
  removes nothing.

## What it can do, and what to read first

- A built automation is a decree machine. The model writes only its `steps` function; the frame
  (`automation/lib/automations/run.sh`) gives it the triggering note or file, `ask` (one chat
  model answer), `web_search` and `web_read`, `curl` and `jq`.
- Steps that need you (pay, sign up, send, decide) come back under "For you".
- It runs unattended with access to your workspace and the stack's services. Read
  `ai/proposed/<name>.md` in code-server before you accept it.
- A name the stack ships is refused, so it can't replace an existing machine.
- `develop` uses Claude when the automation container is
  [signed in](../decree/decree.md#claude-for-machines), otherwise the chat model. Built automations can
  then hand a step to Claude too.
- Your notes are read-only to the automation container, so nothing it reads can rewrite them.
- For bigger automations, ask Claude in code-server instead.
