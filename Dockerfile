# CUDA 12.8 runtime on Ubuntu 22.04 (works with RTX 5090 / CUDA 12.8)
FROM nvidia/cuda:12.8.0-cudnn-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 LC_ALL=C.UTF-8 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_ROOT_USER_ACTION=ignore \
    WORKDIR_PATH=/workspace \
    VENV_PATH=/workspace/.venvs/comfyui-perf \
    COMFY_PORT=3000 \
    CODESERVER_PORT=3100 \
    HF_HOME=/workspace/.cache/huggingface \
    PIP_CACHE_DIR=/workspace/.cache/pip

# System deps (incl. build tools in case xformers needs to compile)
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common curl wget git ca-certificates \
    build-essential pkg-config tmux tini supervisor \
    ffmpeg libgl1 libglib2.0-0 \
    ninja-build cmake \
    && rm -rf /var/lib/apt/lists/*

# Python 3.12 (clean on 22.04 via deadsnakes)
RUN add-apt-repository ppa:deadsnakes/ppa -y && \
    apt-get update && apt-get install -y --no-install-recommends \
    python3.12 python3.12-venv python3.12-dev \
    && rm -rf /var/lib/apt/lists/*

# code-server (official installer is fine in containers)
RUN curl -fsSL https://code-server.dev/install.sh | sh

# Prepare workspace/caches
RUN mkdir -p /workspace $HF_HOME $PIP_CACHE_DIR

# Supervisor config & bootstrap script
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY startup.sh /usr/local/bin/startup.sh
RUN chmod +x /usr/local/bin/startup.sh

WORKDIR /workspace

# Expose ComfyUI + code-server (and optional Comfy fallback 3001)
EXPOSE 3000 3001 3100

# Run both services under supervisord; wrap with tini as PID 1
ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/usr/bin/supervisord","-c","/etc/supervi]()
