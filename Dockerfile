# Ubuntu 24.04 + CUDA 12.8 (cuDNN devel); Python 3.12
FROM nvidia/cuda:12.8.0-cudnn-devel-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1 \
    VENV_PATH=/workspace/.venvs/comfyui-perf \
    IMAGE_VENV=/opt/venvs/comfyui-perf \
    APP_PATH=/workspace/ComfyUI \
    COMFY_PORT=3000 \
    CODE_SERVER_PORT=3100 \
    AI_TOOLKIT_PORT=8675 \
    START_COMFYUI=0 \
    TINI_SUBREAPER=1

# --- System deps (toolchain + Python headers + common CV/media/runtime libs) ---
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential g++ cmake pkg-config \
      python3 python3-venv python3-pip \
      python3.12-dev libpython3.12-dev \
      libgl1 libglib2.0-0 ffmpeg \
      libopenblas-dev libssl-dev libffi-dev \
      ca-certificates curl wget git unzip zip tini \
      rustc cargo git-lfs \
    && rm -rf /var/lib/apt/lists/*

# --- code-server (fixed version) ---
ENV CODE_SERVER_VERSION=4.89.1
RUN curl -fsSL https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server_${CODE_SERVER_VERSION}_amd64.deb -o /tmp/code-server.deb && \
    apt-get update && apt-get install -y /tmp/code-server.deb && \
    rm -f /tmp/code-server.deb && rm -rf /var/lib/apt/lists/*

# --- Non-root user + workspace ---
RUN useradd -m -s /bin/bash comfy && \
    mkdir -p /workspace && chown -R comfy:comfy /workspace

# --- Image venv + base Python deps (baked, later mirrored to /workspace if missing) ---
RUN python3 -m venv ${IMAGE_VENV} && \
    ${IMAGE_VENV}/bin/python -m pip install --upgrade pip wheel setuptools && \
    ${IMAGE_VENV}/bin/python -m pip install \
        "torch==2.8.0" --index-url https://download.pytorch.org/whl/cu128 && \
    ${IMAGE_VENV}/bin/python -m pip install \
        onnx onnxruntime-gpu==1.18.1 \
        "numpy<2.1" pillow \
        "uvicorn<1.0" "fastapi<1.0" \
        requests tqdm \
        opencv-python-headless rembg \
    && true

# --- Build GroundingDINO wheel at image build (no runtime compiles) ---
ARG GDINO_REPO=https://github.com/IDEA-Research/GroundingDINO.git
ARG GDINO_REF=main
RUN mkdir -p /opt/wheels /opt/src && cd /opt/src && \
    git clone --depth 1 --branch ${GDINO_REF} ${GDINO_REPO} GroundingDINO && \
    cd GroundingDINO && \
    ${IMAGE_VENV}/bin/python -m pip install --upgrade pip wheel setuptools && \
    FORCE_CUDA=1 ${IMAGE_VENV}/bin/python -m pip wheel . -w /opt/wheels && \
    ${IMAGE_VENV}/bin/python -m pip install --no-index --find-links=/opt/wheels GroundingDINO && \
    rm -rf /opt/src/GroundingDINO

# --- Ensure perms for comfy user over baked assets ---
RUN mkdir -p /opt/venvs /opt/wheels && \
    ln -s ${IMAGE_VENV} /opt/venvs/comfyui-perf && \
    chown -R comfy:comfy /opt/venvs /opt/wheels

# --- Startup script ---
COPY images/comfyui-ubuntu24.04-py312/run-comfy.sh /usr/local/bin/run-comfy.sh
RUN chmod +x /usr/local/bin/run-comfy.sh

EXPOSE 3000 3100 8675

USER comfy
WORKDIR /workspace

# tini as PID1 with subreaper
ENTRYPOINT ["/usr/bin/tini", "-s", "--", "/usr/local/bin/run-comfy.sh"]
