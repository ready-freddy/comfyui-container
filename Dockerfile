# syntax=docker/dockerfile:1.7
FROM nvidia/cuda:12.8.0-devel-ubuntu24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG PYTHON_VERSION=3.12
ARG NODE_VERSION=v20.18.0
ARG CODESERVER_VERSION=4.92.2
ARG TORCH_CUDA=cu128
ARG TORCH_VERSION=2.8.0
ARG TV_VERSION=0.20.0
ARG TA_VERSION=2.8.0
ARG ORT_VERSION=1.18.1
ARG OPENCV_VERSION=4.11.0.86

# Pip behavior: reliable + quiet
ENV PIP_DEFAULT_TIMEOUT=120 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

# ---------- OS deps (build time only; never apt inside running pods) ----------
RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    ca-certificates curl wget git jq tini \
    build-essential pkg-config \
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 \
    ffmpeg \
    python3 python3-dev python3-venv; \
  rm -rf /var/lib/apt/lists/*

# ---------- Node (pinned tarball) ----------
RUN set -eux; \
  cd /tmp; \
  arch="$(dpkg --print-architecture)"; \
  case "$arch" in amd64) NODE_ARCH=x64 ;; arm64) NODE_ARCH=arm64 ;; *) echo "Unsupported arch: $arch"; exit 1 ;; esac; \
  NODE_TGZ="node-${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz"; \
  curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/${NODE_TGZ}" -o "${NODE_TGZ}"; \
  tar -xJf "${NODE_TGZ}" -C /usr/local --strip-components=1; \
  node -v && npm -v

# ---------- code-server (pinned tarball) ----------
RUN set -eux; \
  cd /opt; \
  arch="$(dpkg --print-architecture)"; \
  case "$arch" in amd64) CS_ARCH=amd64 ;; arm64) CS_ARCH=arm64 ;; *) echo "Unsupported arch: $arch"; exit 1 ;; esac; \
  CS_TGZ="code-server-${CODESERVER_VERSION}-linux-${CS_ARCH}.tar.gz"; \
  curl -fsSL "https://github.com/coder/code-server/releases/download/v${CODESERVER_VERSION}/${CS_TGZ}" -o "${CS_TGZ}"; \
  tar -xzf "${CS_TGZ}"; \
  ln -sfn "/opt/code-server-${CODESERVER_VERSION}-linux-${CS_ARCH}/bin/code-server" /usr/local/bin/code-server; \
  code-server --version

# ---------- Python venv (baked seed) ----------
ENV VENV_DIR=/opt/venvs/comfyui-perf \
    PERSIST_VENV=/workspace/.venvs/comfyui-perf \
    PATH="/opt/venvs/comfyui-perf/bin:/usr/local/bin:/usr/bin:/bin"

RUN set -eux; \
  python3 -m venv "${VENV_DIR}"; \
  "${VENV_DIR}/bin/python" -m pip install --upgrade --timeout 120 pip wheel setuptools "packaging<25"; \
  # Torch stack via cu128 index; first try explicit +cu128 builds, then retry fallback without suffix if needed
  ( \
    "${VENV_DIR}/bin/pip" install --prefer-binary --timeout 120 \
      --extra-index-url "https://download.pytorch.org/whl/${TORCH_CUDA}" \
      "torch==${TORCH_VERSION}" \
      "torchvision==${TV_VERSION}+${TORCH_CUDA}" \
      "torchaudio==${TA_VERSION}+${TORCH_CUDA}" \
  ) || ( \
    echo "Retrying Torch stack without +${TORCH_CUDA} suffix from cu128 index..."; \
    "${VENV_DIR}/bin/pip" install --prefer-binary --timeout 120 \
      --index-url "https://download.pytorch.org/whl/${TORCH_CUDA}" \
      "torch==${TORCH_VERSION}" \
      "torchvision==${TV_VERSION}" \
      "torchaudio==${TA_VERSION}" \
  ); \
  # Back to default index for the rest
  "${VENV_DIR}/bin/pip" install --prefer-binary --timeout 120 \
    "onnxruntime-gpu==${ORT_VERSION}" \
    "opencv-python-headless==${OPENCV_VERSION}" \
    "fastapi" "uvicorn" "pydantic" "tqdm" "pillow" "requests"

# ---------- App skeleton & ports ----------
ENV WORKSPACE=/workspace \
    COMFY_PORT=3000 \
    CODE_SERVER_PORT=3100 \
    JUPYTER_PORT=3600

RUN set -eux; \
  mkdir -p ${WORKSPACE}/bin ${WORKSPACE}/models ${WORKSPACE}/logs ${WORKSPACE}/.locks ${WORKSPACE}/.venvs

# ---------- Minimal scripts ----------
COPY scripts/comfyctl         /workspace/bin/comfyctl
COPY scripts/provision_all.sh /opt/provision_all.sh
COPY scripts/entrypoint.sh    /entrypoint.sh
RUN chmod +x /workspace/bin/comfyctl /opt/provision_all.sh /entrypoint.sh

WORKDIR /workspace
EXPOSE 3000 3100 3600
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=20 \
  CMD curl -fsS "http://127.0.0.1:${CODE_SERVER_PORT}/" >/dev/null || exit 1

ENTRYPOINT ["/usr/bin/tini","--","/entrypoint.sh"]
CMD []
