# Ubuntu 24.04 (glibc 2.39) + CUDA 12.8 + cuDNN 9
FROM nvidia/cuda:12.8.0-cudnn9-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    VENV_DIR=/opt/venvs/comfyui-perf \
    PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1

# Base OS deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common ca-certificates curl git git-lfs \
    build-essential pkg-config sudo \
    libgl1 libopengl0 libglib2.0-0 libsm6 libxext6 libxrender1 \
    libgtk-3-0 ffmpeg unzip p7zip-full wget \
 && rm -rf /var/lib/apt/lists/*

# Python 3.10 alongside system 3.12 (keep ABI for cp310 native nodes)
RUN add-apt-repository -y ppa:deadsnakes/ppa && apt-get update && \
    apt-get install -y --no-install-recommends python3.10 python3.10-venv python3.10-distutils && \
    rm -rf /var/lib/apt/lists/*

# Pip for py3.10
RUN curl -fsSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py \
 && python3.10 /tmp/get-pip.py

# Non-root user + workspace scaffold
RUN useradd -m -u 1000 -s /bin/bash comfy && \
    mkdir -p /workspace/ComfyUI /workspace/models /workspace/.venvs && \
    chown -R comfy:comfy /workspace
USER comfy
WORKDIR /workspace

# Isolated venv (py3.10)
RUN python3.10 -m venv ${VENV_DIR}
ENV PATH="${VENV_DIR}/bin:${PATH}"

# ComfyUI
RUN git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI

# Torch 2.8.0 + CUDA 12.8 wheels
RUN pip install --upgrade pip wheel setuptools && \
    pip install torch==2.8.0 torchvision==0.23.0 --index-url https://download.pytorch.org/whl/cu128

# Core deps
RUN pip install -r /workspace/ComfyUI/requirements.txt

# Optional manager
RUN pip install comfyui-manager

# ETUR node (latest main)
RUN mkdir -p /workspace/ComfyUI/custom_nodes && \
    cd /workspace/ComfyUI/custom_nodes && \
    git clone --depth=1 https://github.com/Ltamann/ComfyUI-TBG-ETUR.git

# Ports: prod 3000, canary 3001
EXPOSE 3000 3001

# Entrypoint
COPY run-comfy.sh /usr/local/bin/run-comfy.sh
RUN chmod +x /usr/local/bin/run-comfy.sh
ENTRYPOINT ["/usr/local/bin/run-comfy.sh"]
