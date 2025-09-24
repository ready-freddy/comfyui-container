# syntax=docker/dockerfile:1.7

# Single target: CUDA 12.8 + Ubuntu 24.04 + Python 3.12
ARG CUDA_TAG=12.8.0
FROM nvidia/cuda:${CUDA_TAG}-cudnn-devel-ubuntu24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG USERNAME=comfy
ARG UID=1000
ARG GID=1000

# Base OS deps (only in image build; never apt inside running pods)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget git tini python3.12 python3.12-venv python3.12-distutils \
    sudo tzdata locales nano \
 && rm -rf /var/lib/apt/lists/*

# Locale
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# Non-root user
RUN groupadd -g ${GID} ${USERNAME} \
 && useradd -m -u ${UID} -g ${GID} -s /bin/bash ${USERNAME} \
 && usermod -aG sudo ${USERNAME} \
 && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-${USERNAME}

# Ports contract
EXPOSE 3000 3100 3400 3600

# Workdir + scripts
WORKDIR /workspace
RUN mkdir -p /workspace/{logs,models,notebooks,.venvs,ComfyUI,ai-toolkit,scripts,bin}
COPY scripts/entrypoint.sh /scripts/entrypoint.sh
COPY scripts/bootstrap.sh  /workspace/scripts/bootstrap.sh
RUN chmod +x /scripts/entrypoint.sh /workspace/scripts/bootstrap.sh

# Service toggles (ComfyUI manual by default)
ENV START_COMFYUI=0 \
    START_CODE_SERVER=1 \
    START_OSTRIS=0 \
    START_JUPYTER=0 \
    COMFY_PORT=3000 \
    CODE_SERVER_PORT=3100 \
    OSTRIS_PORT=3400 \
    JUPYTER_PORT=3600

# tini as PID 1
ENTRYPOINT ["/usr/bin/tini","-s","--","/scripts/entrypoint.sh"]
