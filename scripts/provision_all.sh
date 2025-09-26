#!/usr/bin/env bash
set -euo pipefail

PROVISION_VERSION="${PROVISION_VERSION:-2025-09-26-v4}"
STAMP="/workspace/.provision/complete-${PROVISION_VERSION}"
LOG="/workspace/logs/provision.$(date +%Y%m%dT%H%M%S).log"
echo "[provision] begin ${PROVISION_VERSION}" | tee -a "$LOG"

VENV_BASE=/workspace/.venvs
mkdir -p /workspace/{bin,models,notebooks,logs,ComfyUI,ai-toolkit,.provision} "$VENV_BASE"

ensure_venv () {
  local name="$1"
  local path="$VENV_BASE/$name"
  if [[ ! -d "$path" ]]; then
    python -m venv "$path"
    "$path/bin/pip" install -U pip wheel setuptools "numpy<2.1"
    echo "[provision] created venv $name" | tee -a "$LOG"
  fi
  echo "$path"
}

# --- ComfyUI venv ---
COMFY_VENV="$(ensure_venv comfyui-perf)"
TORCH_SPEC='torch==2.8.0+cu128 torchvision==0.19.0+cu128 torchaudio==2.8.0+cu128 --index-url https://download.pytorch.org/whl/cu128'
"$COMFY_VENV/bin/pip" install $TORCH_SPEC \
  onnx==1.16.2 onnxruntime-gpu==1.18.1 \
  opencv-python-headless==4.11.0.86 \
  insightface==0.7.3 | tee -a "$LOG"

# --- ComfyUI repo ---
if [[ ! -d /workspace/ComfyUI/.git ]]; then
  echo "[provision] cloning ComfyUI" | tee -a "$LOG"
  git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI | tee -a "$LOG"
else
  echo "[provision] ComfyUI repo exists; skipping clone" | tee -a "$LOG"
fi

# --- Jupyter ---
JUPY_VENV="$(ensure_venv jupyter)"
"$JUPY_VENV/bin/pip" install -U jupyterlab | tee -a "$LOG"

# --- code-server ---
CS_VERSION="4.89.1"
CS_DIR="/workspace/bin/code-server-${CS_VERSION}"
if [[ ! -x /workspace/bin/code-server ]]; then
  echo "[provision] installing code-server ${CS_VERSION}" | tee -a "$LOG"
  mkdir -p "$CS_DIR"
  curl -fsSL "https://github.com/coder/code-server/releases/download/v${CS_VERSION}/code-server-${CS_VERSION}-linux-amd64.tar.gz" \
    | tar -xz -C "$CS_DIR" --strip-components=1
  ln -sf "$CS_DIR/bin/code-server" /workspace/bin/code-server
  echo "[provision] code-server installed" | tee -a "$LOG"
else
  echo "[provision] code-server present; skipping" | tee -a "$LOG"
fi

# --- Launchers ---
cat >/workspace/bin/comfyctl <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
VENV=/workspace/.venvs/comfyui-perf
LOG=/workspace/logs/comfyui.$(date +%Y%m%dT%H%M%S).log
CMD="$VENV/bin/python -X faulthandler -u /workspace/ComfyUI/main.py --listen 0.0.0.0 --port ${COMFY_PORT:-3000}"
case "${1:-start}" in
  start) pkill -f "python.*ComfyUI/main.py" || true; nohup bash -lc "$CMD" >> "$LOG" 2>&1 & echo "ComfyUI starting… log=$LOG";;
  stop)  pkill -f "python.*ComfyUI/main.py" || true; echo "ComfyUI stopped." ;;
  log)   tail -n 200 -f "$LOG" ;;
  *)     echo "usage: comfyctl {start|stop|log}"; exit 2;;
esac
EOS
chmod +x /workspace/bin/comfyctl

cat >/workspace/bin/jupyterctl <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
VENV=/workspace/.venvs/jupyter
LOG=/workspace/logs/jupyter.$(date +%Y%m%dT%H%M%S).log
case "${1:-start}" in
  start) nohup "$VENV/bin/jupyter" lab --ip 0.0.0.0 --port ${JUPYTER_PORT:-3600} --allow-root --NotebookApp.token= --NotebookApp.password= >> "$LOG" 2>&1 & echo "Jupyter starting… log=$LOG";;
  stop)  pkill -f "jupyter.*lab" || true; echo "Jupyter stopped." ;;
  log)   tail -n 200 -f "$LOG" ;;
  *)     echo "usage: jupyterctl {start|stop|log}"; exit 2;;
esac
EOS
chmod +x /workspace/bin/jupyterctl

cat >/workspace/bin/codesrvctl <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
BIN=/workspace/bin/code-server
LOG=/workspace/logs/code-server.$(date +%Y%m%dT%H%M%S).log
CMD="$BIN --bind-addr 0.0.0.0:${CODE_SERVER_PORT:-3100} --auth none /workspace"
case "${1:-start}" in
  start) pkill -f "code-server.*bind-addr" || true; nohup bash -lc "$CMD" >> "$LOG" 2>&1 & echo "code-server starting… log=$LOG";;
  stop)  pkill -f "code-server.*bind-addr" || true; echo "code-server stopped." ;;
  log)   tail -n 200 -f "$LOG" ;;
  *)     echo "usage: codesrvctl {start|stop|log}"; exit 2;;
esac
EOS
chmod +x /workspace/bin/codesrvctl

echo "${PROVISION_VERSION}" > "$STAMP"
echo "[provision] complete ${PROVISION_VERSION}" | tee -a "$LOG"
