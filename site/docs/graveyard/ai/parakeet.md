---
sidebar_position: 6
---

# Parakeet ASR

- Source: https://github.com/NVIDIA/NeMo
- License: [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0)
- Alternatives: Whisper, Speaches, faster-whisper
- Status: TBD
- Model: NVIDIA Parakeet-TDT 0.6B

GPU-accelerated speech-to-text built on NVIDIA's Parakeet-TDT model.

## Features

- **High-Quality Transcription**: NVIDIA Parakeet-TDT 0.6B model
- **REST API**: Simple HTTP interface for audio transcription
- **GPU Acceleration**: Optimized for NVIDIA GPUs, falls back to CPU
- **S3 Integration**: Transcribe audio files directly from S3/MinIO

## API

### Health Check

```
GET /
```

### Transcribe Audio

```
POST /transcribe
```

```bash
curl -X POST -F "file=@audio.wav" http://localhost:8000/transcribe
```

### Transcribe from S3

```
POST /transcribe-s3
```

```json
{
  "bucket": "my-audio-bucket",
  "key": "recordings/meeting.mp4",
  "endpoint_url": "http://minio:9000"
}
```

## Configuration

| Variable | Description |
|---|---|
| `TRANSCRIBE_DEVICE` | `cuda` or `cpu` |
| `S3_ENDPOINT` | S3/MinIO URL |
| `S3_ACCESS_KEY` | S3 access key |
| `S3_SECRET_KEY` | S3 secret key |
