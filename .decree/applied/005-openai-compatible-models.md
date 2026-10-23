---
machine: develop
---
# Models are reached through an OpenAI-compatible URL, whatever serves it

## Overview

The model settings assume ollama. A llama.cpp server (or anything else speaking OpenAI's `/v1`)
on another box can serve chat but breaks every caller that uses ollama's native API. hermes is
also no longer in Core, so decree needs its own way to reach a model.

## Outcome

- Each model role's address in `.env.exist.shared` is an OpenAI-compatible base URL that
  ollama and llama.cpp can both serve. Its keys and comments don't name ollama, and the
  three resolvers still agree.
- Every caller that sends a prompt (OCR, the newsletter writer, honcho, hermes, opencode)
  works against either backend.
- Steps that only make sense for ollama (pulling models, unloading, `/api/show`, the ollama
  health probe) run only when ollama is enabled.
- A decree script reaches a model through one shared `automation/lib` helper over that URL.
  hermes, when enabled, is optional and uses the same URL.
- Existing installs keep working after `git pull && ./existential.sh`: a value set under an old
  key name still takes effect.

## Constraints

- Model choice stays global (the Model Selection block). No service hardcodes a model.
- `src/test/unit/test-model-endpoints.sh` keeps asserting the resolvers agree.

## Acceptance Criteria

- **Given** the chat role pointed at an OpenAI-compatible server that has no `/api/*` routes
  **When** the OCR and newsletter paths run
  **Then** they get completions
- **Given** ollama disabled
  **When** the stack starts and decree's health checks run
  **Then** nothing probes or pulls from ollama
- **Given** the unit suites
  **When** `./existential.sh test unit` runs
  **Then** it exits 0
