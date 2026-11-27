---
sidebar_position: 2
---

# Pick Up the Thread

You had it all in your head on Tuesday. By Friday the thread is gone, and the note that held it
is somewhere. These bring it back to you, without you having to go looking.

## Where you were, every morning

**On by default.** At seven your phone shows yesterday in one notification, and the whole of it
is in `workspace/ai/you-were-here.md`:

- **The picture**: two or three sentences.
- **Waiting on you**: at most three things, and **one next thing**.
- **Where you left off**: the last thing you said in each conversation with an agent, by project
  (with [Capture](./one-place.md#everything-you-typed-to-an-ai) on).
- **Holding steady**: the routines that ran fine, so you don't have to check.
- **From your feeds**: three to five new items close to what you're working on, if
  `workspace/notes/feeds.md` lists feeds.
- **Worth learning**: one encyclopedia article on a subject you keep coming back to, never the
  same one twice. Only the subject is sent to Wikipedia.

Every claim links to the note it came from. Each day is kept, never rewritten, in
`workspace/ai/you-were-here/<year>/<date>.md`. Without a model it still writes the parts built
from your files. A day with nothing new sends nothing.

```bash
./existential.sh plugin off you_were_here     # if you'd rather not
```

## What did I even do this year?

A summary of the week every Sunday evening and of the month on its last evening, saved next to
the daily notes: what you finished, what kept coming up, what you decided, each linked to the
day it happened. A week with nothing in it sends nothing.

```bash
./existential.sh plugin on look_back
```

Ask for any range from code-server's terminal:

```bash
echo | decree emit --machine look_back --param period=year
```

`period` is `week`, `month`, `quarter` or `year`; `from` and `to` (`YYYY-MM-DD`) set either end.
To see only work, list your work projects and folders in `workspace/ai/you-were-here/scope.md`
and add `--param scope=work`.

## Notes that find their own connections

You write something down, not knowing you solved the same problem three weeks ago. Each new note
is checked against everything you already wrote; when it connects to an earlier one, the
connection is written beside it and your phone says so.

```bash
./existential.sh plugin on note_connect
```

The first run marks what you already have as seen, so turning it on over a big vault doesn't
fire a call per note. To check the backlog once:
`echo | decree emit --machine note_connect --param CONNECT_BOOTSTRAP=true`.

## Ask what you decided

Search is part of Core. Ask Claude in code-server *"what did I decide about syncing my notes?"*
and it searches your notes, PDFs and Word files, by meaning and by exact words, and answers with
the file and line. Nothing to turn on: [qmd](../ai/qmd.md).
