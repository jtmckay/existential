// Streams an audio file from a pre-signed S3 URL and transcribes it via Whisper.
// Called by the whisper-transcribe file processor. Outputs transcription text to stdout.
//
// Required env:
//   PRE_SIGNED_URL  — signed URL for the audio file (set by file-processor when IS_PRE_SIGNED=true)
//
// Optional env:
//   WHISPER_MODEL   — model name to pass to the API (omitted if empty, Whisper picks its default)

import { streamS3File } from "./streamS3File";

(async () => {
  const preSignedUrl = process.env.PRE_SIGNED_URL ?? "";
  const whisperModel = process.env.WHISPER_MODEL ?? "";

  if (!preSignedUrl) {
    console.error("PRE_SIGNED_URL is required");
    process.exit(1);
  }

  const { blob, contentType, filename } = await streamS3File(preSignedUrl);

  const file = new File([blob], filename, { type: contentType });

  const formData = new FormData();
  formData.append("file", file);
  if (whisperModel) formData.append("model", whisperModel);

  const res = await fetch("http://whisper:8000/v1/audio/transcriptions", {
    method: "POST",
    body: formData,
  });

  if (!res.ok) {
    const body = await res.text();
    console.error(`Whisper error (${res.status}): ${body}`);
    process.exit(1);
  }

  const data = (await res.json()) as { text: string };
  process.stdout.write(data.text);
})()
