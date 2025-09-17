# Ubuntu 24.04 + CUDA 12.8 (cudnn runtime); Python 3.12 is native
FROM nvidia/cuda:12.8.0-cudnn-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1 \
    VENV_PATH=/workspace/.venvs/comfyui-perf \
    APP_PATH=/workspace/ComfyUI \
    COMFY_PORT=3000 \
    CODE_SERVER_PORT=3100 \
    ENABLE_CODE_SERVER=1 \
    START_COMFYUI=0

# Runtime deps + build toolchain (incl. g++ for insightface etc.)
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common ca-certificates curl wget git git-lfs \
    libgl1 libopengl0 libglib2.0-0 libsm6 libxext6 libxrender1 \
    libgtk-3-0 ffmpeg unzip p7zip-full \
    build-essential g++ pkg-config python3 python3-venv python3-distutils python3-dev \
 && rm -rf /var/lib/apt/lists/*

# Copy in our wrapper script from repo → container
COPY --chmod=0755 images/comfyui-ubuntu24.04-py312/run-comfy.sh /usr/local/bin/run-comfy.sh

# Install code-server (fixed version, like before)
RUN set -eux; \
  curl -fsSL https://github.com/coder/code-server/releases/download/v4.89.1/code-server-4.89.1-linux-amd64.tar.gz \
  | tar xz -C /opt && \
  ln -sf /opt/code-server-4.89.1-linux-amd64/bin/code-server /usr/local/bin/code-server

# Non-root user + workspace
RUN useradd -m -s /bin/bash comfy || true && \
    mkdir -p /workspace && chown -R comfy:comfy /workspace

USER comfy
WORKDIR /workspace

# Expose: ComfyUI (3000), code-server (3100), AI-Toolkit (8675)
EXPOSE 3000 3100 8675

# Entrypoint is our wrapper (manual-only ComfyUI, auto code-server)
ENTRYPOINT ["/usr/local/bin/run-comfy.sh"]
