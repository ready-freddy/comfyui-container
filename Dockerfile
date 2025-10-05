# syntax=docker/dockerfile:1.7
FROM --platform=linux/amd64 nvidia/cuda:12.8.1-runtime-ubuntu22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG TORCH_VERSION=2.8.0
ARG TV_VERSION=0.23.0
ARG TA_VERSION=2.8.0
ARG TRITON_VERSION=3.4.0

ENV VENV_DIR=/opt/venvs/comfyui \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PATH="/opt/venvs/comfyui/bin:${PATH}"

# System deps (build-time only; never apt inside running pods)
RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    ca-certificates curl wget git jq tini \
    build-essential pkg-config \
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 \
    ffmpeg \
    python3 python3-dev python3-venv; \
  rm -rf /var/lib/apt/lists/*

# Create venv and upgrade pip tooling
RUN set -eux; \
  python3 -m venv "${VENV_DIR}"; \
  python -m pip install --upgrade pip wheel setuptools "packaging<25"

# Install PyTorch stack by direct wheel URLs (CUDA 12.8)
RUN set -eux; \
  PYTAG="$(python - <<'PY'\nimport sys;print(f'cp{sys.version_info.major}{sys.version_info.minor}')\nPY\n)"; \
  PLAT="manylinux_2_28_x86_64"; \
  BASE="https://download.pytorch.org/whl"; \
  curl -fSL "${BASE}/cu128/torch-${TORCH_VERSION}+cu128-${PYTAG}-${PYTAG}-${PLAT}.whl" -o /tmp/torch.whl; \
  curl -fSL "${BASE}/cu128/torchvision-${TV_VERSION}+cu128-${PYTAG}-${PYTAG}-${PLAT}.whl" -o /tmp/torchvision.whl; \
  curl -fSL "${BASE}/cu128/torchaudio-${TA_VERSION}+cu128-${PYTAG}-${PYTAG}-${PLAT}.whl" -o /tmp/torchaudio.whl; \
  pip install --no-index /tmp/torch.whl /tmp/torchvision.whl /tmp/torchaudio.whl; \
  rm -f /tmp/torch*.whl /tmp/torchvision*.whl /tmp/torchaudio*.whl

# Triton (optional but recommended; ignore failure gracefully)
RUN set -eux; \
  PYTAG="$(python - <<'PY'\nimport sys;print(f'cp{sys.version_info.major}{sys.version_info.minor}')\nPY\n)"; \
  TRITON_FILE="triton-${TRITON_VERSION}-${PYTAG}-${PYTAG}-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl"; \
  TRITON_URL="https://download.pytorch.org/whl/triton/${TRITON_FILE}"; \
  curl -fSL "${TRITON_URL}" -o /tmp/triton.whl && pip install --no-index /tmp/triton.whl || echo '*** Triton optional; continuing'; \
  rm -f /tmp/triton.whl

# Common runtime libs
RUN set -eux; \
  pip install --upgrade --prefer-binary \
    fastapi uvicorn pydantic tqdm pillow requests \
    opencv-python-headless onnxruntime-gpu

WORKDIR /workspace
CMD ["/bin/bash"]
