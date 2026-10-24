---
machine: e2e_search
e2e_check: 30-search
requires: EXIST_IS_AI_QMD
---

A note written in the workspace → qmd's refresh → found by keyword and by
meaning, over the same MCP protocol Claude Code and opencode use, and by the
`search` command.

Each service's own test proves qmd answers. What it cannot prove is the
property the person relies on: something written a minute ago is already
findable, from whichever tool they are in. So this writes a fresh note and
waits for it, the way a person would, then asks for it four ways:

- **keyword**, by a token that exists nowhere else;
- **meaning**, by a question that shares almost no words with the note, once
  qmd reports every file embedded (the first boot downloads the model). A
  second note on another subject is written alongside, and each must rank
  first for its own question, so the nearest note is not trivially the only one;
- **MCP**, the protocol Claude Code and opencode speak to it: `initialize`,
  `tools/list` offering `query` and `get`, then `get` returning the note;
- **the `search` command** code-server puts on PATH, run from the repo's
  `lib/recall/search.sh`, which must print the note's path.

That code-server's Claude Code is registered with qmd, allows its tools and has
the recall skill is code-server's own `exist.test.sh`, run by `00-services`.
