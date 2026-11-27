---
machine: repo_develop
---
# One GPU in the stack, taken in turns; images from ComfyUI

## Overview

A single card can hold one GPU-heavy thing at a time. Ollama and ComfyUI on the same box take
turns instead of failing for lack of memory.

## Outcome

- `gpu_lease` is decree's `decree_lease` (`extends:`) with this stack's one resource, `gpu`: a
  lease in mode `llm` unloads ComfyUI's models first, one in `comfy` unloads ollama's. Up to four
  leases in the loaded mode share it; the other mode waits, nobody more than 30 minutes.
- `gpu_release`: a client outside the stack gives its lease back or renews it
  (`POST /gpu/lease/<id>/release|renew`).
- `comfy` generates an image or video in ComfyUI from a workflow binding in
  `lib/comfy/workflows/`, the message body as the prompt, under the lease (or another host's,
  through the fleet: [[fleet]]).
- Technical: *ComfyUI*, *Plugins*.

## Constraints

- decree's own plugin is never edited: only what changes is in `gpu_lease`.

## Acceptance Criteria

- **Given** `./existential.sh test comfy-workflows`
  **Then** it exits 0
- **Given** `./existential.sh test decree`
  **Then** it passes
