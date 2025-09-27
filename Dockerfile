# syntax=docker/dockerfile:1.7
FROM nvidia/cuda:12.8.0-runtime-ubuntu24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG CODE_SERVER_VERSION=4.92.2

# OS + Python + GL/X
RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    python3 python3-venv python3-pip python3-dev \
    git curl ca-certificates unzip iproute2 procps \
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender1; \
  rm -rf /var/lib/apt/lists/*

# Workspace skeleton
RUN set -eux; mkdir -p /workspace/{bin,models,logs,notebooks,ComfyUI,ai-toolkit,.venvs} /scripts

# Bake code-server (no runtime download)
RUN set -eux; \
  curl -L "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz" \
    | tar -xz -C /opt; \
  ln -sf /opt/code-server-${CODE_SERVER_VERSION}-linux-amd64/bin/code-server /usr/local/bin/code-server

# Contract
ENV COMFY_PORT=3000 \
    CODE_SERVER_PORT=3100 \
    JUPYTER_PORT=3600 \
    OSTRIS_PORT=3400 \
    START_CODE_SERVER=1 \
    START_JUPYTER=1 \
    START_COMFYUI=0 \
    START_OSTRIS=0 \
    STARTUP_SLEEP_ONLY=0

# entrypoint.sh (inline)
RUN set -eux; cat > /scripts/entrypoint.sh <<'BASH'
#!/usr/bin/env bash
set -Eeuo pipefail
LOG_DIR=/workspace/logs; mkdir -p "$LOG_DIR"
echo "[entrypoint] $(date -Iseconds)"

# Always run provision (soft-fail so container stays alive)
if /scripts/provision_all.sh; then
  echo "[entrypoint] provision OK"
else
  echo "[entrypoint] WARNING: provision failed; see /workspace/logs"
fi

if [[ "${STARTUP_SLEEP_ONLY:-0}" == "1" ]]; then
  echo "[entrypoint] sleep-only mode"; tail -f /dev/null
fi

if [[ "${START_CODE_SERVER:-1}" == "1" ]]; then
  LOG_CS="$LOG_DIR/code-server.$(date +%Y%m%dT%H%M%S).log"
  nohup code-server --bind-addr 0.0.0.0:${CODE_SERVER_PORT} --auth none /workspace >>"$LOG_CS" 2>&1 &
fi

if [[ "${START_JUPYTER:-1}" == "1" ]]; then
  LOG_J="$LOG_DIR/jupyter.$(date +%Y%m%dT%H%M%S).log"
  JVENV=/workspace/.venvs/jupyter
  [[ -d "$JVENV" ]] || (python3 -m venv "$JVENV" && "$JVENV/bin/pip" install -U pip wheel setuptools jupyterlab)
  nohup "$JVENV/bin/jupyter" lab --ip=0.0.0.0 --port="${JUPYTER_PORT}" --no-browser \
        --ServerApp.token="${JUPYTER_TOKEN:-}" --ServerApp.allow_origin='*' >>"$LOG_J" 2>&1 &
fi

# ComfyUI is manual-only (policy); allow opt-in
if [[ "${START_COMFYUI:-0}" == "1" ]]; then /workspace/bin/comfyctl start || true; fi

# Keep PID 1 alive; stream logs
touch "$LOG_DIR/.sentinel"; exec tail -n +1 -F "$LOG_DIR/"*.log "$LOG_DIR/.sentinel"
BASH
RUN chmod +x /scripts/entrypoint.sh

# provision_all.sh (inline)
RUN set -eux; cat > /scripts/provision_all.sh <<'BASH'
#!/usr/bin/env bash
set -Eeuo pipefail
LOG_DIR=/workspace/logs; mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/provision.$(date +%Y%m%dT%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "[provision] begin $(date -Iseconds)"

CVENV=/workspace/.venvs/comfyui-perf
if [[ ! -d "$CVENV" ]]; then
  python3 -m venv "$CVENV"
  "$CVENV/bin/pip" install -U pip wheel setuptools
fi

"$CVENV/bin/pip" install \
  "torch==2.8.0+cu128" "torchvision==0.19.0+cu128" "torchaudio==2.8.0+cu128" \
  --extra-index-url https://download.pytorch.org/whl/cu128
"$CVENV/bin/pip" install \
  "onnx==1.16.2" "onnxruntime-gpu==1.18.1" \
  "opencv-python-headless==4.11.0.86" "insightface==0.7.3"

if [[ ! -d /workspace/ComfyUI/.git ]]; then
  git clone --depth=1 https://github.com/comfyanonymous/ComfyUI /workspace/ComfyUI
fi

BIN=/workspace/bin; mkdir -p "$BIN"
cat > /workspace/bin/comfyctl <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
PY=/workspace/.venvs/comfyui-perf/bin/python
LOG=/workspace/logs/comfyui.$(date +%Y%m%dT%H%M%S).log
CMD="$PY -u /workspace/ComfyUI/main.py --listen 0.0.0.0 --port ${COMFY_PORT:-3000}"
case "${1:-start}" in
  start) pkill -f "python.*ComfyUI/main.py" || true; nohup $CMD >>"$LOG" 2>&1 & \
         for i in $(seq 1 180); do curl -sI 127.0.0.1:${COMFY_PORT:-3000}/ | grep -q '200 OK' && { echo READY; exit 0; }; sleep 1; done; \
         echo "NOT READY (timeout)"; exit 1;;
  stop) pkill -f "python.*ComfyUI/main.py" || true; echo STOPPED;;
  restart) "$0" stop; "$0" start;;
  *) echo "Usage: comfyctl {start|stop|restart}"; exit 2;;
esac
EOF
chmod +x /workspace/bin/comfyctl

python3 - <<'PY'
import sys; print("python:", sys.version)
import cv2, onnx, onnxruntime as ort
print("cv2:", cv2.__version__); print("onnx:", onnx.__version__); print("ort:", ort.__version__)
PY

echo "[provision] done $(date -Iseconds)"
BASH
RUN chmod +x /scripts/provision_all.sh

EXPOSE 3000 3100 3400 3600
ENTRYPOINT ["/scripts/entrypoint.sh"]
