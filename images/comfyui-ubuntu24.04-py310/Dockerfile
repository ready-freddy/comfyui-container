# Ubuntu 24.04 + CUDA 12.8 runtime + Python 3.12
FROM nvidia/cuda:12.8.0-cudnn-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1 \
    RUNPOD_VENV=/workspace/.venvs/comfyui-perf \
    COMFY_PATH=/workspace/ComfyUI \
    COMFY_HOST=0.0.0.0 \
    COMFY_PORT=3000

# Runtime deps + minimal build toolchain for insightface (g++, headers)
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common ca-certificates curl git git-lfs \
    libgl1 libopengl0 libglib2.0-0 libsm6 libxext6 libxrender1 \
    libgtk-3-0 ffmpeg unzip p7zip-full wget \
    build-essential python3-dev \
 && rm -rf /var/lib/apt/lists/*

# Python 3.12 (Ubuntu 24.04 default) — matches your existing venv
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-venv python3-distutils \
 && rm -rf /var/lib/apt/lists/*

# Non-root user + writable workspace
RUN useradd -m -s /bin/bash comfy || true && \
    mkdir -p /workspace && chown -R comfy:comfy /workspace
USER comfy
WORKDIR /workspace

# Open ComfyUI ports + (optionally) keep 3001 for manual alternatives
EXPOSE 3000 3001 8675

# Entrypoint: hands off to your mounted venv + ComfyUI
# NOTE: path stays the same as your repo; the file contents can stay as-is
COPY images/comfyui-ubuntu24.04-py310/run-comfy.sh /usr/local/bin/run-comfy.sh
RUN chmod +x /usr/local/bin/run-comfy.sh
ENTRYPOINT ["/usr/local/bin/run-comfy.sh"]
