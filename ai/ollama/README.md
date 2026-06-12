Create larger context models for Ollama

Create a `Modefile`
```
FROM gemma4:26b
PARAMETER num_ctx 128000
```

With ollama serve already running, execute
```bash
ollama create gemma4:26b -f Modelfile
```
