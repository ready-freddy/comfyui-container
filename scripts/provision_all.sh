#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
VENV_DIR="${WORKSPACE}/.venvs/comfyui-perf"
COMFY_REPO="${COMFY_REPO:-https://github.com/comfyanonymous/ComfyUI.git}"
COMFY_DIR="${WORKSPACE}/ComfyUI"

export CUDA_HOME="/usr/local/cuda"
export TORCH_CUDA_ARCH_LIST="8.9;9.0"
export LD_LIBRARY_PATH="/usr/local/cuda-12.8/compat:/usr/local/cuda/compat:/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"

log(){ printf '%s %s\n' "[$(date +'%Y-%m-%dT%H:%M:%S')]" "$*"; }

PIP="${VENV_DIR}/bin/pip"

# ---- Ensure audio and runtime helper libraries ----
log "pip: verifying audio and runtime requirements"
"${PIP}" install --prefer-binary \
  sounddevice soundfile librosa==0.10.1 perth resemble-perth \
  hyperpyyaml ruamel.yaml pyloudnorm conformer s3tokenizer >/dev/null

# ---- ComfyUI repo (idempotent) ----
if [ ! -d "${COMFY_DIR}/.git" ]; then
  log "git: cloning ComfyUI"
  git clone --depth=1 "${COMFY_REPO}" "${COMFY_DIR}"
else
  log "git: ComfyUI exists; pulling"
  git -C "${COMFY_DIR}" pull --ff-only || true
fi

# ---- comfyctl utility ----
COMFYCTL="${WORKSPACE}/bin/comfyctl"
cat > "${COMFYCTL}" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
CMD="${1:-status}"
PORT="${COMFY_PORT:-3000}"
WORKSPACE="${WORKSPACE:-/workspace}"
VENV="${WORKSPACE}/.venvs/comfyui-perf"
APP="${WORKSPACE}/ComfyUI/main.py"

export CUDA_HOME="/usr/local/cuda"
export TORCH_CUDA_ARCH_LIST="8.9;9.0"
export LD_LIBRARY_PATH="/usr/local/cuda-12.8/compat:/usr/local/cuda/compat:/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"

case "$CMD" in
  start)
    LOG="${WORKSPACE}/logs/comfyui.$(date +%Y%m%dT%H%M%S).log"
    pkill -f "python.*ComfyUI/main.py" || true
    nohup "${VENV}/bin/python" -u "$APP" --listen 0.0.0.0 --port "$PORT" >>"$LOG" 2>&1 &
    echo "started :$PORT (log $LOG)"
    ;;
  stop)
    pkill -f "python.*ComfyUI/main.py" || true
    echo "stopped"
    ;;
  status)
    pgrep -f "python.*ComfyUI/main.py" >/dev/null && echo "running" || echo "not running"
    ;;
  logs)
    LATEST_LOG=$(ls -t "${WORKSPACE}/logs"/comfyui.*.log 2>/dev/null | head -n1 || true)
    if [ -n "$LATEST_LOG" ] && [ -f "$LATEST_LOG" ]; then
      tail -n 200 -F "$LATEST_LOG"
    else
      echo "No log files found in ${WORKSPACE}/logs"
    fi
    ;;
  *)
    echo "usage: $0 {start|stop|status|logs}"; exit 2;;
esac
EOS
chmod +x "${COMFYCTL}"

# ---- Sanity check ----
"${VENV_DIR}/bin/python" - <<'PY' || true
import torch
print("--- GPU SANITY CHECK ---")
print("PyTorch:", torch.__version__, "| CUDA:", torch.cuda.is_available())
if torch.cuda.is_available():
    print("GPU:", torch.cuda.get_device_name(0), "| Capability:", torch.cuda.get_device_capability(0))
try:
    import comfy_kitchen; print("Comfy-Kitchen: READY (Native sm_89 Built)")
except Exception as e:
    print("Comfy-Kitchen:", e)
try:
    import flash_attn; print("FlashAttention: READY")
except Exception as e:
    print("FlashAttention:", e)
PY

log "provision: complete"
