#!/bin/bash
set -e

echo "START Ollama server"
ollama serve &

# Keep the container running
wait
