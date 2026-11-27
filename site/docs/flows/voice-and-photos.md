---
sidebar_position: 6
---

# Voice and Photos

Voice memos never played back. A photo of a whiteboard you'll never find again. These turn what
you recorded or photographed into text beside it, where search and every agent can find it.

Both start from a file uploaded through Nextcloud, so set up
[files from your phone](./one-place.md#files-from-your-phone) first, and turn on your Nextcloud
phone app's **auto-upload** for the camera roll or your recordings folder.

## Voice memos you actually read

Record a voice memo. A transcript, with each speaker labelled, is saved beside it.

```bash
./existential.sh service on whisperx
./existential.sh plugin on transcribe
docker compose up -d
```

Speaker labels need a free HuggingFace token: accept the model's terms at
https://huggingface.co/pyannote/speaker-diarization-community-1, and WhisperX's setup asks for
the token. Needs a GPU: [WhisperX](../ai/whisperx.md).

## Photograph it, and the text is yours

Photograph a receipt, a whiteboard or a page. It syncs from your phone, and its text is saved
next to the image a few seconds later.

```bash
./existential.sh plugin on ocr
```

It reads with your vision model, `EXIST_MODEL_VISION`, at your model's address
([Configuration](../configuration.md#models)). With a local [Ollama](../ai/ollama.md),
`./existential.sh plugin on ollama_pull` pulls it. A scanner or a folder of old scans works too:
anything that writes into Nextcloud starts it.

How a file landing in Nextcloud becomes a job, and how to add your own step:
[File Processors](../plugins/file-change-processing.md).
