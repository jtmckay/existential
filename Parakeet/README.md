# Parakeet ASR Service

A lightning-fast, GPU-accelerated speech-to-text service built on NVIDIA's Parakeet-TDT (Transducer with Duration and Timing) model.

## Overview

This service provides a REST API for transcribing audio files to text using NVIDIA's Parakeet-TDT 0.6B model, a state-of-the-art ASR (Automatic Speech Recognition) system. It's designed to run efficiently on NVIDIA GPUs but can also operate on CPU if needed.

## Features

- **High-Quality Transcription**: Powered by NVIDIA's Parakeet-TDT 0.6B model
- **REST API**: Simple HTTP interface for audio transcription
- **GPU Acceleration**: Optimized for NVIDIA GPUs (fallbacks to CPU if unavailable)
- **Docker Container**: Easy deployment with Docker Compose
- **File Format Support**: Accepts WAV, FLAC, and other common audio formats

## Getting Started

### Prerequisites

- Docker and Docker Compose
- NVIDIA GPU with CUDA support (recommended, but not required) [GUIDE](../Proxmox/README.md#gpu)
- NVIDIA Container Toolkit (for GPU support)

### Installation

1. Clone this repository or navigate to the Parakeet directory
2. Start the service using Docker Compose:

```bash
cd Parakeet
docker compose up -d
```

The service will automatically download the model on first startup, which may take a few minutes depending on your internet connection.

### API Endpoints

#### Health Check

```
GET /
```

Returns basic information about the service status.

Example response:
```json
{
  "status": "ok",
  "model": "parakeet-tdt-0.6b-v2",
  "device": "cuda"
}
```

#### Transcribe Audio

```
POST /transcribe
```

Upload an audio file to be transcribed.

**Parameters**:
- `file`: The audio file to transcribe (multipart/form-data)

**Example request using curl**:
```bash
curl -X POST -F "file=@your-audio-file.wav" http://localhost:8000/transcribe
```

**Example response**:
```json
{
  "text": "This is the transcribed text from your audio file."
}
```

#### Transcribe Audio from S3

```
POST /transcribe-s3
```

Transcribe an audio file stored in an S3 bucket or MinIO instance.

**Request Body**:
```json
{
  "bucket": "your-bucket-name",
  "key": "path/to/your-audio-file.mp4",
  "region": "us-east-1",  // optional
  "endpoint_url": "http://minio:9000",  // optional, for MinIO or other S3-compatible services
  "credentials": {        // optional
    "access_key": "YOUR_AWS_ACCESS_KEY",
    "secret_key": "YOUR_AWS_SECRET_KEY",
    "session_token": "YOUR_AWS_SESSION_TOKEN"  // optional
  }
}
```

**Example request using curl**:
```bash
curl -X POST http://localhost:8000/transcribe-s3 \
  -H "Content-Type: application/json" \
  -d '{
    "bucket": "my-audio-bucket",
    "key": "recordings/interview.mp4"
  }'
```

**Example response**:
```json
{
  "text": "This is the transcribed text from your S3 audio file."
}
```

**Supported Formats**:
- Audio: WAV, MP3, FLAC, OGG, AAC, M4A
- Video: MP4, AVI, MKV, MOV, WebM (audio will be extracted automatically)

## Performance Considerations

- The first transcription may take longer as the model warms up
- GPU transcription is significantly faster than CPU
- Audio quality affects transcription accuracy
- The model works best with clean audio, minimal background noise, and clear speech

## Configuration

The service can be configured via environment variables in the `docker-compose.yml` file or by creating a `.env` file based on the provided `.env.example`:

- `NVIDIA_VISIBLE_DEVICES`: Controls which GPUs are available to the container
- `TRANSCRIBE_DEVICE`: Set to "cuda" for GPU or "cpu" for CPU processing
- `S3_ENDPOINT`: URL for S3-compatible service (e.g., "http://minio:9000" for local MinIO)
- `S3_ACCESS_KEY`: Access key for S3/MinIO authentication
- `S3_SECRET_KEY`: Secret key for S3/MinIO authentication
- `S3_REGION`: Optional region name for S3 (can be empty for MinIO)

### Using with MinIO

This service can use a local MinIO instance for S3 storage. To configure:

1. Copy `.env.example` to `.env` and update with your MinIO credentials:
```bash
cp .env.example .env
# Edit .env with your preferred editor
```

2. If MinIO is running in the same Docker network, you can use the service name as the hostname:
```
S3_ENDPOINT=http://minio:9000
```

3. When calling the `/transcribe-s3` endpoint, you can either:
   - Use the environment variables configured in the `.env` file
   - Override the endpoint in your request with the `endpoint_url` parameter

Example with endpoint override:
```json
{
  "bucket": "audio-files",
  "key": "recordings/meeting.mp3",
  "endpoint_url": "http://localhost:9000"
}
```

## Troubleshooting

If you encounter issues:

1. Check if the container is running: `docker ps | grep parakeet`
2. View logs for errors: `docker logs parakeet-asr`
3. Ensure GPU is properly configured (if using GPU acceleration)
4. Verify that your audio file is in a supported format

## Technical Details

- **Base Model**: NVIDIA Parakeet-TDT 0.6B
- **Framework**: NeMo Toolkit, PyTorch
- **API**: FastAPI
- **Container**: NVIDIA PyTorch container with CUDA support
- **Audio Processing**: SoundFile, TorchAudio

## License

This project uses NVIDIA's Parakeet model which is subject to NVIDIA's license terms. Please refer to NVIDIA's licensing for the model usage.
