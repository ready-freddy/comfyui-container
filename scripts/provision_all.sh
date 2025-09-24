#!/usr/bin/env bash
set -euo pipefail

# Idempotent, all-in provisioning into /workspace
PROVISION_VERSION="${PROVISION_VERSION:-2025-09-24-v1}"
STAMP="/workspace/.provision/complete-${PROVISION_VERSION}"
LOG="/workspace/logs/provision.$(date +%Y%m%dT%H%M%S).log"
echo "[provision] begin ${PROVISION_VERSION}" | tee -a "$LOG"

VENV_BASE=/workspace/.venvs
mkdir -p /workspace/{bin,models,notebooks,logs,ComfyUI,ai-toolkit} "$VENV_BASE"

ensure_venv () {
  local name="$1"
  local path="$VENV_BASE/$name"
  if [[ ! -d "$path" ]]; then
    python3 -m venv "$path"
    "$path/bin/pip" install -U pip wheel setuptools
    echo "[provision] created venv $name" | tee -a "$LOG"
  fi
  echo "$path"
}

# --- ComfyUI venv + Torch/ONNX ---
COMFY_VENV="$(ensure_venv comfyui-perf)"
TORCH_SPEC='torch==2.8.0+cu128 torchvision==0.19.0+cu128 torchaudio==2.8.0+cu128 --index-url https://download.pytorch.org/whl/cu128'
"$COMFY_VENV/bin/pip" install $TORCH_SPEC onnx onnxruntime-gpu==1.18.1 | tee -a "$LOG"

# --- ComfyUI repo (clone if missing) ---
if [[ ! -d /workspace/ComfyUI/.git ]]; then
  echo "[provision] cloning ComfyUI" | tee -a "$LOG"
  git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI | tee -a "$LOG"
else
  echo "[provision] ComfyUI repo exists; skipping clone" | tee -a "$LOG"
fi

# --- Jupyter venv + Lab ---
JUPY_VENV="$(ensure_venv jupyter)"
"$JUPY_VENV/bin/pip" install -U jupyterlab | tee -a "$LOG"

# --- code-server install (no apt; download binary) ---
CODESRV_VENV="$(ensure_venv codesrv)"
CS_VERSION="4.89.1"
CS_DIR="/workspace/bin/code-server-${CS_VERSION}"
if [[ ! -x /workspace/bin/code-server ]]; then
  echo "[provision] installing code-server ${CS_VERSION}" | tee -a "$LOG"
  mkdir -p "$CS_DIR"
  curl -fsSL "https://github.com/coder/code-server/releases/download/v${CS_VERSION}/code-server-${CS_VERSION}-linux-amd64.tar.gz" \
    | tar -xz -C "$CS_DIR" --strip-components=1
  ln -sf "$CS_DIR/bin/code-server" /workspace/bin/code-server
  echo "[provision] code-server installed at /workspace/bin/code-server" | tee -a "$LOG"
else
  echo "[provision] code-server present; skipping" | tee -a "$LOG"
fi

# --- AI Toolkit (Ostris) scaffold (optional) ---
OSTRIS_REPO="${OSTRIS_REPO:-}"
OSTRIS_REF="${OSTRIS_REF:-}"
if [[ -n "$OSTRIS_REPO" ]]; then
  OSTRIS_DIR="/workspace/ai-toolkit"
  if [[ ! -d "$OSTRIS_DIR/.git" ]]; then
    echo "[provision] cloning AI Toolkit from $OSTRIS_REPO $OSTRIS_REF" | tee -a "$LOG"
    git clone "$OSTRIS_REPO" "$OSTRIS_DIR" | tee -a "$LOG"
    if [[ -n "$OSTRIS_REF" ]]; then
      (cd "$OSTRIS_DIR" && git checkout "$OSTRIS_REF" && echo "[provision] checked out $OSTRIS_REF" | tee -a "$LOG")
    fi
  else
    echo "[provision] AI Toolkit repo exists; skipping clone" | tee -a "$LOG"
  fi
  AIT_VENV="$(ensure_venv ai-toolkit)"
  if [[ -f "$OSTRIS_DIR/pyproject.toml" || -f "$OSTRIS_DIR/setup.py" ]]; then
    "$AIT_VENV/bin/pip" install -U pip wheel setuptools | tee -a "$LOG"
    "$AIT_VENV/bin/pip" install -e "$OSTRIS_DIR" | tee -a "$LOG"
  fi
else
  echo "[provision] OSTRIS_REPO not set; toolkit provisioning skipped" | tee -a "$LOG"
fi

# --- Launchers: comfyctl, jupyterctl, codesrvctl, ai-toolkitctl ---
cat >/workspace/bin/comfyctl <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
VENV=/workspace/.venvs/comfyui-perf
LOG=/workspace/logs/comfyui.$(date +%Y%m%dT%H%M%S).log
CMD="$VENV/bin/python -X faulthandler -u /workspace/ComfyUI/main.py --listen 0.0.0.0 --port ${COMFY_PORT:-3000}"
case "${1:-start}" in
  start) nohup bash -lc "$CMD" > "$LOG" 2>&1 & echo "ComfyUI starting… log=$LOG";;
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
  start) nohup "$VENV/bin/jupyter" lab --ip 0.0.0.0 --port ${JUPYTER_PORT:-3600} --allow-root --NotebookApp.token= --NotebookApp.password= > "$LOG" 2>&1 & echo "Jupyter starting… log=$LOG";;
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
  start) nohup bash -lc "$CMD" > "$LOG" 2>&1 & echo "code-server starting… log=$LOG";;
  stop)  pkill -f "code-server.*bind-addr" || true; echo "code-server stopped." ;;
  log)   tail -n 200 -f "$LOG" ;;
  *)     echo "usage: codesrvctl {start|stop|log}"; exit 2;;
esac
EOS
chmod +x /workspace/bin/codesrvctl

cat >/workspace/bin/ai-toolkitctl <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
VENV=/workspace/.venvs/ai-toolkit
LOG=/workspace/logs/ai-toolkit.$(date +%Y%m%dT%H%M%S).log
if [[ -z "${OSTRIS_REPO:-}" ]]; then
  echo "AI Toolkit not configured (set OSTRIS_REPO/OSTRIS_REF env)."; exit 0
fi
CMD="$VENV/bin/python -m uvicorn app:app --host 0.0.0.0 --port ${OSTRIS_PORT:-3400}"
case "${1:-start}" in
  start) nohup bash -lc "$CMD" > "$LOG" 2>&1 & echo "AI Toolkit starting… log=$LOG";;
  stop)  pkill -f "uvicorn.*--port ${OSTRIS_PORT:-3400}" || true; echo "AI Toolkit stopped." ;;
  log)   tail -n 200 -f "$LOG" ;;
  *)     echo "usage: ai-toolkitctl {start|stop|log}"; exit 2;;
esac
EOS
chmod +x /workspace/bin/ai-toolkitctl

# Mark complete
echo "${PROVISION_VERSION}" > "$STAMP"
echo "[provision] complete ${PROVISION_VERSION}" | tee -a "$LOG"
