---
machine: develop
---
# Your notes are searchable by meaning and by exact words from the AI tools you use

## Overview

The person's notes, decisions and past prompts are only useful to an AI conversation if the AI
can find them, and the person rarely remembers the original wording. Search has to match a
paraphrase and an exact name, command or identifier in the same query, cite where it found
them, and work without anything to tune. It is optional infrastructure: when it is down,
nothing else is.

XERJ was evaluated first and not used: version 1.0.0-rc.98 indexed 26 of 152 Markdown files
with frontmatter as YAML with no body, failed a search across all indexes, and ships an MCP
tool that sends a report off the machine without asking. qmd met every requirement measured.

## Outcome

- **The service.** `ai/qmd` is an add-on (`EXIST_IS_AI_QMD`) running qmd, pinned in its
  image, on the `exist` network only, never published.
  - It indexes every `*.md` in the workspace, mounted read-only.
  - Hidden files, anything a workspace `.gitignore` ignores, and the globs in `QMD_IGNORE`
    are never searchable.
  - Index, config and model live in one rebuildable `qmd_cache` volume.
- **Neural search from the start.** It is on before the first search, with a local CPU model
  (embeddinggemma-300M) downloaded once.
- **Freshness.** An edit, new note, rename, delete or new ignore rule is reflected within one
  refresh (`QMD_REFRESH_SECONDS`, default 60), including after a restart.
- **Neural failure is loud.** When neural indexing fails:
  - qmd still answers keyword search;
  - its log says `NEURAL INDEX NOT READY` with the reason;
  - `./existential.sh run qmd test` fails.
- **Clients.** With `EXIST_SEARCH_MCP_URL` set, code-server's Claude Code and opencode both
  use the one index over MCP:
  - Claude Code's read-only qmd tools run without a prompt.
  - The `recall` skill is at `workspace/.claude/skills/recall/`.
  - With the URL blank, none of the three is present.
- **The recall skill tells the agent to:**
  - search when the person's context could change the answer, not on every message;
  - search with keywords and a plain-words question together, with reranking off;
  - rephrase and search again when results are thin;
  - read around a hit before relying on it, and cite file paths;
  - treat `ai/conversations/` as questions, not decisions;
  - never treat a missing result as proof, or a score as a confidence.
- **The eval.** `./existential.sh run qmd eval` measures keyword-only, neural-only and
  hybrid retrieval on a fixed fixture in a throwaway container, then checks exclusions and
  freshness.
- **Documentation.** `site/docs/ai/qmd.md` documents:
  - what is indexed and kept out;
  - the defaults and why, with the measured numbers;
  - other MCP clients, and where retrieval cannot reach;
  - rebuild, backup and model downloads;
  - resource use.

## Constraints

- qmd's own distribution (npm, pinned version); no fork and no custom retrieval code.
- No authentication exists on qmd's HTTP server, so it is reachable only from the `exist`
  network, and any other `Host` header is refused.
- No backend-only memory: knowledge stays in the person's Markdown files.
- No query or document text leaves the machine. The only outbound connection is the model
  download.
- Core does not depend on qmd: code-server reaches it only through `EXIST_SEARCH_MCP_URL`.

## Acceptance Criteria

- **Given** qmd running on the eval fixture
  **When** `./existential.sh run qmd eval` runs
  **Then** it exits 0, and hybrid finds every expected source in the top five for at least as
  many questions as keyword search alone
- **Given** a gitignored folder, a hidden folder and a dotfile each containing one word
  **When** that word is searched
  **Then** nothing is found
- **Given** an embedding model that cannot be downloaded
  **When** a refresh has run
  **Then** keyword search still answers, the log says `NEURAL INDEX NOT READY`, and
  `./existential.sh run qmd test` exits non-zero
- **Given** `EXIST_SEARCH_MCP_URL=http://qmd:8181/mcp`
  **When** code-server starts
  **Then** `claude mcp get qmd` names that URL, `settings.json` allows `mcp__qmd`, and
  `workspace/.claude/skills/recall/SKILL.md` exists
