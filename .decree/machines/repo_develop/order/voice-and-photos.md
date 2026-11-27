---
machine: repo_develop
---
# Voice memos and photos become text beside them

## Overview

A voice memo is never played back; a photo of a whiteboard is never found again. What was
recorded or photographed becomes text next to it, where search and every agent find it.

## Outcome

- A file uploaded through Nextcloud (the phone app's auto-upload) starts every file processor
  whose `CRITERIA` match it: `file_processor` downloads it through the `nextcloud` rclone remote
  (`nextcloud_rclone_remote`, an order) and runs the processor.
- `transcribe`: WhisperX writes a transcript beside a recording, speakers labelled (a free
  HuggingFace token, which WhisperX's setup asks for). Needs a GPU.
- `ocr`: the vision model (`EXIST_MODEL_VISION`, at the model address) writes an image's text
  beside it. `ollama_pull` pulls a model by role, or rebuilds it with a context window, for a
  local Ollama.
- Guide: *Voice and Photos*; Technical: *File Processors*.

## Constraints

- A processor writes beside the file or under `workspace/ai/`, never over the original.
- A processor's `CRITERIA` are code in its plugin, changed in the repo, not the workspace.

## Acceptance Criteria

- **Given** `./existential.sh test file-handlers`
  **Then** it exits 0
- **Given** `./existential.sh validate conventions`
  **Then** it passes
