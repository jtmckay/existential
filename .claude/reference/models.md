# Models: selection, endpoints, VRAM tiers

Three separate things, one rule each in `CLAUDE.md`. This is the why.

## Model selection is global

Every model the stack uses is named once, in `.env.exist.shared`'s *Model Selection* block:
`EXIST_MODEL_CHAT`, `_CHAT_NUM_CTX`, `_EXTRACT`, `_EMBED`, `_EMBED_DIM`, `_VISION`, `_STT`,
`_STT_LANGUAGE`, `_TTS_VOICE`.

Consumers read those keys rather than naming a tag themselves:

- ollama migrations name an `OLLAMA_ROLE`, never a tag
- honcho renders its `config.toml` from them
- the wyoming services take them as compose env

A hardcoded model tag in a service is a second place to edit when the user changes machines or
tiers, and the tier table below can no longer keep the stack consistent.

## Model addresses are per-role

`.env.exist.shared`'s *Model Endpoints* block gives each role its own key —
`EXIST_OLLAMA_URL_CHAT`, `_EXTRACT`, `_EMBED`, `_VISION` — each shipped **blank** and falling
back to `EXIST_OLLAMA_URL`. That blankness is the mechanism: leaving them empty means "one
ollama for everything", and filling one in moves that role to another machine. It is how VRAM
gets spread across hosts without touching a service.

Because the fallback chain matters, **never read a role key directly and never write your own
fallback**. There are exactly three resolvers, one per context:

| context | how to resolve |
|---|---|
| shell scripts | source `src/utils/model-endpoints.sh`, call `endpoint_for <role>` |
| rendered templates | write the bare token `EXIST_OLLAMA_URL_EMBED`; `src/templates.sh` resolves it before substitution |
| compose files | `${EXIST_OLLAMA_URL_<ROLE>:-${EXIST_OLLAMA_URL:-http://ollama:11434}}` |

Roles share `ollama-pull`'s `OLLAMA_ROLE` vocabulary, so a model is pulled to the machine that
actually serves it. Adding a role means touching all three resolvers —
`src/test/unit/test-model-endpoints.sh` asserts they agree, so a half-done role fails the suite.

**STT/TTS get no endpoint keys.** The wyoming services are CPU-only, so there is no VRAM to
spread, and Home Assistant is told where they live in its own UI.

## Values come from the VRAM tier table

`src/utils/model-tiers.sh` holds the table. Quest asks how much VRAM the machine has on first
run (after the GPU vendor question, and only when the answer was not *No GPU*);
`./existential.sh run models` re-asks later.

`.env.exist.shared` ships the **default tier's model values (8 GB)** but ships `EXIST_VRAM_GB`
**blank**. The blank is the record of not-yet-asked, and quest's picker fires only while it is
empty — shipping a value there makes the question unreachable forever. A unit test asserts both
that the shipped model values match the 8 GB tier and that `EXIST_VRAM_GB` is blank, so **edit
the table, not the individual defaults**.

Every tier tag must satisfy three constraints:

- **ollama's `tools` capability** — hermes cannot act without it.
- **multimodal** — so images reuse the already-resident model rather than loading a second one.
- **at least 64k context** — hermes requires 64,000 tokens and ollama truncates *silently*
  below it, which reads as the model ignoring instructions rather than as an error.

On the small tiers that KV cache spills into system RAM. That is a speed cost, not a correctness
one, so no tier is cut just to meet the floor.

The `0` tier is CPU-only, and `src/generate-compose.ts` keys its GPU-reservation strip off that
exact value — **do not renumber it**.
