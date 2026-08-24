#!/usr/bin/env bash
set -euo pipefail

# ---- settings ----
WORKSPACE="${WORKSPACE:-/workspace}"
VENV_DIR="${WORKSPACE}/.venvs/comfyui-perf"
COMFY_REPO="${COMFY_REPO:-https://github.com/comfyanonymous/ComfyUI.git}"
COMFY_DIR="${WORKSPACE}/ComfyUI"

TORCH_VERSION="${TORCH_VERSION:-2.8.0}"
TV_VERSION="${TV_VERSION:-0.23.0}"
TA_VERSION="${TA_VERSION:-2.8.0}"
TRITON_VERSION="${TRITON_VERSION:-3.4.0}"
ORT_VERSION="${ORT_VERSION:-1.18.1}"
OPENCV_VERSION="${OPENCV_VERSION:-4.11.0.86}"

log(){ printf '%s %s\n' "[$(date +'%Y-%m-%dT%H:%M:%S')]" "$*"; }

# ---- ensure venv ----
if [ ! -x "${VENV_DIR}/bin/python" ]; then
  log "venv: creating ${VENV_DIR}"
  python3 -m venv "${VENV_DIR}"
fi

# upgrade pip toolchain & ensure setuptools/pkg_resources are permanently present
"${VENV_DIR}/bin/python" -m pip install --upgrade --timeout 300 \
  pip wheel setuptools "packaging<25" av >/dev/null

PIP="${VENV_DIR}/bin/pip"

# ---- PyTorch stack (CUDA 12.8) ----
install_torch() {
  log "pip: ensuring torch ${TORCH_VERSION}+cu128, torchvision ${TV_VERSION}+cu128, torchaudio ${TA_VERSION}+cu128"
  "${PIP}" install --prefer-binary --timeout 600 \
      --extra-index-url https://download.pytorch.org/whl/cu128 \
      torch=="${TORCH_VERSION}+cu128" torchvision=="${TV_VERSION}+cu128" torchaudio=="${TA_VERSION}+cu128"
}
install_torch

# Triton
"${PIP}" install --prefer-binary --timeout 600 \
  --extra-index-url https://download.pytorch.org/whl \
  triton=="${TRITON_VERSION}" || log "triton optional: continuing"

# Baseline libs
"${PIP}" install --prefer-binary --timeout 600 \
  onnxruntime-gpu=="${ORT_VERSION}" opencv-python-headless=="${OPENCV_VERSION}" \
  fastapi uvicorn pydantic tqdm pillow requests >/dev/null

# ---- 1. Hardware Attention Kernels (SageAttention + Flash-Attention) ----
log "pip: checking / installing SageAttention and Flash-Attention"
export TORCH_CUDA_ARCH_LIST="8.9;9.0"
"${PIP}" install --prefer-binary sageattention || log "sageattention failed"
"${PIP}" install --prefer-binary flash-attn --no-build-isolation || log "flash-attn failed"

# ---- 2. Audio DSP & Voice Conversion Stack ----
log "pip: ensuring clean audio libraries"
"${PIP}" install --prefer-binary \
  sounddevice soundfile librosa==0.10.1 perth resemble-perth \
  hyperpyyaml ruamel.yaml pyloudnorm conformer s3tokenizer

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

# ---- sanity check ----
"${VENV_DIR}/bin/python" - <<'PY' || true
import torch
print("--- GPU SANITY CHECK ---")
print("PyTorch:", torch.__version__, "| CUDA:", torch.cuda.is_available())
if torch.cuda.is_available():
    print("GPU:", torch.cuda.get_device_name(0))
try:
    import sageattention; print("SageAttention: READY")
except Exception as e:
    print("SageAttention:", e)
try:
    import flash_attn; print("FlashAttention: READY")
except Exception as e:
    print("FlashAttention:", e)
try:
    import sounddevice; print("SoundDevice (PortAudio): READY")
except Exception as e:
    print("SoundDevice:", e)
PY

log "provision: complete"
