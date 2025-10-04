# syntax=docker/dockerfile:1.6

# ==========================================================
# RunPod / ComfyUI / AI-Toolkit — single large image
# v5.2.4+1 (patch: PATH + venv sanity + manual-only services)
# Base: Ubuntu 24.04 + CUDA 12.8 devel + Python 3.12
# ==========================================================

FROM nvidia/cuda:12.8.0-devel-ubuntu24.04

# ---- Core env & ports
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC \
    # default ports
    COMFY_PORT=3000 \
    CODE_SERVER_PORT=3100 \
    JUPYTER_PORT=3600 \
    OSTRIS_PORT=7860 \
    OSTRISDASH_PORT=8675 \
    # start toggles (only code-server auto)
    START_CODE_SERVER=1 \
    START_COMFYUI=0 \
    START_JUPYTER=0 \
    START_OSTRIS=0 \
    START_OSTRISDASH=0 \
    # make node visible to all shells (patch)
    PATH="/usr/local/bin:/usr/bin:/bin:${PATH}"

EXPOSE 3000 3100 3600 7860 8675

# ---- OS deps (build-essential, dev libs, git, curl, etc.)
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

# ---- Node.js 20.x (tarball) — avoids broken nodesource on 24.04 sometimes
ARG NODE_VERSION=20.18.0
RUN set -eux; \
    cd /tmp; \
    arch=$(uname -m); case "$arch" in \
      x86_64) node_arch=x64 ;; \
      aarch64) node_arch=arm64 ;; \
      *) echo "Unsupported arch: $arch"; exit 1 ;; \
    esac; \
    curl -fsSL https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz -o node.tar.xz; \
    mkdir -p /usr/local/lib/nodejs; \
    tar -xJf node.tar.xz -C /usr/local/lib/nodejs; \
    ln -sf /usr/local/lib/nodejs/node-v${NODE_VERSION}-linux-${node_arch}/bin/node /usr/local/bin/node; \
    ln -sf /usr/local/lib/nodejs/node-v${NODE_VERSION}-linux-${node_arch}/bin/npm  /usr/local/bin/npm; \
    ln -sf /usr/local/lib/nodejs/node-v${NODE_VERSION}-linux-${node_arch}/bin/npx  /usr/local/bin/npx; \
    node -v && npm -v

# ---- code-server (binds to 3100)
ARG CODE_SERVER_VERSION=4.92.2
RUN set -eux; \
    arch=$(uname -m); case "$arch" in \
      x86_64) cs_arch=amd64 ;; \
      aarch64) cs_arch=arm64 ;; \
      *) echo "Unsupported arch: $arch"; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/code-server.deb \
      https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server_${CODE_SERVER_VERSION}_${cs_arch}.deb; \
    apt-get update; \
    apt-get install -y /tmp/code-server.deb; \
    rm -rf /var/lib/apt/lists/* /tmp/code-server.deb

# ---- Create persistent layout
RUN set -eux; \
    mkdir -p /workspace/.venvs/comfyui-perf \
             /workspace/bin \
             /workspace/ComfyUI \
             /workspace/models \
             /workspace/ai-toolkit \
             /workspace/logs \
             /workspace/.locks; \
    chmod -R 777 /workspace

# ---- Python stack in venv (Torch cu128, ORT, OpenCV headless)
# NOTE: use PyTorch index for CUDA 12.8 wheels.
ARG TORCH_VERSION=2.8.0
ARG TORCH_CUDA=cu128
ARG ORT_VERSION=1.18.1
ARG OPENCV_VERSION=4.11.0.86
RUN set -eux; \
    python3 -m venv /workspace/.venvs/comfyui-perf; \
    . /workspace/.venvs/comfyui-perf/bin/activate; \
    python -m pip install --upgrade pip wheel setuptools; \
    pip install --index-url https://download.pytorch.org/whl/${TORCH_CUDA} \
        torch==${TORCH_VERSION} \
        torchvision==0.20.0+${TORCH_CUDA} \
        torchaudio==2.8.0+${TORCH_CUDA}; \
    pip install onnx onnxruntime-gpu==${ORT_VERSION} \
                opencv-python-headless==${OPENCV_VERSION} \
                fastapi uvicorn pydantic tqdm pillow; \
    python - <<'PY'
import torch, sys
print('Torch:', torch.__version__, 'CUDA?', torch.cuda.is_available())
print('Python:', sys.version)
PY

# ---- Lightweight provision script (idempotent)
#  - clones ComfyUI if missing
#  - does NOT auto-start services
COPY scripts/provision_all.sh /scripts/provision_all.sh
COPY scripts/entrypoint.sh    /scripts/entrypoint.sh
RUN set -eux; \
    sed -i 's/\r$//' /scripts/*.sh; \
    chmod +x /scripts/*.sh

# ---- Launch helpers into /workspace/bin (created by provision)
# comfyctl/aikitctl/aikituictl are emitted by provision script if missing

# ---- Final environment & entrypoint
ENV PASSWORD=changeme JUPYTER_TOKEN=changeme
WORKDIR /workspace
ENTRYPOINT ["/scripts/entrypoint.sh"]
CMD [""]

# =====================[ END DOCKERFILE ]====================

# --- scripts/entrypoint.sh (embedded for reference) ---
# Place this file at scripts/entrypoint.sh in your repo.
# It is copied above by the Dockerfile.
#
# #!/usr/bin/env bash
# set -Eeuo pipefail
# export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
# LOG_DIR=/workspace/logs; mkdir -p "$LOG_DIR"
# VENV=/workspace/.venvs/comfyui-perf
#
# # 1) One-time provision (idempotent)
# /scripts/provision_all.sh || true
#
# # 2) Sanity using venv interpreter (patch)
# if [ -x "$VENV/bin/python" ]; then
#   "$VENV/bin/python" - <<'PY' | tee -a "$LOG_DIR/sanity.$(date +%Y%m%dT%H%M%S).log"
# import sys, cv2, torch, onnxruntime
# print('sanity python:', sys.executable)
# print('cv2:', getattr(cv2,'__file__','n/a'))
# print('torch:', torch.__version__, 'cuda:', torch.cuda.is_available())
# print('onnxruntime:', onnxruntime.__version__)
# PY
# else
#   echo "[sanity] WARNING: venv missing at $VENV" | tee -a "$LOG_DIR/sanity.$(date +%Y%m%dT%H%M%S).log"
# fi
#
# # 3) Auto-start: code-server only (manual policy for others)
# if [ "${START_CODE_SERVER:-1}" = "1" ]; then
#   mkdir -p /root/.config/code-server
#   cat > /root/.config/code-server/config.yaml <<YML
# bind-addr: 0.0.0.0:${CODE_SERVER_PORT:-3100}
# auth: password
# password: ${PASSWORD:-changeme}
# cert: false
# YML
#   # run in background
#   (code-server --log debug --disable-telemetry /workspace >/workspace/logs/code-server.log 2>&1 &)
# fi
#
# # 4) Optional manual services, guarded by env toggles
# if [ "${START_COMFYUI:-0}" = "1" ]; then
#   /workspace/bin/comfyctl start || true
# fi
# if [ "${START_JUPYTER:-0}" = "1" ]; then
#   . "$VENV/bin/activate"; 
#   jupyter lab --no-browser --NotebookApp.token=${JUPYTER_TOKEN:-changeme} \
#     --ServerApp.port=${JUPYTER_PORT:-3600} --ServerApp.ip=0.0.0.0 \
#     >/workspace/logs/jupyter.log 2>&1 &
#   deactivate || true
# fi
# if [ "${START_OSTRIS:-0}" = "1" ]; then
#   /workspace/bin/aikitctl || true
# fi
# if [ "${START_OSTRISDASH:-0}" = "1" ]; then
#   /workspace/bin/aikituictl || true
# fi
#
# # 5) Keep container alive (tail)
# tail -f /dev/null

# --- scripts/provision_all.sh (embedded for reference) ---
# Place this file at scripts/provision_all.sh in your repo.
# It is copied above by the Dockerfile.
#
# #!/usr/bin/env bash
# set -Eeuo pipefail
# export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
# VENV=/workspace/.venvs/comfyui-perf
# BIN=/workspace/bin
# mkdir -p "$BIN" /workspace/logs /workspace/.locks
#
# # ComfyUI minimal checkout (idempotent)
# if [ ! -d /workspace/ComfyUI/.git ]; then
#   git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI || true
# fi
#
# # comfyctl launcher
# if [ ! -x "$BIN/comfyctl" ]; then
#   cat >"$BIN/comfyctl" <<'SH'
# #!/usr/bin/env bash
# set -Eeuo pipefail
# VENV=/workspace/.venvs/comfyui-perf
# . "$VENV/bin/activate"
# exec python -u /workspace/ComfyUI/main.py --listen 0.0.0.0 --port ${COMFY_PORT:-3000}
# SH
#   chmod +x "$BIN/comfyctl"
# fi
#
# # aikitctl (trainer) — placeholder
# if [ ! -x "$BIN/aikitctl" ]; then
#   cat >"$BIN/aikitctl" <<'SH'
# #!/usr/bin/env bash
# set -Eeuo pipefail
# . /workspace/.venvs/comfyui-perf/bin/activate
# PORT="${OSTRIS_PORT:-7860}"
# python - <<'PY'
# import gradio as gr
# def ping(x): return x
# gr.Interface(fn=ping, inputs="text", outputs="text").launch(server_name="0.0.0.0", server_port=int("${OSTRIS_PORT:-7860}"))
# PY
# SH
#   chmod +x "$BIN/aikitctl"
# fi
#
# # aikituictl (dashboard) — placeholder using Node
# if [ ! -x "$BIN/aikituictl" ]; then
#   cat >"$BIN/aikituictl" <<'SH'
# #!/usr/bin/env bash
# set -Eeuo pipefail
# cd /workspace/ai-toolkit
# PORT="${OSTRISDASH_PORT:-8675}"
# npx http-server -p "$PORT" -a 0.0.0.0 .
# SH
#   chmod +x "$BIN/aikituictl"
# fi


# =====================
# scripts/entrypoint.sh
# =====================
#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
LOG_DIR=/workspace/logs; mkdir -p "$LOG_DIR"
VENV=/workspace/.venvs/comfyui-perf

# 1) One-time provision (idempotent)
/scripts/provision_all.sh || true

# 2) Sanity using venv interpreter (patch)
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

# 3) Auto-start: code-server only (manual policy for others)
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

# 4) Optional manual services, guarded by env toggles
if [ "${START_COMFYUI:-0}" = "1" ]; then
  /workspace/bin/comfyctl start || true
fi
if [ "${START_JUPYTER:-0}" = "1" ]; then
  . "$VENV/bin/activate"
  jupyter lab --no-browser --NotebookApp.token=${JUPYTER_TOKEN:-changeme} \
    --ServerApp.port=${JUPYTER_PORT:-3600} --ServerApp.ip=0.0.0.0 \
    >/workspace/logs/jupyter.log 2>&1 &
  deactivate || true
fi
if [ "${START_OSTRIS:-0}" = "1" ]; then
  /workspace/bin/aikitctl || true
fi
if [ "${START_OSTRISDASH:-0}" = "1" ]; then
  /workspace/bin/aikituictl || true
fi

# 5) Keep container alive
exec tail -f /dev/null


# =========================
# scripts/provision_all.sh
# =========================
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
  cat >"$BIN/comfyctl" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
VENV=/workspace/.venvs/comfyui-perf
. "$VENV/bin/activate"
exec python -u /workspace/ComfyUI/main.py --listen 0.0.0.0 --port ${COMFY_PORT:-3000}
SH
  chmod +x "$BIN/comfyctl"
fi

# aikitctl (trainer) — placeholder
if [ ! -x "$BIN/aikitctl" ]; then
  cat >"$BIN/aikitctl" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
. /workspace/.venvs/comfyui-perf/bin/activate
PORT="${OSTRIS_PORT:-7860}"
python - <<'PY'
import gradio as gr

def ping(x):
    return x

gr.Interface(fn=ping, inputs="text", outputs="text").launch(
    server_name="0.0.0.0", server_port=int("${OSTRIS_PORT:-7860}")
)
PY
SH
  chmod +x "$BIN/aikitctl"
fi

# aikituictl (dashboard) — placeholder using Node static server
if [ ! -x "$BIN/aikituictl" ]; then
  cat >"$BIN/aikituictl" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
cd /workspace/ai-toolkit
PORT="${OSTRISDASH_PORT:-8675}"
npx http-server -p "$PORT" -a 0.0.0.0 .
SH
  chmod +x "$BIN/aikituictl"
fi

