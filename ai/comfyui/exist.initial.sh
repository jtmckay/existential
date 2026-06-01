#!/usr/bin/env bash
# ComfyUI — first-time setup
set -euo pipefail

echo ""
echo "  ComfyUI setup"
echo "  ─────────────────────────────────────────────────────────────"
echo ""
echo "  ComfyUI runs a node-based image generation UI at https://comfyui.internal"
echo "  after containers are up."
echo ""
echo "  To get started:"
echo "    1. Start containers:  docker compose up -d"
echo "    2. Open https://comfyui.internal in your browser"
echo "    3. Download a model (e.g. SDXL) via the ComfyUI Manager node,"
echo "       or place .safetensors files in the comfyui_data volume at:"
echo "         /workspace/ComfyUI/models/checkpoints/"
echo ""
