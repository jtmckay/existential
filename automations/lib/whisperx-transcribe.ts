// Transcribes an audio file via WhisperX-FastAPI with speaker diarization and
// prints a speaker-labelled transcript to stdout. Called by the
// whisperx-transcribe file processor.
//
// WhisperX-FastAPI is asynchronous: POST the pre-signed URL to /speech-to-text-url
// (which runs the full transcribe → align → diarize pipeline), then poll
// /task/{id} until it completes. Diarization (pyannote) requires the service's
// HF_TOKEN to be set — without it the task fails.
//
// Required env:
//   PRE_SIGNED_URL        signed URL for the audio file (set by the file-processor)
//
// Optional env:
//   WHISPERX_URL          base URL (default http://whisperx:8000)
//   WHISPERX_MODEL        whisper model (default large-v3; match the service env)
//   WHISPERX_LANGUAGE     ISO 639-1 language hint (default en)
//   WHISPERX_MIN_SPEAKERS / WHISPERX_MAX_SPEAKERS  diarization speaker bounds
//   WHISPERX_TIMEOUT_SEC  max seconds to wait for the task (default 1800)
//   WHISPERX_POLL_SEC     poll interval in seconds (default 5)

type Segment = { start: number; end: number; text: string | null; speaker: string | null };

const env = process.env;
const base = (env.WHISPERX_URL ?? "http://whisperx:8000").replace(/\/$/, "");
const preSignedUrl = env.PRE_SIGNED_URL ?? "";
const model = env.WHISPERX_MODEL || env.WHISPER_MODEL || "large-v3";
const language = env.WHISPERX_LANGUAGE || "en";
const timeoutSec = Number(env.WHISPERX_TIMEOUT_SEC ?? 1800);
const pollSec = Number(env.WHISPERX_POLL_SEC ?? 5);

const sleep = (s: number) => new Promise((r) => setTimeout(r, s * 1000));

// Collapse consecutive same-speaker segments into one "[SPEAKER_xx] text" line.
function formatTranscript(segments: Segment[]): string {
  const lines: string[] = [];
  let speaker = "";
  let buffer: string[] = [];
  const flush = () => {
    if (buffer.length) {
      lines.push(`[${speaker || "SPEAKER_?"}] ${buffer.join(" ").replace(/\s+/g, " ").trim()}`);
    }
    buffer = [];
  };
  for (const seg of segments) {
    const text = (seg.text ?? "").trim();
    if (!text) continue;
    const who = seg.speaker ?? speaker; // null speaker → continuation of current
    if (who !== speaker) {
      flush();
      speaker = who;
    }
    buffer.push(text);
  }
  flush();
  return lines.join("\n");
}

(async () => {
  if (!preSignedUrl) {
    console.error("PRE_SIGNED_URL is required");
    process.exit(1);
  }

  // Kick off the async diarized pipeline. model/language/speaker bounds are query
  // params; the audio URL is the multipart form field.
  const qs = new URLSearchParams({ model, language });
  if (env.WHISPERX_MIN_SPEAKERS) qs.set("min_speakers", env.WHISPERX_MIN_SPEAKERS);
  if (env.WHISPERX_MAX_SPEAKERS) qs.set("max_speakers", env.WHISPERX_MAX_SPEAKERS);

  const form = new FormData();
  form.append("url", preSignedUrl);

  const submit = await fetch(`${base}/speech-to-text-url?${qs.toString()}`, {
    method: "POST",
    body: form,
  });
  if (!submit.ok) {
    console.error(`WhisperX submit error (${submit.status}): ${await submit.text()}`);
    process.exit(1);
  }
  const { identifier } = (await submit.json()) as { identifier?: string };
  if (!identifier) {
    console.error("WhisperX returned no task identifier");
    process.exit(1);
  }

  // Poll until the task finishes or we hit the timeout.
  const deadline = Date.now() + timeoutSec * 1000;
  while (Date.now() < deadline) {
    await sleep(pollSec);
    const poll = await fetch(`${base}/task/${identifier}`);
    if (!poll.ok) {
      console.error(`WhisperX poll error (${poll.status}): ${await poll.text()}`);
      process.exit(1);
    }
    const task = (await poll.json()) as {
      status: string;
      result?: { segments?: Segment[]; transcript?: { segments?: Segment[] } };
      error?: string;
    };

    if (task.status === "completed") {
      const segments = task.result?.segments ?? task.result?.transcript?.segments ?? [];
      process.stdout.write(formatTranscript(segments));
      return;
    }
    if (task.status === "failed") {
      console.error(`WhisperX task failed: ${task.error ?? "unknown error"}`);
      process.exit(1);
    }
    // queued | processing → keep polling
  }

  console.error(`WhisperX task ${identifier} did not finish within ${timeoutSec}s`);
  process.exit(1);
})();
