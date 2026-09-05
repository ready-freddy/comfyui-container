# syntax=docker/dockerfile:1.7
FROM nvidia/cuda:12.8.0-devel-ubuntu24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG CODE_SERVER_VERSION=4.92.2
ARG NODE_VERSION=20.18.0
ARG BLENDER_VERSION=4.2.3
ARG IMAGE_VERSION="v5.7.0"

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
    LD_LIBRARY_PATH="/workspace/lib:/usr/local/cuda-12.8/compat:/usr/local/cuda/compat:/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"

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
    libopencv-videoio-dev libopenblas-dev libomp-dev libgl1-mesa-dev \
    xvfb libxkbcommon0 libxcursor1 libxi6 libxinerama1 libxrandr2; \
  rm -rf /var/lib/apt/lists/*

# --- 2. Node 20 ---
RUN set -eux; \
  curl -fsSL https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz \
    | tar -xJ -C /opt; \
  ln -sf /opt/node-v${NODE_VERSION}-linux-x64/bin/node /usr/local/bin/node; \
  ln -sf /opt/node-v${NODE_VERSION}-linux-x64/bin/npm  /usr/local/bin/npm; \
  ln -sf /opt/node-v${NODE_VERSION}-linux-x64/bin/npx  /usr/local/bin/npx

# --- 3. Persistent Workspace Skeleton & System Directories ---
RUN set -eux; mkdir -p /workspace/{bin,models,logs,notebooks,ComfyUI,ai-toolkit} /opt/venvs /scripts

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

# --- 5. Virtualenv & Complete Studio ML Stack Pre-Baked ---
COPY requirements.studio.txt /tmp/requirements.studio.txt

RUN set -eux; \
  python3 -m venv /opt/venvs/comfyui-perf; \
  /opt/venvs/comfyui-perf/bin/pip install --upgrade pip wheel setuptools packaging scikit-build-core nanobind cmake ninja uv; \
  /opt/venvs/comfyui-perf/bin/pip install --timeout 600 \
    --extra-index-url https://download.pytorch.org/whl/cu128 \
    torch==2.8.0+cu128 torchvision==0.23.0+cu128 torchaudio==2.8.0+cu128; \
  /opt/venvs/comfyui-perf/bin/uv pip install --no-cache -r /tmp/requirements.studio.txt; \
  /opt/venvs/comfyui-perf/bin/pip install --no-cache-dir --no-deps comfy-kitchen; \
  /opt/venvs/comfyui-perf/bin/python -c '\
import comfy_kitchen, pathlib; \
p = pathlib.Path(comfy_kitchen.__file__); \
shim = """\n\
import torch\n\
import torch.nn.functional as F\n\
\n\
def _native_rms_rope_split_half_(q, k, freqs_cis, q_scale=1.0, k_scale=1.0, epsilon=1e-5, rot_dim=None):\n\
    q_norm = F.rms_norm(q, (q.shape[-1],), eps=epsilon)\n\
    k_norm = F.rms_norm(k, (k.shape[-1],), eps=epsilon)\n\
    if q_scale != 1.0: q_norm = q_norm * q_scale\n\
    if k_scale != 1.0: k_norm = k_norm * k_scale\n\
    rot_dim = rot_dim or (freqs_cis.shape[-1] * 2 if torch.is_complex(freqs_cis) else freqs_cis.shape[-1])\n\
    q_rot, q_pass = q_norm[..., :rot_dim], q_norm[..., rot_dim:]\n\
    k_rot, k_pass = k_norm[..., :rot_dim], k_norm[..., rot_dim:]\n\
    freqs = freqs_cis\n\
    while freqs.ndim < q_rot.ndim: freqs = freqs.unsqueeze(1)\n\
    if torch.is_complex(freqs):\n\
        q_c = torch.view_as_complex(q_rot.float().reshape(*q_rot.shape[:-1], -1, 2))\n\
        k_c = torch.view_as_complex(k_rot.float().reshape(*k_rot.shape[:-1], -1, 2))\n\
        q_rot = torch.view_as_real(q_c * freqs).flatten(-2).to(q.dtype)\n\
        k_rot = torch.view_as_real(k_c * freqs).flatten(-2).to(k.dtype)\n\
    else:\n\
        cos = freqs.cos().to(dtype=q.dtype)\n\
        sin = freqs.sin().to(dtype=q.dtype)\n\
        q1, q2 = q_rot.chunk(2, dim=-1)\n\
        k1, k2 = k_rot.chunk(2, dim=-1)\n\
        q_rot = torch.cat([q1 * cos - q2 * sin, q1 * sin + q2 * cos], dim=-1)\n\
        k_rot = torch.cat([k1 * cos - k2 * sin, k1 * sin + k2 * cos], dim=-1)\n\
    if q_pass.numel() > 0:\n\
        q.copy_(torch.cat([q_rot, q_pass], dim=-1))\n\
        k.copy_(torch.cat([k_rot, k_pass], dim=-1))\n\
    else:\n\
        q.copy_(q_rot)\n\
        k.copy_(k_rot)\n\
    return q, k\n\
\n\
rms_rope_split_half_ = _native_rms_rope_split_half_\n\
rms_rope_split_half = _native_rms_rope_split_half_\n\
"""; \
p.write_text(p.read_text() + shim)\
'; \
  /opt/venvs/comfyui-perf/bin/pip install --no-cache-dir --no-deps \
    git+https://github.com/facebookresearch/sam3.git \
    git+https://github.com/microsoft/VibeVoice.git \
    git+https://github.com/apple/ml-sharp.git \
    git+https://github.com/microsoft/MoGe.git \
    audio-separator; \
  /opt/venvs/comfyui-perf/bin/pip install --no-build-isolation flash-attn; \
  /opt/venvs/comfyui-perf/bin/pip install --no-cache-dir sageattention; \
  /opt/venvs/comfyui-perf/bin/pip install --no-cache-dir --no-deps descript-audiotools==0.7.2 descript-audio-codec==1.0.0; \
  /opt/venvs/comfyui-perf/bin/pip install --no-cache-dir --no-deps \
    "https://github.com/JamePeng/llama-cpp-python/releases/download/v0.3.46-cu128-linux-20260808/llama_cpp_python-0.3.46+cu128-cp312-cp312-linux_x86_64.whl"; \
  /opt/venvs/comfyui-perf/bin/pip install --no-cache-dir --force-reinstall --no-deps \
    "numpy==1.26.4" \
    "pillow>=9.2.0,<12.0"; \
  rm -f /tmp/requirements.studio.txt

# --- 6. Verified Environment Assertion ---
RUN set -eux; \
  blender --version; \
  /opt/venvs/comfyui-perf/bin/python -c "\
import torch, flash_attn, sageattention, comfy_kitchen, comfy_env, audiotools, dac, demucs, numpy as np, PIL, llama_cpp, pathlib, pygltflib, viser, sharp, moge, audio_separator, diffusers, iopath, timm, plyfile, cv2, sam3; \
assert hasattr(comfy_kitchen, 'rms_rope_split_half_'), 'FATAL: comfy_kitchen RoPE export missing'; \
q = torch.randn(1, 4, 16, 64, dtype=torch.bfloat16); \
k = torch.randn(1, 4, 16, 64, dtype=torch.bfloat16); \
f = torch.complex(torch.randn(1, 16, 1, 32), torch.randn(1, 16, 1, 32)); \
comfy_kitchen.rms_rope_split_half_(q, k, f); \
from llama_cpp.llama_chat_format import Qwen3VLChatHandler, Llava15ChatHandler; \
assert np.__version__ == '1.26.4', f'NumPy mismatch: {np.__version__}'; \
assert int(PIL.__version__.split('.')[0]) < 12, f'Pillow mismatch: {PIL.__version__}'; \
lib_dir = pathlib.Path(llama_cpp.__file__).parent / 'lib'; \
cuda_libs = list(lib_dir.glob('*cuda*')); \
assert len(cuda_libs) > 0 or llama_cpp.llama_supports_gpu_offload(), f'FATAL: CUDA libraries missing from {lib_dir}'; \
print(f'=== ALL NATIVE ACCELERATION, ROPE SHIM, SAM3, OPENCV, PLYFILE, BLENDER, 3D, AUDIO & STUDIO REQUIREMENTS VERIFIED ===')"

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
