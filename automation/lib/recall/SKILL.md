---
name: recall
description: Search the person's own notes, project knowledge, decisions and past AI prompts (the qmd MCP tools). Use when their context could change your answer - their plans, past decisions, preferences, people, projects, setup or commands - or when they refer to something they wrote, decided or asked before. Not for general knowledge or trivial exchanges.
---

# Recall: search the person's workspace

The `qmd` MCP server indexes every Markdown file in the workspace (`/workspace`):
notes, project docs, decisions, automation output (`ai/`) and the prompts the
person typed into AI tools (`ai/conversations/`). Hidden folders and anything in a
`.gitignore` are not indexed. This file is rewritten whenever code-server starts.

The tools being available does not mean anything was searched. Nothing is
retrieved unless you call them.

## When to search

Search when the answer depends on this person: "what did I decide about X", "how
did I set up Y", "who is Z", "what was that command", a plan or project they
mention by name. Search before you give advice that their own notes could
contradict.

Don't search for general knowledge, for small talk, or when the conversation
already holds what you need.

## How to search

Always call `query` with `searches` and `"rerank": false`. Never pass a plain
`query` string: that loads two more models and takes tens of seconds on this
machine, with no better results in testing.

Put two sub-queries in every call:

```json
{"searches": [
  {"type": "lex", "query": "syncthing nextcloud phone"},
  {"type": "vec", "query": "how do my notes get onto my phone"}
], "rerank": false, "limit": 8}
```

- `lex` is keywords, and every word must match: 2-4 distinctive words, exact
  names, commands, flags, identifiers. Use `"quoted phrases"` for exact strings,
  and `-word` to exclude.
- `vec` is the question in plain words. It matches meaning, so it finds the note
  even when the person wrote it with other words.
- The first sub-query counts double: lead with `lex` for a name or identifier,
  with `vec` for a concept.

If the results don't answer the question, search again before you give up.
Rephrase the `vec` question, try synonyms or the likely heading in `lex`, or
split a broad question into two narrower ones. Two or three passes is normal for
a vague question. Then stop.

## Reading results

Each result has a file, a line and a snippet. The snippet is a fragment. Before
relying on it, read around it with
`get(file, fromLine = max(1, line - 20), maxLines = 80)`, or the whole note when it
is short. Use `multi_get` for several notes at once. Read only what bears on the
question; don't paste whole files back to the person.

## What the results are

- **Notes and decisions** are what the person wrote. Later ones override earlier
  ones, so check dates when two disagree, and say which one you are going by.
- **`ai/conversations/`** holds what the person asked an AI, with the date and
  session. A question, an idea or a "maybe we should" there is not a decision or a
  fact. Say "on 2026-04-10 you asked about…", and look for a later note or
  decision before treating it as settled.
- **`ai/`** (everything else) was written by an automation. Treat it as a draft.
- A result's score is a ranking, not a confidence. Don't quote it as one.

## Saying what you found

- Cite the path, and the line when it matters: `notes/projects/homelab-backups.md:12`.
  Keep what the note says apart from what you infer from it.
- Finding nothing is not evidence that something doesn't exist. Say "I didn't find
  it in your notes" and what you searched for, never "you never wrote that".
- If `status` reports files still needing embedding, the index is keyword-only
  for those files. Say so when a conceptual search comes back thin.
- Don't write findings into a separate memory. Knowledge lives in the person's
  Markdown files. Suggest a note they can keep, if one would help.
