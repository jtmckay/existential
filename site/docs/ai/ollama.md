---
sidebar_position: 2
---

# Ollama

General AI model hosting.

- Source: https://github.com/ollama/ollama
- License: [MIT](https://opensource.org/licenses/MIT)
- Alternatives: vLLM, LocalAI, LM Studio

## Features

- **Simple Model Management**: One-command download and run from the Ollama model library
- **OpenAI-Compatible API**: Works as a drop-in backend for any OpenAI SDK or tool
- **GPU Acceleration**: Automatic CUDA/ROCm/Metal detection for hardware acceleration
- **Custom Models via Modelfile**: Extend base models with system prompts and context size tweaks
- **Concurrent Model Hosting**: Keep multiple models loaded and warm simultaneously
- **Embedding Support**: Generate embeddings for RAG and vector search workflows

## Pick Your LLM

In `ollama_entrypoint.sh`, uncomment the LLM you want to preload.

For GPU setup, see [Proxmox GPU](../hosting/proxmox#gpu).

## Pre-download Models

### Connect to running container

```bash
podman exec -it ollama sh
```

### Pull a model

```bash
ollama pull gpt-oss:120b
# ollama pull qwen3:8b
```

## Create a Larger Context Model

For 1000x better results with coding tools:

### Create a Modelfile

```
FROM gpt-oss:20b
PARAMETER num_ctx 32000
```

### Build the variant

```bash
ollama create gpt-oss:20b-32k -f Modelfile
```

## Opencode Integration

Ollama works with [opencode](https://opencode.ai) for AI-assisted coding.

```bash
# Install (avoid 1.3.2)
npm install -g opencode-ai@1.2.26
# Optional: disable autoupdate checks
# echo 'export OPENCODE_DISABLE_AUTOUPDATE=true' >> ~/.bashrc

# Language servers
npm install -g typescript-language-server typescript
npm install -g pyright
npm install -g vscode-langservers-extracted
```

Copy `opencode.json.example_` to `~/.config/opencode/opencode.json` and reference your model variant.
