# syntax=docker/dockerfile:1.6

# =========================
# RunPod / ComfyUI / Toolkit
# v5.2.4+1 — SINGLE FILE
# =========================
FROM nvidia/cuda:12.8.0-devel-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC \
    COMFY_PORT=3000 \
    CODE_SERVER_PORT=3100 \
    JUPYTER_PORT=3600 \
    OSTRIS_PORT=7860 \
    OSTRISDASH_PORT=8675 \
    START_CODE_SERVER=1 \
    START_COMFYUI=0 \
    START_JUPYTER=0 \
    START_OSTRIS=0 \
    START_OSTRISDASH=0 \
    PASSWORD=changeme \
    JUPYTER_TOKEN=changeme \
    PATH="/usr/local/bin:/usr/bin:/bin:${PATH}"

EXPOSE 3000 3100 3600 7860 8675

# OS deps
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt/lists \
    set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates curl git wget \
      build-essential g++ make ninja-build cmake pkg-config \
      python3 python3-dev python3-venv python3-pip \
      libglib2.0-0 libglib2.0-dev \
      libgl1-mesa-dev libxext6 libsm6 \
      libopencv-core-dev libopencv-imgproc-dev libopencv-highgui-dev libopencv-videoio-dev \
      libopenblas-dev libomp-dev \
      openssl unzip xz-utils; \
    rm -rf /var/lib/apt/lists/*

# Node 20 (tarball)
ARG NODE_VERSION=20.18.0
RUN set -eux; \
    cd /tmp; \
    arch=$(uname -m); case "$arch" in x86_64) A=x64 ;; aarch64) A=arm64 ;; *) echo "Unsupported $arch"; exit 1 ;; esac; \
    curl -fsSL https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${A}.tar.xz -o node.tar.xz; \
    mkdir -p /usr/local/lib/nodejs; \
    tar -xJf node.tar.xz -C /usr/local/lib/nodejs; \
    ln -sf /usr/local/lib/nodejs/node-v${NODE_VERSION}-linux-${A}/bin/node /usr/local/bin/node; \
    ln -sf /usr/local/lib/nodejs/node-v${NODE_VERSION}-linux-${A}/bin/npm  /usr/local/bin/npm; \
    ln -sf /usr/local/lib/nodejs/node-v${NODE_VERSION}-linux-${A}/bin/npx  /usr/local/bin/npx; \
    node -v && npm -v

# code-server
ARG CODE_SERVER_VERSION=4.92.2
RUN set -eux; \
    arch=$(uname -m); case "$arch" in x86_64) CS=amd64 ;; aarch64) CS=arm64 ;; *) echo "Unsupported $arch"; exit 1 ;; esac; \
    curl -fsSL -o /tmp/code-server.deb \
      https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server_${CODE_SERVER_VERSION}_${CS}.deb; \
    apt-get update; apt-get install -y /tmp/code-server.deb; \
    rm -rf /var/lib/apt/lists/* /tmp/code-server.deb

# Persistent layout
RUN set -eux; \
    mkdir -p /workspace/.venvs/comfyui-perf /workspace/bin /workspace/ComfyUI \
             /workspace/models /workspace/ai-toolkit /workspace/logs /workspace/.locks /scripts; \
    chmod -R 777 /workspace

# Python stack (Torch cu128, ORT, OpenCV headless)
ARG TORCH_VERSION=2.8.0
ARG TORCH_CUDA=cu128
ARG ORT_VERSION=1.18.1
ARG OPENCV_VERSION=4.11.0.86
RUN set -eux; \
    python3 -m venv /workspace/.venvs/comfyui-perf; \
    . /workspace/.venvs/comfyui-perf/bin/activate; \
    python -m pip install --upgrade pip wheel setuptools; \
    pip install --index-url https://download.pytorch.org/whl/${TORCH_CUDA} \
        torch==${TORCH_VERSION} torchvision==0.20.0+${TORCH_CUDA} torchaudio==2.8.0+${TORCH_CUDA}; \
    pip install onnx onnxruntime-gpu==${ORT_VERSION} \
                opencv-python-headless==${OPENCV_VERSION} \
                fastapi uvicorn pydantic tqdm pillow; \
    python - <<'PY'
import torch, sys; print('Torch', torch.__version__, 'CUDA?', torch.cuda.is_available()); print(sys.version)
PY

# ------------------------------
# provision_all.sh (heredoc)
# ------------------------------
RUN set -eux; \
  cat > /scripts/provision_all.sh <<'SH'; \
  chmod +x /scripts/provision_all.sh
#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
VENV=/workspace/.venvs/comfyui-perf
BIN=/workspace/bin
mkdir -p "$BIN" /workspace/logs /workspace/.locks

# ComfyUI minimal checkout (idempotent)
if [ ! -d /workspace/ComfyUI/.git ]; then
  git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI || true
fi

# comfyctl launcher
if [ ! -x "$BIN/comfyctl" ]; then
  cat >"$BIN/comfyctl" <<'S2'
#!/usr/bin/env bash
set -Eeuo pipefail
VENV=/workspace/.venvs/comfyui-perf
. "$VENV/bin/activate"
exec python -u /workspace/ComfyUI/main.py --listen 0.0.0.0 --port ${COMFY_PORT:-3000}
S2
  chmod +x "$BIN/comfyctl"
fi

# aikitctl (trainer) — placeholder
if [ ! -x "$BIN/aikitctl" ]; then
  cat >"$BIN/aikitctl" <<'S3'
#!/usr/bin/env bash
set -Eeuo pipefail
. /workspace/.venvs/comfyui-perf/bin/activate
PORT="${OSTRIS_PORT:-7860}"
python - <<'PY'
import gradio as gr
def ping(x): return x
gr.Interface(fn=ping, inputs="text", outputs="text").launch(
  server_name="0.0.0.0", server_port=int("${OSTRIS_PORT:-7860}")
)
PY
S3
  chmod +x "$BIN/aikitctl"
fi

# aikituictl (dashboard) — placeholder (static serve)
if [ ! -x "$BIN/aikituictl" ]; then
  cat >"$BIN/aikituictl" <<'S4'
#!/usr/bin/env bash
set -Eeuo pipefail
cd /workspace/ai-toolkit
PORT="${OSTRISDASH_PORT:-8675}"
npx http-server -p "$PORT" -a 0.0.0.0 .
S4
  chmod +x "$BIN/aikituictl"
fi
SH

# ------------------------------
# entrypoint.sh (heredoc)
# ------------------------------
RUN set -eux; \
  cat > /scripts/entrypoint.sh <<'SH'; \
  chmod +x /scripts/entrypoint.sh
#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
LOG_DIR=/workspace/logs; mkdir -p "$LOG_DIR"
VENV=/workspace/.venvs/comfyui-perf

# 1) One-time provision (idempotent)
/scripts/provision_all.sh || true

# 2) Sanity using venv interpreter
if [ -x "$VENV/bin/python" ]; then
  "$VENV/bin/python" - <<'PY' | tee -a "$LOG_DIR/sanity.$(date +%Y%m%dT%H%M%S).log"
import sys, cv2, torch, onnxruntime
print('sanity python:', sys.executable)
print('cv2:', getattr(cv2,'__file__','n/a'))
print('torch:', torch.__version__, 'cuda:', torch.cuda.is_available())
print('onnxruntime:', onnxruntime.__version__)
PY
else
  echo "[sanity] WARNING: venv missing at $VENV" | tee -a "$LOG_DIR/sanity.$(date +%Y%m%dT%H%M%S).log"
fi

# 3) Auto-start: code-server only
if [ "${START_CODE_SERVER:-1}" = "1" ]; then
  mkdir -p /root/.config/code-server
  cat > /root/.config/code-server/config.yaml <<YML
bind-addr: 0.0.0.0:${CODE_SERVER_PORT:-3100}
auth: password
password: ${PASSWORD:-changeme}
cert: false
YML
  (code-server --log debug --disable-telemetry /workspace >/workspace/logs/code-server.log 2>&1 &)
fi

# 4) Optional toggled services
if [ "${START_COMFYUI:-0}" = "1" ]; then /workspace/bin/comfyctl start || true; fi
if [ "${START_JUPYTER:-0}" = "1" ]; then
  . "$VENV/bin/activate"
  jupyter lab --no-browser --NotebookApp.token=${JUPYTER_TOKEN:-changeme} \
    --ServerApp.port=${JUPYTER_PORT:-3600} --ServerApp.ip=0.0.0.0 \
    >/workspace/logs/jupyter.log 2>&1 &
  deactivate || true
fi
if [ "${START_OSTRIS:-0}" = "1" ]; then /workspace/bin/aikitctl || true; fi
if [ "${START_OSTRISDASH:-0}" = "1" ]; then /workspace/bin/aikituictl || true; fi

# 5) Keep container alive
exec tail -f /dev/null
SH

WORKDIR /workspace
ENTRYPOINT ["/scripts/entrypoint.sh"]
CMD [""]
