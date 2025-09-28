# syntax=docker/dockerfile:1.7
FROM nvidia/cuda:12.8.0-runtime-ubuntu24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG CODE_SERVER_VERSION=4.92.2

# ---- Base OS + Python + tools (build-time apt only) ----
RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    python3 python3-venv python3-pip python3-dev \
    git curl ca-certificates unzip iproute2 procps \
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender1; \
  rm -rf /var/lib/apt/lists/*

# ---- Workspace skeleton ----
RUN set -eux; mkdir -p /workspace/{bin,models,logs,notebooks,ComfyUI,ai-toolkit,.venvs} /scripts /workspace/.locks

# ---- Bake code-server (no runtime download) ----
RUN set -eux; \
  curl -L "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz" \
    | tar -xz -C /opt; \
  ln -sf /opt/code-server-${CODE_SERVER_VERSION}-linux-amd64/bin/code-server /usr/local/bin/code-server

# ---- Runtime contract & toggles ----
ENV COMFY_PORT=3000 \
    CODE_SERVER_PORT=3100 \
    JUPYTER_PORT=3600 \
    OSTRIS_PORT=3400 \
    START_CODE_SERVER=1 \
    START_JUPYTER=0 \
    START_COMFYUI=0 \
    START_OSTRIS=0 \
    STARTUP_SLEEP_ONLY=0 \
    SKIP_PROVISION=0 \
    SAFE_START=0
# optional: JUPYTER_TOKEN (set in RunPod if you enable Jupyter)

# ---- entrypoint.sh (SAFE_START + soft-fail + sidecars; unchanged) ----
RUN set -eux; cat > /scripts/entrypoint.sh <<'BASH'
#!/usr/bin/env bash
set -Eeuo pipefail
LOG_DIR=/workspace/logs; mkdir -p "$LOG_DIR"
echo "[entrypoint] $(date -Iseconds)"

# Emergency: skip everything and keep container alive
if [[ "${SAFE_START:-0}" == "1" ]]; then
  echo "[entrypoint] SAFE_START=1 → skipping provision + sidecars"
  exec tail -f /dev/null
fi

# Always try provision unless explicitly skipped (soft-fail)
if [[ "${SKIP_PROVISION:-0}" == "1" ]]; then
  echo "[entrypoint] SKIP_PROVISION=1 → not running provision"
else
  if /scripts/provision_all.sh; then
    echo "[entrypoint] provision OK"
  else
    echo "[entrypoint] WARNING: provision failed (soft-fail). See /workspace/logs."
  fi
fi

# Optional sleep-only mode for debugging after provision phase
if [[ "${STARTUP_SLEEP_ONLY:-0}" == "1" ]]; then
  echo "[entrypoint] STARTUP_SLEEP_ONLY=1 → sleeping"
  exec tail -f /dev/null
fi

# Sidecars (ComfyUI is manual-only by policy)
if [[ "${START_CODE_SERVER:-1}" == "1" ]]; then
  LOG_CS="$LOG_DIR/code-server.$(date +%Y%m%dT%H%M%S).log"
  nohup code-server --bind-addr 0.0.0.0:${CODE_SERVER_PORT:-3100} --auth none /workspace >>"$LOG_CS" 2>&1 &
fi

if [[ "${START_JUPYTER:-0}" == "1" ]]; then
  LOG_J="$LOG_DIR/jupyter.$(date +%Y%m%dT%H%M%S).log"
  JVENV=/workspace/.venvs/jupyter
  [[ -d "$JVENV" ]] || (python3 -m venv "$JVENV" && "$JVENV/bin/pip" install -U pip wheel setuptools jupyterlab)
  nohup "$JVENV/bin/jupyter" lab \
        --ip=0.0.0.0 --port="${JUPYTER_PORT:-3600}" --no-browser \
        --ServerApp.token="${JUPYTER_TOKEN:-}" \
        --ServerApp.allow_origin='*' >>"$LOG_J" 2>&1 &
fi

# Keep PID 1 alive and stream logs
touch "$LOG_DIR/.sentinel"
exec tail -n +1 -F "$LOG_DIR/"*.log "$LOG_DIR/.sentinel"
BASH
RUN chmod +x /scripts/entrypoint.sh

# ---- provision_all.sh (IDEMPOTENT + LOCK + FETCH/RESET) ----
RUN set -eux; cat > /scripts/provision_all.sh <<'BASH'
#!/usr/bin/env bash
set -Eeuo pipefail

LOG_DIR=/workspace/logs
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/provision.$(date +%Y%m%dT%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "[provision] begin $(date -Iseconds)"

# Respect SKIP_PROVISION (diagnostics mode)
if [[ "${SKIP_PROVISION:-0}" == "1" ]]; then
  echo "[provision] SKIP_PROVISION=1 → skipping provision safely"
  exit 0
fi

# 0) Serialize provisioning to avoid parallel races
LOCKDIR="/workspace/.locks"; mkdir -p "$LOCKDIR"
LOCKFILE="$LOCKDIR/provision.lock"
if command -v flock >/dev/null 2>&1; then
  exec 9> "$LOCKFILE"
  flock -w 120 9 || { echo "[provision] ERROR: lock timeout"; exit 1; }
else
  for i in $(seq 1 120); do
    mkdir "$LOCKFILE".d 2>/dev/null && break || sleep 1
  done
  trap 'rmdir "$LOCKFILE".d 2>/dev/null || true' EXIT
fi

# 1) Python venv + core stacks (pins as per image policy)
CVENV=/workspace/.venvs/comfyui-perf
if [[ ! -d "$CVENV" ]]; then
  echo "[provision] create venv @ $CVENV"
  python3 -m venv "$CVENV"
  "$CVENV/bin/pip" install -U pip wheel setuptools
fi

echo "[provision] install torch stack (CUDA 12.8)"
"$CVENV/bin/pip" install \
  "torch==2.8.0+cu128" "torchvision==0.23.0+cu128" "torchaudio==2.8.0+cu128" \
  --extra-index-url https://download.pytorch.org/whl/cu128

echo "[provision] install core libs"
"$CVENV/bin/pip" install -U \
  "numpy<2" \
  "onnx==1.17.0" \
  "onnxruntime-gpu==1.18.1" \
  "opencv-python-headless==4.11.0.86" \
  "insightface==0.7.3" \
  "protobuf>=4.25.1" \
  "transformers==4.56.2" \
  "tokenizers==0.22.1" \
  "tqdm" "pyyaml"

# Ensure GUI cv2 is not present
"$CVENV/bin/pip" uninstall -y opencv-python || true

# 2) ComfyUI repo — idempotent + tolerant
REPO_DIR="/workspace/ComfyUI"
REPO_URL="https://github.com/comfyanonymous/ComfyUI.git"

ensure_repo () {
  if [[ -d "$REPO_DIR/.git" ]]; then
    echo "[provision] ComfyUI git repo present — fetch/reset"
    if git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      git -C "$REPO_DIR" remote set-url origin "$REPO_URL" || true
      git -C "$REPO_DIR" fetch --all --prune --depth=1
      CURR=$(git -C "$REPO_DIR" symbolic-ref --quiet --short HEAD || echo "")
      if [[ -n "$CURR" ]] && git -C "$REPO_DIR" rev-parse --verify "origin/$CURR" >/dev/null 2>&1; then
        git -C "$REPO_DIR" reset --hard "origin/$CURR"
      else
        git -C "$REPO_DIR" reset --hard origin/main || git -C "$REPO_DIR" reset --hard origin/master
      fi
      return 0
    fi
  fi

  if [[ -f "$REPO_DIR/main.py" && ! -d "$REPO_DIR/.git" ]]; then
    echo "[provision] ComfyUI code present (non-git) — leaving as-is"
    return 0
  fi

  if [[ -d "$REPO_DIR" && ! -d "$REPO_DIR/.git" ]]; then
    TS=$(date +%Y%m%dT%H%M%S)
    echo "[provision] non-git directory at $REPO_DIR — preserving to ${REPO_DIR}._stray_${TS}"
    mv "$REPO_DIR" "${REPO_DIR}._stray_${TS}"
  fi

  echo "[provision] cloning ComfyUI"
  git clone --depth=1 "$REPO_URL" "$REPO_DIR" || {
    echo "[provision] WARNING: clone failed but continuing (directory may exist)"; true;
  }
}

ensure_repo

# 3) comfyctl helper (manual-only by policy)
install -d /workspace/bin
cat >/workspace/bin/comfyctl <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
unset PYTHONPATH
export PATH="/workspace/.venvs/comfyui-perf/bin:$PATH"
export GIT_PYTHON_GIT_EXECUTABLE=/usr/bin/git
export GIT_PYTHON_REFRESH=quiet

PY=/workspace/.venvs/comfyui-perf/bin/python
LOG=/workspace/logs/comfyui.$(date +%Y%m%dT%H%M%S).log
CMD="$PY -u /workspace/ComfyUI/main.py --listen 0.0.0.0 --port ${COMFY_PORT:-3000}"

case "${1:-start}" in
  start)
    pkill -f "python.*ComfyUI/main.py" || true
    nohup $CMD >>"$LOG" 2>&1 &
    for i in $(seq 1 180); do
      curl -sI 127.0.0.1:${COMFY_PORT:-3000}/ | grep -q '200 OK' && { echo READY; exit 0; }
      sleep 1
    done
    echo "NOT READY (timeout)"; exit 1;;
  stop)
    pkill -f "python.*ComfyUI/main.py" || true
    echo STOPPED;;
  restart)
    "$0" stop; "$0" start;;
  *)
    echo "Usage: comfyctl {start|stop|restart}"; exit 2;;
esac
EOF
chmod +x /workspace/bin/comfyctl

# 4) Sanity import (surface pins + CUDA availability)
echo "[provision] sanity import"
"$CVENV/bin/python" - <<'PY'
import torch, torchvision, torchaudio, numpy as np, cv2, onnx, onnxruntime as ort, transformers, tokenizers
print("torch", torch.__version__, "| tv", torchvision.__version__, "| ta", torchaudio.__version__)
print("numpy", np.__version__, "| cv2", cv2.__version__, "| onnx", onnx.__version__, "| ort", ort.__version__)
print("transformers", transformers.__version__, "| tokenizers", tokenizers.__version__)
print("cuda_available", torch.cuda.is_available(), "| devices", torch.cuda.device_count())
PY

echo "[provision] done $(date -Iseconds)"
BASH
RUN chmod +x /scripts/provision_all.sh

EXPOSE 3000 3100 3400 3600
ENTRYPOINT ["/scripts/entrypoint.sh"]
