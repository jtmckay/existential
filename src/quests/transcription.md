---
name: Recording Transcription
tagline: Automatically transcribe audio and video recordings dropped into Nextcloud
e2e: false
services:
  - var: EXIST_IS_AI_WHISPERX
    label: WhisperX
  - var: EXIST_IS_NAS_NEXTCLOUD
    label: Nextcloud
  - var: EXIST_IS_SERVICES_AUTOMATION
    label: Decree
  - var: EXIST_IS_SERVICES_AUTOMATION_WEBHOOK
    label: automation-webhook (receives the POSTs)
done:
  files:
    - automation/lib/file-processors/whisperx-transcribe.sh
---

Drop a recording into Nextcloud and Decree transcribes it with WhisperX,
saving a speaker-labelled transcript next to the original file — no manual steps.

The pipeline:
  File synced to Nextcloud → Nextcloud file event
    → POST http://automation-webhook:8801/files  (27-nextcloud-file-events migration)
    → file-router matches PATTERN against the rclone path
    → whisperx-transcribe.sh: PATTERN='\.[Mm][Pp][34]$|\.[Ww][Aa][Vv]$'
    → IS_PRE_SIGNED=true — rclone generates a share link; WhisperX fetches it directly
    → whisperx-transcribe.ts submits /speech-to-text-url, polls /task/{id} until done
    → transcript saved to same rclone path + ".transcript.txt" suffix

Processor convention (whisperx-transcribe.sh):
  PATTERN              matches .mp3 .mp4 .wav (case-insensitive)
  IS_PRE_SIGNED        true — file is never downloaded locally; WhisperX gets the URL
  FILE_SUFFIX          transcript filename suffix (default: .transcript.txt)
  OUTPUT_RCLONE        rclone remote to write the transcript (default: nextcloud)
  WHISPERX_MODEL       override the whisper model (default: large-v3)
  WHISPERX_MIN_SPEAKERS / WHISPERX_MAX_SPEAKERS  diarization speaker bounds (optional)

Setup:
  1. Diarization needs a HuggingFace token. The WhisperX setup prompts for it
     (WHISPERX_HF_TOKEN); first accept the gated model terms while logged in:
       https://huggingface.co/pyannote/speaker-diarization-community-1

  2. File events must be on — the **Capture** quest does it. By hand: copy
     automation-examples/migrations/23-nextcloud-rclone-remote.md and
     27-nextcloud-file-events.md into volumes/workspace_data/.decree/migrations/. file-router and
     file-processor are enabled by default.

  3. Copy the processor in. Processor scripts are bind-mounted live into
     decree — no restart needed for this one:
       cp automation/lib/file-processors.example/whisperx-transcribe.sh \
          automation/lib/file-processors/

  4. Drop a recording into Nextcloud. The transcript appears in the same folder,
     named <filename>.mp3.transcript.txt, with each line prefixed by its speaker
     (e.g. "[SPEAKER_00] …"). Diarized runs take longer than plain transcription.

Logs for each run land in volumes/workspace_data/.decree/runs/ and are queryable in Grafana
via the Decree Overview dashboard.
