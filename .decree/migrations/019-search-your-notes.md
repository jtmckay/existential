---
machine: develop
---
# Your notes are searchable by meaning and by exact words, from a terminal and from the AI tools you use

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
  - It indexes every `*.md` in the workspace, mounted read-only, and the text layer of
    every `*.pdf` and `*.docx`. A hit in one names the original file, and a PDF hit
    its page.
  - A PDF or Word file with no text (a scan; there is no OCR) or one that can't be
    read is logged as `not searchable` and counted by `./existential.sh run qmd test`,
    never silently skipped.
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
- **Clients.** With `EXIST_IS_AI_QMD=true`, code-server's Claude Code and opencode both
  use the one index over MCP:
  - Claude Code's read-only qmd tools run without a prompt.
  - The `recall` skill is at `workspace/.claude/skills/recall/`.
  - With the add-on off, none of the three is present. There is no second setting:
    the one switch turns search on everywhere.
- **A terminal command.** `search <words>` in code-server's terminal (with the add-on
  on) and `./existential.sh run qmd search <words>` on the host
  run the same hybrid search without MCP or an AI, print `path:line` and the passage
  for each hit, best first, and say when files are still keyword-only. An empty result
  says that it is not proof of absence.
- **The recall skill tells the agent to:**
  - search when the person's context could change the answer, not on every message;
  - search with keywords and a plain-words question together, with reranking off;
  - rephrase and search again when results are thin;
  - read around a hit before relying on it, and cite file paths;
  - treat `ai/conversations/` as questions, not decisions;
  - cite a PDF or Word hit by its original file and page;
  - never treat a missing result as proof, or a score as a confidence.
- **The eval.** `./existential.sh run qmd eval` measures keyword-only, neural-only and
  hybrid retrieval, and the `search` command's query, on a fixed fixture that includes a
  PDF, a Word file and a scanned PDF, in a throwaway container. Then it checks exclusions
  and freshness, for documents too.
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
- PDF and Word text comes from tools packaged in the qmd image and stays in `qmd_cache`;
  the workspace is never written to.
- No query or document text leaves the machine. The only outbound connection is the model
  download.
- Core works the same with qmd off: code-server wires search only when `EXIST_IS_AI_QMD`
  is true.

## Acceptance Criteria

- **Given** qmd running on the eval fixture
  **When** `./existential.sh run qmd eval` runs
  **Then** it exits 0, and hybrid finds every expected source in the top five for at least as
  many questions as keyword search alone
- **Given** a gitignored folder, a hidden folder and a dotfile each containing one word
  **When** that word is searched
  **Then** nothing is found
- **Given** a PDF and a `.docx` in the workspace, and a `.docx` in a gitignored folder
  **When** a refresh has run
  **Then** a word from each of the first two is found with the original file's path, and
  the third is neither found nor converted
- **Given** a PDF with no text layer
  **When** a refresh has run
  **Then** `docker logs qmd` names it as `not searchable` and `./existential.sh run qmd test`
  warns about it
- **Given** qmd running with notes indexed
  **When** `./existential.sh run qmd search <a word in a note>` runs
  **Then** it exits 0 and prints that note's `path:line`
- **Given** an embedding model that cannot be downloaded
  **When** a refresh has run
  **Then** keyword search still answers, the log says `NEURAL INDEX NOT READY`, and
  `./existential.sh run qmd test` exits non-zero
- **Given** `EXIST_IS_AI_QMD=true`
  **When** code-server starts
  **Then** `claude mcp get qmd` names `http://qmd:8181/mcp`, `settings.json` allows `mcp__qmd`,
  `workspace/.claude/skills/recall/SKILL.md` exists, and `search` is on the terminal's PATH
