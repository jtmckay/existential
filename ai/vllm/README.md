# VLLM

Useful for when you really want to use tools (Ollama does not support tools)

#### Opencode Config

Use the opencode.json.example\_ to see how to configure opencode to use vllm with opencode. Copy into or create the opencode.json file in ~/.config/opencode/ and then run Opencode to select a model.

#### I never got it to work through podman-compose but this direct podman call worked

```
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
