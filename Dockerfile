# syntax=docker/dockerfile:1.6
FROM nvidia/cuda:12.8.0-devel-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC \
    COMFY_PORT=3000 CODE_SERVER_PORT=3100 JUPYTER_PORT=3600 \
    OSTRIS_PORT=7860 OSTRISDASH_PORT=8675 \
    START_CODE_SERVER=1 START_COMFYUI=0 START_JUPYTER=0 START_OSTRIS=0 START_OSTRISDASH=0 \
    PASSWORD=changeme JUPYTER_TOKEN=changeme \
    PATH="/usr/local/bin:/usr/bin:/bin:${PATH}"

EXPOSE 3000 3100 3600 7860 8675

# ---- system deps
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt/lists \
    set -eux; apt-get update; apt-get install -y --no-install-recommends \
    ca-certificates curl git wget build-essential g++ make ninja-build cmake pkg-config \
    python3 python3-dev python3-venv python3-pip \
    libglib2.0-0 libglib2.0-dev libgl1-mesa-dev libxext6 libsm6 \
    libopencv-core-dev libopencv-imgproc-dev libopencv-highgui-dev libopencv-videoio-dev \
    libopenblas-dev libomp-dev openssl unzip xz-utils; \
    rm -rf /var/lib/apt/lists/*

# ---- Node 20
ARG NODE_VERSION=20.18.0
RUN set -eux; \
  cd /tmp; \
  arch=$(uname -m); case "$arch" in x86_64) A=x64 ;; aarch64) A=arm64 ;; *) echo "Unsupported $arch"; exit 1 ;; esac; \
  curl -fsSL https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${A}.tar.xz -o node.tar.xz; \
  mkdir -p /usr/local/lib/nodejs; \
  tar -xJf node.tar.xz -C /usr/local/lib/nodejs; \
  NODE_DIR=/usr/local/lib/nodejs/node-v${NODE_VERSION}-linux-${A}/bin; \
  ln -sf "${NODE_DIR}/node" /usr/local/bin/node; \
  ln -sf "${NODE_DIR}/npm"  /usr/local/bin/npm; \
  ln -sf "${NODE_DIR}/npx"  /usr/local/bin/npx; \
  /usr/local/bin/node -v && /usr/local/bin/npm -v

# ---- code-server
ARG CODE_SERVER_VERSION=4.92.2
RUN set -eux; \
  arch=$(uname -m); case "$arch" in x86_64) CS=amd64 ;; aarch64) CS=arm64 ;; *) echo "Unsupported $arch"; exit 1 ;; esac; \
  curl -fsSL -o /tmp/code-server.deb https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server_${CODE_SERVER_VERSION}_${CS}.deb; \
  apt-get update; apt-get install -y /tmp/code-server.deb; \
  rm -rf /var/lib/apt/lists/* /tmp/code-server.deb

# ---- layout
RUN set -eux; mkdir -p /workspace /workspace/logs /workspace/.locks /workspace/bin /scripts /opt/venvs; chmod -R 777 /workspace

# ---- Python + CUDA stack
ARG TORCH_VERSION=2.8.0 TORCH_CUDA=cu128 ORT_VERSION=1.18.1 OPENCV_VERSION=4.11.0.86
RUN set -eux; \
    python3 -m venv /opt/venvs/comfyui-perf; \
    . /opt/venvs/comfyui-perf/bin/activate; \
    python -m pip install --upgrade pip wheel setuptools; \
    pip install --index-url https://download.pytorch.org/whl/${TORCH_CUDA} \
      torch==${TORCH_VERSION} torchvision==0.20.0+${TORCH_CUDA} torchaudio==2.8.0+${TORCH_CUDA}; \
    pip install onnx onnxruntime-gpu==${ORT_VERSION} \
      opencv-python-headless==${OPENCV_VERSION} fastapi uvicorn pydantic tqdm pillow; \
    python - <<'PY'
import torch, sys
print("Torch", torch.__version__, "CUDA?", torch.cuda.is_available())
print("Python", sys.version)
PY

# ---- scripts
COPY scripts/provision_all.sh /scripts/provision_all.sh
COPY scripts/entrypoint.sh    /scripts/entrypoint.sh
RUN set -eux; sed -i 's/\r$//' /scripts/*.sh; chmod +x /scripts/*.sh

WORKDIR /workspace
ENTRYPOINT ["/scripts/entrypoint.sh"]
CMD [""]
