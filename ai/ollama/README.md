# Ollama

### Pick your LLM

In the `ollama_entrypoint.sh` uncomment the LLM you want to preload.

See GPU install under [Proxmox](../../hosting/proxmox/README.md#gpu)

#### Pre-download models
##### Remote shell
`podman exec -it ollama sh`
##### Pull
`ollama pull gpt-oss:120b`
<!-- Other options -->
<!-- ollama pull qwen3:8b -->
