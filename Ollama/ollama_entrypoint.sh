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

echo "PULL deepseek-r1:8b model"
ollama pull deepseek-r1:8b

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

# Keep the container running
wait
