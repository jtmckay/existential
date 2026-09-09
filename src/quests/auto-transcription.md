---
name: Recording Transcription
tagline: Automatically transcribe audio and video recordings dropped into Nextcloud
e2e: false
services:
  - var: EXIST_IS_AI_WHISPERX
    label: WhisperX
  - var: EXIST_IS_NAS_SEAWEEDFS
    label: SeaweedFS
  - var: EXIST_IS_NAS_NEXTCLOUD
    label: Nextcloud
  - var: EXIST_IS_SERVICES_AUTOMATION
    label: Decree
---

Drop a recording into Nextcloud and Decree transcribes it with WhisperX,
saving a speaker-labelled transcript next to the original file — no manual steps.

The pipeline:
  File synced to Nextcloud → seaweedfs file event
    → POST http://automation-webhook:8801/s3  (pre-configured in notification.toml)
    → s3-router matches PATTERN against the rclone path
    → whisperx-transcribe.sh: PATTERN='\.[Mm][Pp][34]$|\.[Ww][Aa][Vv]$'
    → IS_PRE_SIGNED=true — rclone generates a signed URL; WhisperX fetches it directly
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

  2. Enable the routines in services/automation/decree/config.yml:
       file-processor:
         enabled: true
       s3-router:
         enabled: true

  3. Copy the processor in. Processor scripts are bind-mounted live into
     decree — no restart needed for this one:
       cp automation/lib/file-processors.example/whisperx-transcribe.sh \
          automation/lib/file-processors/

  4. Restart decree to pick up config changes:
       docker compose restart automation

  5. Nothing to subscribe. The webhook is declared once in
     nas/seaweedfs/notification.toml and read at boot, and it already covers the
     whole nextcloud bucket:
       endpoint      = "http://automation-webhook:8801/s3"
       path_prefixes = ["/buckets/nextcloud"]

     Using a DIFFERENT bucket? Add it to path_prefixes and restart seaweedfs —
     that file is the only place a bucket is subscribed.

  7. Drop a recording into Nextcloud. The transcript appears in the same folder,
     named <filename>.mp3.transcript.txt, with each line prefixed by its speaker
     (e.g. "[SPEAKER_00] …"). Diarized runs take longer than plain transcription.

Logs for each run land in automation/runs/ and are queryable in Grafana
via the Decree Overview dashboard.
