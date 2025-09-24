# syntax=docker/dockerfile:1.7
ARG CUDA_TAG=12.8.0
FROM nvidia/cuda:${CUDA_TAG}-cudnn-devel-ubuntu24.04

ARG DEBIAN_FRONTEND=noninteractive

# Base OS deps (image build only; never apt inside running pods)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget git tini tzdata locales nano \
    python3 python3-venv python3-pip \
 && rm -rf /var/lib/apt/lists/*

# Provide "python" alias
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3 1

# Locale & Python defaults
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
ENV PIP_NO_CACHE_DIR=1 PYTHONUNBUFFERED=1

# Ports contract
EXPOSE 3000 3100 3400 3600

# Workdir + scripts
WORKDIR /workspace
RUN mkdir -p /workspace/{logs,models,notebooks,.venvs,ComfyUI,ai-toolkit,scripts,bin,.provision}
COPY scripts/entrypoint.sh /scripts/entrypoint.sh
COPY scripts/provision_all.sh /workspace/scripts/provision_all.sh

# Enforce exec bits (since web UI can't chmod)
RUN chmod +x /scripts/entrypoint.sh /workspace/scripts/provision_all.sh

# Provisioning toggles & version stamp
ENV AUTOPROVISION=1 \
    PROVISION_VERSION=2025-09-24-v1 \
    COMFY_PORT=3000 \
    CODE_SERVER_PORT=3100 \
    OSTRIS_PORT=3400 \
    JUPYTER_PORT=3600 \
    START_COMFYUI=0 \
    START_CODE_SERVER=0 \
    START_OSTRIS=0 \
    START_JUPYTER=0 \
    OSTRIS_REPO="" \
    OSTRIS_REF=""

ENTRYPOINT ["/usr/bin/tini","-s","--","/scripts/entrypoint.sh"]
