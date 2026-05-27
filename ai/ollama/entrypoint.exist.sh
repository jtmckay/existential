#!/bin/bash
set -e

echo "START Ollama server"
# Start the server
ollama serve &

sleep 2

# echo "PULL deepseek-r1:1.5b model"
# ollama pull deepseek-r1:1.5b

# echo "PULL deepseek-r1:7b model"
# ollama pull deepseek-r1:7b

# echo "PULL deepseek-r1:8b model"
# ollama pull deepseek-r1:8b

# echo "PULL deepseek-r1:14b model"
# ollama pull deepseek-r1:14b

# echo "PULL deepseek-r1:32b model"
# ollama pull deepseek-r1:32b

# echo "PULL deepseek-r1:70 model"
# ollama pull deepseek-r1:70

# echo "PULL llama3.2:latest model"
# ollama pull llama3.2:latest

# echo "PULL llama3.2-vision:latest model"
# ollama pull llama3.2-vision:latest

# Gemma doesn't support tools, but it is a very small model for low VRAM envs
# echo "PULL gemma3n:e4b model"
# ollama pull gemma3n:e4b

# echo "PULL qwen3.5:4b model"
# ollama pull qwen3.5:4b

# echo "PULL qwen3.5:9b model"
# ollama pull qwen3.5:9b

# echo "PULL gpt-oss:20b mode"
# ollama pull gpt-oss:20b
# ollama create gpt-oss:20b-32k -f /root/Modelfile

# echo "PULL gpt-oss:120b model"
# ollama pull gpt-oss:120b

# echo "PULL deepseek-coder:6.7b"
# ollama pull deepseek-coder:6.7b
# ollama create deepseek-coder:6.7b-5k -f /root/Modelfile

# echo "PULL deepseek-coder-v2:16b"
# ollama pull deepseek-coder-v2:16b

# echo "PULL deepseek-coder-v2:16b"
# ollama pull deepseek-coder-v2:16b

echo "PULL gemma4:e2b model"
ollama pull gemma4:e2b

# echo "PULL gemma4:26b model"
# ollama pull gemma4:26b

# echo "PULL nomic-embed-text model for RAG embeddings"
# ollama pull nomic-embed-text

# Keep the container running
wait
