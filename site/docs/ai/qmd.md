---
service: ai/qmd
sidebar_position: 12
---

# qmd (search)

- Source: https://github.com/tobi/qmd
- License: [MIT](https://github.com/tobi/qmd/blob/main/LICENSE)
- Alternatives: XERJ, OpenViking, ripgrep

Search over everything you've written in the workspace, and the PDF and Word files you
keep there. One query matches both exact words (names, commands, flags, identifiers)
and meaning (a note you wrote in other words), and returns the file and line. Claude
Code and opencode in code-server share the one index over MCP, and a `search` command
reaches it from a terminal. It runs on the CPU, needs no GPU, and nothing leaves the
machine.

Your Markdown files stay the source of truth. The index is a copy that qmd rebuilds
from them, and nothing in this setup keeps knowledge anywhere else.

## Enable

In `.env.shared`, `EXIST_IS_AI_QMD=true`. Then `./existential.sh && docker compose up -d --build qmd`, and
`docker compose up -d --force-recreate code-server` so Claude Code and opencode pick it
up. `./existential.sh run qmd test` checks it. `./existential.sh quest` offers it as **Search**.

Search is optional. If qmd is down, or its model never downloaded, editing, capture and
every automation work as before. The only thing missing is search.

## Containers

| Container | Role |
|---|---|
| `qmd` | the index, a refresh loop, and the MCP server (Streamable HTTP on port 8181) |

## Access

- MCP: `http://qmd:8181/mcp` on the `exist` network. Not published to the host or the LAN.
- REST: `POST http://qmd:8181/query` (same body as the MCP `query` tool) and `GET /health`.
- Terminal: `search` in code-server, `./existential.sh run qmd search` on the host
  (see [From a terminal](#from-a-terminal)).

qmd's HTTP server has **no authentication**, which is why it is reachable only from
other containers. It also refuses any `Host` header other than `qmd:8181`
(`QMD_ALLOWED_HOSTS`), so a web page can't reach it through DNS rebinding.

## What is indexed

Every `*.md`, `*.pdf` and `*.docx` file under the workspace, except:

| Kept out | Why |
|---|---|
| hidden files and folders (`.decree/`, `.capture/`, `.claude/`, `.env`, `.git/`) | qmd never indexes them; secrets and app internals live there |
| anything a `.gitignore` in the workspace ignores, at any depth | the same rule that stops a file handler firing |
| `node_modules`, `vendor`, `dist`, `build`, `.cache` | qmd's built-in list |
| globs in `QMD_IGNORE` (`ai/qmd/.env`, comma-separated, relative to the workspace) | for things git tracks that search shouldn't |
| any other file type: images, `.doc`, spreadsheets, code files | not converted |
| a PDF with no text layer (a scan, a photo) | there is no OCR; the log says `not searchable` and `run qmd test` warns |

A `!pattern` in a `.gitignore` has no qmd equivalent: the path stays out of search, and
the container logs that it skipped the line. Rules are re-read on every refresh, so a new
ignore drops the files within a minute, and removing it brings them back.

Paths are shown to the agent with a short description of where they come from:

| Path | Described as |
|---|---|
| everything | the person's own notes, project knowledge and decisions |
| `ai/` | written by automations: drafts to check |
| `ai/conversations/` | prompts the person typed into an AI, dated: questions and ideas, not decisions |

## PDF and Word files

On each refresh, every PDF and `.docx` file the rules above allow is turned into text
under `qmd_cache/documents/`, one Markdown file per original at the same path plus
`.md`, and indexed as its own collection, `documents`. A PDF's pages become
`## Page N` headings, so a hit says which page; a Word file keeps its headings, lists
and tables. Images are dropped. pdftotext (poppler) reads PDFs and mammoth reads Word
files, both inside the qmd container.

- Only the text layer is read. A scanned PDF has none: it is recorded as
  `<path>.md.none`, logged once as `not searchable`, and counted by `run qmd test`.
  An encrypted or damaged file is recorded the same way.
- A file is converted again only when its modification time changes, so an unchanged
  library costs nothing per refresh. Renaming, deleting or ignoring the original
  removes its text.
- The agent sees these results as `qmd://documents/<path>.md` with the original path
  in the text, and is told to cite the original file and page. Line numbers count
  lines of the extracted text, not of the PDF.
- Converted text is a copy, like the index: deleting `qmd_cache` rebuilds it.

## Conversations

What you type into `claude` or `opencode` (with capture on, the default) is appended to
`workspace/ai/conversations/<date>-<tool>-<session>.md`: one file per session per day,
with the session id, date and working directory in its frontmatter. Each prompt is a
quote under its timestamp. Only your prompts are kept, never the AI's answers, and
secrets are redacted first. The raw stream stays in `workspace/.capture/`
(see [Capture](../getting-started#capture)).

## How search behaves

The recall skill tells the agent to send every search as two parts, keywords (`lex`) and
the question in plain words (`vec`), with reranking off. qmd fuses the two lists with
reciprocal-rank fusion. There is nothing to tune.

| Setting | Default | Why |
|---|---|---|
| Embedding model | embeddinggemma-300M (Q8, 320 MB, CPU) | the best recall in our tests at the lowest cost; see below |
| Hybrid keyword + neural | on | together they found every expected source; each alone missed some |
| Reranking (Qwen3-Reranker-0.6B) | off | no better results in our tests (20/21 against 21/21), ~19 s a query on CPU, 2.6 GiB |
| Query expansion (a 1.7B model rewriting the query) | off | the agent writes its own alternative searches instead |

qmd's own MCP default is reranking **on**, and a plain-text `query` also turns on
expansion. That is why the skill always sends `searches` with `"rerank": false`. A
client that does otherwise still gets correct results, but loads two more models
(about 1.7 GB, downloaded on first use), uses up to 4.6 GiB of memory and waits tens of
seconds per query.

Markdown is split into chunks of about 900 tokens with 15% overlap, preferring heading
and paragraph boundaries and never splitting inside a code fence (qmd's documented
behaviour). A hit gives the file and line; `get` reads the lines around it, and
`multi_get` reads whole notes.

**What is not supported:** following `[[wikilinks]]` or links between notes (a link's
text is still searchable by keyword), OCR, and a confidence score. The score on a
result is a ranking only.

## From a terminal

No MCP and no AI needed:

```bash
search restic forget            # in code-server's terminal
./existential.sh run qmd search restic forget      # on the host
```

It prints the best passage from each of the ten best files, best first, each as `path:line` (relative to the
workspace; in code-server, a click opens the file) and the lines around the hit. A PDF
or Word hit shows the original file, and a PDF hit its page. The command sends what you type as both the
keyword and the meaning search, so **type the words you remember**: that found every
expected source on 24 of 25 test questions. A whole question works too, but its keyword
half only helps when every word of it is in the note, so it found 21 of 25, the same
as meaning alone (see [Measured](#measured)). If files are still waiting for their
neural index, it says so first. The meaning half always ranks something, so a word
that is in no note still lists the nearest ones: read the passage, not just the path.
Finding nothing does not mean it isn't there: try other words.

A coding agent on the host with no MCP set up can run the same command.

## Using it from AI tools

**Claude Code** in code-server: with `EXIST_IS_AI_QMD=true`, code-server's
entrypoint registers the server (`claude mcp add --transport http --scope user qmd …`),
allows its read-only tools without a prompt (`mcp__qmd` in `settings.json`), and copies
the recall skill to `workspace/.claude/skills/recall/`. Turn the add-on off and recreate
code-server to remove all three.

**opencode** in code-server gets the same server as a `remote` MCP entry in the config
code-server writes.

**The tool being available does not mean it is used.** Claude searches when the skill's
description matches the conversation: questions about your plans, decisions, people,
projects or setup. It doesn't search on every message. Ask "check my notes" when you
want it to.

**Other MCP clients** that run in a container on the `exist` network can point at
`http://qmd:8181/mcp` (Streamable HTTP, stateless). Untested: a client on the host or
another machine needs the port published (`ports: ["127.0.0.1:8181:8181"]` in
`ai/qmd/docker-compose.yml`) and `QMD_ALLOWED_HOSTS` set to the host name it uses. That
is a network path to an unauthenticated server, so keep it on loopback or put
authentication in front of it.

**Apps with no MCP or tool support** (a chat website, a phone app) can't use it. Nothing
here changes what they see.

**Decree**: no step in the workspace's decree project calls Claude: scripts reach
models through `automation/lib/model.sh`. A step that should always start from your notes
fetches them itself before its model call, so retrieval doesn't depend on a model
deciding to search:

```bash
curl -s http://qmd:8181/query -H 'Content-Type: application/json' -d "$(jq -n --arg l "$KEYWORDS" --arg v "$QUESTION" \
  '{searches: [{type: "lex", query: $l}, {type: "vec", query: $v}], limit: 5, rerank: false}')" \
  | jq -r '.results[] | "\(.file):\(.line)\n\(.snippet)\n"'
```

No shipped machine does this yet.

## Operations

| | |
|---|---|
| Freshness | a refresh every `QMD_REFRESH_SECONDS` (60) re-reads the ignore rules, indexes what changed and embeds what's new. An edit, new note, rename, delete or new ignore rule is searchable within one refresh. |
| Restart | the index persists; changes made while qmd was down are picked up on the first refresh |
| Rebuild | `docker compose stop qmd && rm -rf volumes/qmd_cache && docker compose up -d qmd`. Everything is rebuilt from the workspace. |
| Backup | not needed: `qmd_cache` holds only the index, its config, the model and the text taken from PDF and Word files. Back up the workspace. |
| Model download | on first start, from huggingface.co, into `qmd_cache`; never again unless the model changes or the cache is deleted. A failed download is retried every refresh. |
| Neural index not ready | `docker logs qmd` says `NEURAL INDEX NOT READY` with the reason, `run qmd test` fails, and qmd's `status` tool reports files needing embedding. Those files are found by keyword only until the model loads. Keyword-only search is never labelled neural. |
| Changing model | set `QMD_EMBED_MODEL` in `ai/qmd/.env` to an `hf:` GGUF URI and recreate qmd. The next refresh re-embeds everything, since vectors of two models can't be mixed. |
| Upgrading qmd | the version is pinned in `ai/qmd/Dockerfile`. qmd migrates its own index schema; if an upgrade goes wrong, delete `qmd_cache` and let it rebuild. |
| Telemetry | none: qmd sends nothing. Its only outbound connection is the model download. |

## Measured

`./existential.sh run qmd eval` repeats these measurements on your machine. It indexes a
fixed fixture (personal notes with a long runbook, code blocks, an AI conversation and
the later decision about it, a PDF manual, a Word policy and a scanned PDF) plus this
repo's docs as distractors, 159 files in all. It asks 25 questions: exact names and
commands, paraphrases with little word overlap, history versus later decisions,
multi-source, and four answered only by the PDF or the Word file. Then it checks
exclusions (including a gitignored Word file, which is never converted) and freshness
(including a renamed PDF and a deleted Word file). Measured on an 8-core laptop CPU,
no GPU:

| Search | Best match first | Every expected source in top 5 | Per query |
|---|---|---|---|
| keyword only | 22/25 | 22/25 | 6 ms |
| neural only | 14/25 | 21/25 | 75 ms |
| **hybrid (the agents' default)** | **22/25** | **25/25** | **24 ms** |
| `search` command, keywords typed | 22/25 | 24/25 | 22 ms |
| `search` command, the question typed | 13/25 | 21/25 | 25 ms |

Sending each word of a typed question as its own keyword search, to get around the
every-word rule, found less (18/25), so the command doesn't.

Cost: 270 to 630 MiB of memory with the model loaded, a 1.7 GB image (poppler and
mammoth add about 12 MB), a 320 MB model and a 5 MB index for those 159 files. The first
index took about 50 s once the model was downloaded.

Two alternatives were measured on a similar set and not adopted:

- **Qwen3-Embedding-0.6B** put the best match first more often (12/20 against 8/20), but
  found every expected source in the top five less often (18/20 against 20/20). It also
  used twice the memory and disk and was three times slower per query. The agent reads
  several results, so the default stays embeddinggemma.
- **Reranking** (`QMD_EVAL_RERANK=1 ./existential.sh run qmd eval`), on the 21
  questions before PDF and Word support, found every expected source on 20/21
  against hybrid's 21/21. It took about 19 s per query and
  2.6 GiB of memory, against 24 ms for hybrid alone. It added nothing on the earlier
  set either.

These are small hand-made sets: they catch regressions and gross differences, not
fine ones.
