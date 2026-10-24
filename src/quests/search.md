---
name: Search
tagline: Your notes, PDF and Word files, decisions and past prompts, searchable by meaning and by exact words, from a terminal or Claude Code and opencode
e2e: true
services:
  - var: EXIST_IS_AI_QMD
    label: qmd (hybrid keyword + neural search over the workspace, as MCP)
  - var: EXIST_IS_SERVICES_CODE_SERVER
    label: code-server (where Claude Code and opencode use it)
---

An add-on, not part of Core. qmd indexes every Markdown, PDF and Word file in
the workspace (text only: a scanned PDF has none, and there is no OCR) and
answers both kinds of search at once: exact words (names, commands,
identifiers) and meaning (a note you wrote in other words). Claude Code and
opencode in code-server share the one index over MCP. Nothing leaves the
machine, and no GPU is needed.

── 1. Enable and start ───────────────────────────────────────────────────

In .env.shared:

       EXIST_IS_AI_QMD=true

       ./existential.sh
       docker compose up -d --build qmd
       docker compose up -d --force-recreate code-server

The first start downloads the embedding model (about 320 MB) and indexes the
workspace: about a minute for 150 notes on a laptop CPU. After that, a saved
note is searchable within a minute.

── 2. Check it ───────────────────────────────────────────────────────────

       ./existential.sh run qmd test

It runs a keyword search and a meaning search and says whether every file has
its neural vectors. Until they do, those files are found by keyword only, and
the test (and `docker logs qmd`) says so.

── 3. Use it ─────────────────────────────────────────────────────────────

Ask Claude in code-server's terminal about something you wrote: "what did I
decide about syncing notes to my phone?". The recall skill in
workspace/.claude/skills/recall/ tells it when to search, how to phrase the
search, and to cite the file. It searches when your notes could change the
answer, not on every message.

Or search yourself, in code-server's terminal or on the host:

       search restic forget
       ./existential.sh run qmd search restic forget

Type the words you remember; a whole question finds less.

What you type into claude and opencode is kept in workspace/ai/conversations/,
so earlier questions are searchable too, marked as questions, not decisions.

What is in the index, what is kept out and how to change it:
site/docs/ai/qmd.md.
