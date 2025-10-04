# syntax=docker/dockerfile:1.7
FROM nvidia/cuda:12.8.0-devel-ubuntu24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG CODE_SERVER_VERSION=4.92.2
ARG NODE_VERSION=20.18.0
ARG IMAGE_VERSION="v0"

# --- Base OS + Python + DEVEL toolchain (nvcc via -devel base) ---
RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    python3 python3-venv python3-pip python3-dev \
    git curl ca-certificates unzip xz-utils iproute2 procps \
    # runtime GUI libs some Python libs expect
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 \
    # full build toolchain (g++ etc)
    build-essential g++ make ninja-build cmake pkg-config \
    # "libOPEN*" dev cluster for native builds
    libopencv-core-dev libopencv-imgproc-dev libopencv-highgui-dev \
    libopencv-videoio-dev libopenblas-dev libomp-dev libglib2.0-dev libgl1-mesa-dev; \
  rm -rf /var/lib/apt/lists/*

# --- Node 20 (for node-gyp / dashboard builds when needed) ---
RUN set -eux; \
  curl -fsSL https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz \
    | tar -xJ -C /opt; \
  ln -sf /opt/node-v${NODE_VERSION}-linux-x64/bin/node /usr/local/bin/node; \
  ln -sf /opt/node-v${NODE_VERSION}-linux-x64/bin/npm  /usr/local/bin/npm; \
  ln -sf /opt/node-v${NODE_VERSION}-linux-x64/bin/npx  /usr/local/bin/npx

# --- Workspace skeleton ---
RUN set -eux; mkdir -p /workspace/{bin,models,logs,notebooks,ComfyUI,ai-toolkit,.venvs,.locks} /scripts

# --- code-server baked (autostart policy unchanged) ---
RUN set -eux; \
  curl -L "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz" \
    | tar -xz -C /opt; \
  ln -sf /opt/code-server-${CODE_SERVER_VERSION}-linux-amd64/bin/code-server /usr/local/bin/code-server

# --- Runtime toggles (ComfyUI manual; Jupyter optional) ---
ENV COMFY_PORT=3000 \
    CODE_SERVER_PORT=3100 \
    JUPYTER_PORT=3600 \
    START_CODE_SERVER=1 \
    START_JUPYTER=0 \
    START_COMFYUI=0 \
    STARTUP_SLEEP_ONLY=0 \
    SKIP_PROVISION=0 \
    SAFE_START=0

# --- Bring your scripts (real .sh files in repo root) ---
COPY entrypoint.sh    /scripts/entrypoint.sh
COPY provision_all.sh /scripts/provision_all.sh
RUN set -eux; sed -i 's/\r$//' /scripts/*.sh; chmod +x /scripts/*.sh

# --- Provenance ---
LABEL org.opencontainers.image.version="${IMAGE_VERSION}"

# --- Ports (no auto-start except code-server) ---
# ComfyUI 3000, code-server 3100, Jupyter 3600, AI-Toolkit Trainer 7860, Dashboard 8675
EXPOSE 3000 3100 3600 7860 8675

ENTRYPOINT ["/scripts/entrypoint.sh"]
