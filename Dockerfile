# syntax=docker/dockerfile:1.7
FROM nvidia/cuda:13.0.0-devel-ubuntu24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG CODE_SERVER_VERSION=4.92.2
ARG NODE_VERSION=20.18.0
ARG BLENDER_VERSION=4.2.3
ARG IMAGE_VERSION="v6.0.0-cu13"

# Target Ada Lovelace (L40S / RTX 6000 Ada sm_89) and Hopper (H200 sm_90)
ENV TORCH_CUDA_ARCH_LIST="8.9;9.0" \
    PYTHONUNBUFFERED=1 \
    MAX_JOBS=4 \
    TORCHINDUCTOR_COMPILE_THREADS=4 \
    OMP_NUM_THREADS=4 \
    CUDA_HOME="/usr/local/cuda" \
    CUDA_PATH="/usr/local/cuda" \
    CUDACXX="/usr/local/cuda/bin/nvcc" \
    PATH="/opt/venvs/comfyui-perf/bin:/usr/local/cuda/bin:${PATH}" \
    LD_LIBRARY_PATH="/workspace/lib:/usr/local/cuda/compat:/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"

# --- 1. Base OS + Native Dev Toolchain + JuiceFS ---
RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    python3 python3-venv python3-pip python3-dev \
    git curl ca-certificates unzip xz-utils iproute2 procps fuse3 libfuse3-3 \
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 \
    build-essential g++ make ninja-build cmake pkg-config \
    portaudio19-dev libasound2-dev libjack-jackd2-dev libsamplerate0-dev \
    sox libsox-fmt-all ffmpeg \
    libopencv-core-dev libopencv-imgproc-dev libopencv-highgui-dev \
    libopencv-videoio-dev libopenblas-dev libomp-dev libgl1-mesa-dev \
    xvfb libxkbcommon0 libxcursor1 libxi6 libxinerama1 libxrandr2; \
  curl -sSL https://d.juicefs.com/install | sh -; \
  rm -rf /var/lib/apt/lists/*

# --- 2. Node 20 ---
RUN set -eux; \
  curl -fsSL https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz \
    | tar -xJ -C /opt; \
  ln -sf /opt/node-v${NODE_VERSION}-linux-x64/bin/node /usr/local/bin/node; \
  ln -sf /opt/node-v${NODE_VERSION}-linux-x64/bin/npm  /usr/local/bin/npm; \
  ln -sf /opt/node-v${NODE_VERSION}-linux-x64/bin/npx  /usr/local/bin/npx

# --- 3. Persistent Workspace Skeleton & System Directories ---
RUN set -eux; mkdir -p /workspace/{bin,models,logs,notebooks,ComfyUI,ai-toolkit} /opt/venvs /scripts /root/cache

# --- 4. Code-Server ---
RUN set -eux; \
  curl -L "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz" \
    | tar -xz -C /opt; \
  ln -sf /opt/code-server-${CODE_SERVER_VERSION}-linux-amd64/bin/code-server /usr/local/bin/code-server

# --- 4.1 Headless Blender 4.2 LTS Integration ---
RUN set -eux; \
  curl -fsSL "https://download.blender.org/release/Blender4.2/blender-${BLENDER_VERSION}-linux-x64.tar.xz" \
    | tar -xJ -C /opt; \
  ln -sf /opt/blender-${BLENDER_VERSION}-linux-x64/blender /usr/local/bin/blender

# --- 5. Virtualenv & Base Tooling ---
RUN set -eux; \
  python3 -m venv /opt/venvs/comfyui-perf; \
  /opt/venvs/comfyui-perf/bin/pip install --upgrade pip wheel setuptools packaging scikit-build-core nanobind cmake ninja uv

# --- 5.1 PyTorch CUDA 13 Stack ---
RUN set -eux; \
  /opt/venvs/comfyui-perf/bin/pip install --timeout 600 \
    --index-url https://download.pytorch.org/whl/cu130 \
    torch torchvision torchaudio || \
  /opt/venvs/comfyui-perf/bin/pip install --timeout 600 \
    --pre --index-url https://download.pytorch.org/whl/nightly/cu130 \
    torch torchvision torchaudio

# --- 5.2 Studio Requirements ---
COPY requirements.studio.txt /tmp/requirements.studio.txt
RUN set -eux; \
  /opt/venvs/comfyui-perf/bin/uv pip install --no-cache -r /tmp/requirements.studio.txt; \
  rm -f /tmp/requirements.studio.txt

# --- 5.3 Comfy-Kitchen & Audio Decoders ---
RUN set -eux; \
  /opt/venvs/comfyui-perf/bin/pip install --no-cache-dir comfy-kitchen; \
  /opt/venvs/comfyui-perf/bin/pip install --no-cache-dir --no-deps descript-audiotools==0.7.2 descript-audio-codec==1.0.0 audio-separator

# --- 5.4 Repositories & Video/Audio Modules ---
RUN set -eux; \
  /opt/venvs/comfyui-perf/bin/pip install --no-cache-dir --no-deps \
    git+https://github.com/facebookresearch/sam3.git \
    git+https://github.com/microsoft/VibeVoice.git \
    git+https://github.com/apple/ml-sharp.git \
    git+https://github.com/microsoft/MoGe.git

# --- 5.5 Fast Attention & Acceleration Kernels ---
RUN set -eux; \
  /opt/venvs/comfyui-perf/bin/pip install --no-build-isolation flash-attn; \
  /opt/venvs/comfyui-perf/bin/pip install --no-cache-dir sageattention

# --- 5.6 Native llama-cpp Compilation ---
RUN set -eux; \
  CMAKE_ARGS="-DGGML_CUDA=on -DCMAKE_CUDA_ARCHITECTURES=89;90" \
    /opt/venvs/comfyui-perf/bin/pip install --no-build-isolation --no-cache-dir llama-cpp-python

# --- 5.7 Strict ABI Locks ---
RUN set -eux; \
  /opt/venvs/comfyui-perf/bin/pip install --no-cache-dir --force-reinstall --no-deps \
    "numpy==1.26.4" \
    "pillow>=9.2.0,<12.0"

# --- 6. Verified Environment Assertion ---
RUN set -eux; \
  blender --version; \
  /opt/venvs/comfyui-perf/bin/python -c "\
import torch, flash_attn, sageattention, comfy_kitchen, comfy_env, audiotools, dac, demucs, numpy as np, PIL, llama_cpp, pathlib, pygltflib, viser, sharp, moge, audio_separator, diffusers, iopath, timm, plyfile, cv2, sam3; \
assert np.__version__ == '1.26.4', f'NumPy mismatch: {np.__version__}'; \
assert int(PIL.__version__.split('.')[0]) < 12, f'Pillow mismatch: {PIL.__version__}'; \
print(f'=== NATIVE CUDA 13 ACCELERATION, COMFY-KITCHEN, SAM3 & BLENDER VERIFIED ===')"

# --- 7. Runtime Toggles ---
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
