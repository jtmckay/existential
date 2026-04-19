---
sidebar_position: 5
---

# vLLM

- Source: https://github.com/vllm-project/vllm
- License: [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0)
- Alternatives: Ollama, Text Generation Inference, TensorRT-LLM

Useful for when you need full tool-calling support (Ollama does not support tools).

## Features

- **High-Throughput Serving**: PagedAttention memory management for maximum GPU utilization
- **OpenAI-Compatible API**: Drop-in replacement for the OpenAI inference endpoint
- **Full Tool/Function Calling**: Structured tool use that Ollama lacks
- **Quantization Support**: BitsAndBytes, AWQ, and GPTQ for fitting large models on consumer GPUs
- **Multi-GPU Tensor Parallelism**: Split large models across multiple GPUs
- **HuggingFace Integration**: Load any compatible model directly from the Hub

## Direct Podman Run

```bash
alias vllm='podman run -d \
  --name vllm \
  --device nvidia.com/gpu=all \
  --security-opt=label=disable \
  -p 48030:8000 \
  -v ~/hf-cache:/root/.cache/huggingface \
  -e HF_TOKEN=your_hf_token_here \
  vllm/vllm-openai:gemma4-cu130 \
  /root/.cache/huggingface/gemma-4-E4B-it \
  --host 0.0.0.0 \
  --served-model-name gemma-4 \
  --gpu-memory-utilization 0.8 \
  --max_num_seqs 1 \
  --max-model-len 64000 \
  --quantization bitsandbytes \
  --load-format bitsandbytes \
  --dtype auto \
  --enable-auto-tool-choice \
  --tool-call-parser gemma4 \
  --trust-remote-code'
```

## Opencode Config

Copy `opencode.json.example_` to `~/.config/opencode/opencode.json` to configure opencode to use vLLM, then run Opencode and select a model.
