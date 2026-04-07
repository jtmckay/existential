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

## Opencode

Where you use opencode

```
# Don't use 1.3.2 (or vet any newer)
npm install -g opencode-ai@1.2.26
# Optional to stop autoupdate checks:
# echo 'export OPENCODE_DISABLE_AUTOUPDATE=true' >> ~/.bashrc

npm install -g typescript-language-server typescript
npm install -g pyright
# ESLint LSP if you want it as a server:
npm install -g vscode-langservers-extracted
```

Copy the `opencode.json` file to `~/.config/opencode/opencode.json`

### For 1000x better results, create a larger context model

##### Create a Modelfile

```
FROM gpt-oss:20b
PARAMETER num_ctx 32000
```

##### Build the variant

```
ollama create gpt-oss:20b-32k -f Modelfile
```

##### Point to it

Use the opencode.json.example\_ to see how to use the variant. Select it in opencode.
