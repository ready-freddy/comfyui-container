# Ubuntu 24.04 + CUDA 12.8 (cuDNN runtime); Python 3.12 is native
FROM nvidia/cuda:12.8.0-cudnn-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1 \
    VENV_PATH=/workspace/.venvs/comfyui-perf \
    APP_PATH=/workspace/ComfyUI \
    COMFY_PORT=3000 \
    CODE_SERVER_PORT=3100 \
    AI_TOOLKIT_PORT=8675 \
    START_COMFYUI=0 \
    START_AI_TOOLKIT=0 \
    TINI_SUBREAPER=1 \
    PIP_CACHE_DIR=/tmp/pipcache

# Minimal runtime deps (no compilers, no python-dev, no rust)
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-venv python3-pip \
      libgl1 libglib2.0-0 ffmpeg \
      ca-certificates curl wget git unzip zip tini git-lfs \
    && rm -rf /var/lib/apt/lists/*

# code-server
ENV CODE_SERVER_VERSION=4.89.1
RUN curl -fsSL https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server_${CODE_SERVER_VERSION}_amd64.deb -o /tmp/code-server.deb \
 && apt-get update && apt-get install -y /tmp/code-server.deb \
 && rm -f /tmp/code-server.deb && rm -rf /var/lib/apt/lists/*

# Non-root user + workspace
RUN useradd -m -s /bin/bash comfy \
 && mkdir -p /workspace && chown -R comfy:comfy /workspace

# ComfyUI skeleton (you can mount your own later)
WORKDIR /workspace
RUN git clone --depth=1 https://github.com/comfyanonymous/ComfyUI "${APP_PATH}"

# Startup script (keep this path in your repo)
COPY images/comfyui-ubuntu24.04-py312/run-comfy.sh /usr/local/bin/run-comfy.sh
RUN chmod +x /usr/local/bin/run-comfy.sh

EXPOSE 3000 3100 8675

USER comfy
WORKDIR /workspace

ENTRYPOINT ["/usr/bin/tini", "-s", "--", "/usr/local/bin/run-comfy.sh"]
