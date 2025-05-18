# CUDA-accelerated PyTorch base - Latest compatible version as of May 2025
FROM nvcr.io/nvidia/pytorch:24.04-py3

# --- System deps including ffmpeg and moviepy dependencies ----------
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    curl \
    imagemagick \
    libmagick++-dev \
    python3-dev \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# --- Python deps ----------
# Install the latest NeMo ASR toolkit with specific PyTorch version constraint
RUN pip install --no-cache-dir torch==2.3.0 torchvision==0.18.0 torchaudio==2.3.0 --index-url https://download.pytorch.org/whl/cu121

# Install moviepy separately first with all dependencies to ensure proper installation
RUN pip install --no-cache-dir \
    decorator>=4.0.11 \
    imageio>=2.5.0 \
    imageio-ffmpeg>=0.4.2 \
    proglog>=0.1.9 \
    numpy \
    moviepy==1.0.3

# Install remaining dependencies
RUN pip install --no-cache-dir \
        "nemo_toolkit[asr]>=2.3.0" \
        "fastapi>=0.110.0" \
        "uvicorn[standard]>=0.29.0" \
        "soundfile>=0.12.1" \
        "python-multipart>=0.0.9" \
        "boto3>=1.33.0" \
        "python-dotenv>=1.0.0"

# Verify moviepy installation
RUN python -c "from moviepy.editor import VideoFileClip; print('MoviePy successfully installed')"

# --- Non-root user for safety ----------
RUN useradd -ms /bin/bash nemo

# Create cache directories with appropriate permissions
RUN mkdir -p /cache/huggingface /cache/torch /cache/matplotlib && \
    chown -R nemo:nemo /cache

# --- Pre-pull the Parakeet weights so first start is fast ----------
# Set environment variables for cache locations
ENV HF_HOME=/cache/huggingface \
    TORCH_HOME=/cache/torch \
    MPLCONFIGDIR=/cache/matplotlib

# Switch to nemo user before model download
USER nemo

# Use a try-except block for robustness in case the model name changes
RUN python - <<'PY'
import os
import nemo.collections.asr as nemo_asr

try:
    # Try to get the latest Parakeet model
    nemo_asr.models.ASRModel.from_pretrained(
        model_name="nvidia/parakeet-tdt-0.6b-v2",
        map_location="cpu"
    )
    print("Model pre-loaded successfully")
except Exception as e:
    print(f"Warning: Could not preload model: {e}")
    print("Model will be downloaded at runtime")
PY

WORKDIR /app

# --- REST micro-service ----------
COPY --chown=nemo:nemo app.py .

EXPOSE 8000
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
