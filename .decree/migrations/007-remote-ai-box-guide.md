---
machine: develop
---
# A worked guide for a separate GPU box

## Overview

Many users keep their GPU models on a separate machine. The maintainer's own box is a good
worked example: one 24 GB card, rootless podman with NVIDIA CDI, llama.cpp in router mode, ComfyUI,
Qwen3-TTS, and a CPU GLiNER classifier. Only one GPU-heavy service fits at a time, so TTS is
started and stopped through that box's own decree REST endpoints.

## Outcome

- `site/docs/` has a guide to running a separate AI box and pointing the stack at it. It covers:
  - llama.cpp's router-mode command and presets, including why the V-cache type sits per model
    in the preset rather than on the command line
  - ComfyUI
  - TTS behind decree-go-rest `/startTTS` / `/endTTS`, run in tmux with the `tmx` pattern
  - which stack keys to set for each service
  - the VRAM rule: nothing swaps automatically
- The guide links from the hosting docs and the model-endpoints docs.

## Constraints

- No usernames, hostnames, IP addresses or paths under a home directory. Use `<ai-box>` and
  `~/` placeholders.
- Where a detail of the example box is unknown, the guide omits it rather than inventing it.
  Write the question to STOP if the guide can't be useful without it.

## Acceptance Criteria

- **Given** the docs site build
  **When** it runs
  **Then** it succeeds and the guide is reachable from the hosting docs
- **Given** the guide's text
  **When** it is searched for a username, IP address or `/home/` path
  **Then** none is found
