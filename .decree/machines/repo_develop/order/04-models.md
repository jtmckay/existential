---
machine: repo_develop
---
# One model address, whatever serves it; model choice is global

## Overview

A model may be a hosted LLM, ollama on this host, llama.cpp on another box or a controller
lending out a GPU host. Every caller has to work against any of them, and a person sets one
address, not one per service or role.

## Outcome

- **One address.** `EXIST_MODEL_URL` is this host's OpenAI-compatible `/v1` base URL (blank:
  no model yet), `EXIST_MODEL_KEY` its key (blank: the fleet secret), `EXIST_MODEL_CHAT` the
  model (blank: the first one the server lists). Every caller that sends a prompt (decree
  scripts, pi, opencode, OCR, the newsletter) speaks only `/v1`.
- **Ollama-only steps** (pulling, unloading, `/api/*`, its health probe) run only when ollama
  is enabled.
- **Decree scripts reach a model through `model_base`** (the `model` plugin's `lib/model.sh`:
  `model_chat`, `model_gate`), which leases the host whose offer lists the model and falls
  back to `EXIST_MODEL_URL`. pi is configured from the same address. No per-role or
  per-service address exists.
- **Model choice is global**: every model the stack uses is named once in `.env.exist.shared`'s
  Model Selection block; no service hardcodes a tag (an ollama order file names a role).
- **Values come from the VRAM tier table** (`src/utils/model-tiers.sh`); `EXIST_VRAM_GB` ships
  blank (not yet asked). Every tier tag has ollama's tools capability, is multimodal, and has
  at least 64k context. Tier `0` is CPU-only, and the generator's GPU-reservation strip keys
  off that exact value.
- **The hardware questions** (GPU vendor `nvidia`, `amd`, `none` or `external`; VRAM) wait for
  the first enabled service that reserves a GPU; Core never asks. `./existential.sh run
  models` asks again.
- **Existing installs keep working**: a value set under an old key name still takes effect.

## Constraints

- A unit test asserts the tier table and the shipped defaults agree, and that the resolvers
  agree (`src/test/unit/test-model-tiers.sh`, `test-model-client.sh`).

## Acceptance Criteria

- **Given** `EXIST_MODEL_URL` pointed at an OpenAI-compatible server with no `/api/*` routes
  **When** the OCR and newsletter paths run
  **Then** they get completions
- **Given** ollama disabled
  **When** the stack starts and decree's health checks run
  **Then** nothing probes or pulls from ollama
- **Given** `./existential.sh test unit`
  **Then** it exits 0
