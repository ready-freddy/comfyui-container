# syntax=docker/dockerfile:1.7
FROM nvidia/cuda:12.8.0-runtime-ubuntu24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG CODE_SERVER_VERSION=4.92.2
ARG IMAGE_VERSION="v0"

# Base OS + Python (runtime only)
RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    python3 python3-venv python3-pip python3-dev \
    git curl ca-certificates unzip iproute2 procps \
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender1; \
  rm -rf /var/lib/apt/lists/*

# Workspace skeleton
RUN set -eux; mkdir -p /workspace/{bin,models,logs,notebooks,ComfyUI,ai-toolkit,.venvs} /scripts /workspace/.locks

# code-server baked in; autostarts via entrypoint
RUN set -eux; \
  curl -L "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz" \
    | tar -xz -C /opt; \
  ln -sf /opt/code-server-${CODE_SERVER_VERSION}-linux-amd64/bin/code-server /usr/local/bin/code-server

# Runtime contract & toggles (ComfyUI stays manual-only)
ENV COMFY_PORT=3000 \
    CODE_SERVER_PORT=3100 \
    JUPYTER_PORT=3600 \
    START_CODE_SERVER=1 \
    START_JUPYTER=0 \
    START_COMFYUI=0 \
    STARTUP_SLEEP_ONLY=0 \
    SKIP_PROVISION=0 \
    SAFE_START=0
# AI-Toolkit ports are set by their launchers: Trainer 7860, Dashboard 8675 (not auto-started).

# Bring scripts from repo (no heredocs)
COPY entrypoint.sh.txt    /scripts/entrypoint.sh
COPY provision_all.sh.txt /scripts/provision_all.sh
RUN chmod +x /scripts/*.sh

# Provenance
LABEL org.opencontainers.image.version="${IMAGE_VERSION}"

# Ports: ComfyUI 3000, code-server 3100, Jupyter 3600, Trainer 7860, Dashboard 8675
EXPOSE 3000 3100 3600 7860 8675

ENTRYPOINT ["/scripts/entrypoint.sh"]
