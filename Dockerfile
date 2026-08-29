# syntax=docker/dockerfile:1.7
FROM nvidia/cuda:12.8.0-devel-ubuntu24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG CODE_SERVER_VERSION=4.92.2
ARG NODE_VERSION=20.18.0
ARG IMAGE_VERSION="v5.4.0"

# Target Ada Lovelace (L40S sm_89) and Hopper (H200 sm_90)
ENV TORCH_CUDA_ARCH_LIST="8.9;9.0" \
    CUDA_ARCHS="89" \
    PYTHONUNBUFFERED=1 \
    MAX_JOBS=4 \
    CUDA_HOME="/usr/local/cuda" \
    PATH="/workspace/.venvs/comfyui-perf/bin:/usr/local/cuda/bin:${PATH}" \
    LD_LIBRARY_PATH="/usr/local/cuda-12.8/compat:/usr/local/cuda/compat:/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"

# --- 1. Base OS + CUDA Compat + Native Dev Toolchain ---
RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    cuda-compat-12-8 \
    python3 python3-venv python3-pip python3-dev \
    git curl ca-certificates unzip xz-utils iproute2 procps \
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 \
    build-essential g++ make ninja-build cmake pkg-config \
    portaudio19-dev libasound2-dev libjack-jackd2-dev libsamplerate0-dev \
    sox libsox-fmt-all ffmpeg \
    libopencv-core-dev libopencv-imgproc-dev libopencv-highgui-dev \
    libopencv-videoio-dev libopenblas-dev libomp-dev libgl1-mesa-dev; \
  rm -rf /var/lib/apt/lists/*

# --- 2. Node 20 ---
RUN set -eux; \
  curl -fsSL https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz \
    | tar -xJ -C /opt; \
  ln -sf /opt/node-v${NODE_VERSION}-linux-x64/bin/node /usr/local/bin/node; \
  ln -sf /opt/node-v${NODE_VERSION}-linux-x64/bin/npm  /usr/local/bin/npm; \
  ln -sf /opt/node-v${NODE_VERSION}-linux-x64/bin/npx  /usr/local/bin/npx

# --- 3. Workspace skeleton ---
RUN set -eux; mkdir -p /workspace/{bin,models,logs,notebooks,ComfyUI,ai-toolkit,.venvs,.locks} /scripts

# --- 4. Code-Server ---
RUN set -eux; \
  curl -L "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz" \
    | tar -xz -C /opt; \
  ln -sf /opt/code-server-${CODE_SERVER_VERSION}-linux-amd64/bin/code-server /usr/local/bin/code-server

# --- 5. Virtualenv, PyTorch & Native sm_89 Compilation ---
RUN set -eux; \
  python3 -m venv /workspace/.venvs/comfyui-perf; \
  /workspace/.venvs/comfyui-perf/bin/pip install --upgrade pip wheel setuptools packaging nanobind cmake ninja; \
  /workspace/.venvs/comfyui-perf/bin/pip install --timeout 600 \
    --extra-index-url https://download.pytorch.org/whl/cu128 \
    torch==2.8.0+cu128 torchvision==0.23.0+cu128 torchaudio==2.8.0+cu128; \
  /workspace/.venvs/comfyui-perf/bin/pip install triton==3.4.0 onnxruntime-gpu==1.18.1 opencv-python-headless==4.11.0.86 \
    fastapi uvicorn pydantic tqdm pillow requests comfyui-frontend-package comfyui-workflow-templates av; \
  /workspace/.venvs/comfyui-perf/bin/pip install --prefer-binary flash-attn --no-build-isolation || true; \
  # Build comfy-kitchen directly using its setup.py with architecture pinned to sm_89
  git clone --depth 1 https://github.com/Comfy-Org/comfy-kitchen.git /tmp/comfy-kitchen; \
  cd /tmp/comfy-kitchen; \
  /workspace/.venvs/comfyui-perf/bin/python setup.py build_ext --cuda-archs="89" install; \
  cd /; \
  rm -rf /tmp/comfy-kitchen

# --- 6. Runtime toggles ---
ENV COMFY_PORT=3000 \
    CODE_SERVER_PORT=3100 \
    JUPYTER_PORT=3600 \
    START_CODE_SERVER=1 \
    START_JUPYTER=0 \
    START_COMFYUI=0 \
    STARTUP_SLEEP_ONLY=0 \
    SKIP_PROVISION=0 \
    SAFE_START=0

COPY scripts/entrypoint.sh    /scripts/entrypoint.sh
COPY scripts/provision_all.sh /scripts/provision_all.sh
RUN set -eux; sed -i 's/\r$//' /scripts/*.sh; chmod +x /scripts/*.sh

LABEL org.opencontainers.image.version="${IMAGE_VERSION}"

EXPOSE 3000 3100 3600 7860 8675

ENTRYPOINT ["/scripts/entrypoint.sh"]
