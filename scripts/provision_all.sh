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

# upgrade pip toolchain
"${VENV_DIR}/bin/python" -m pip install --upgrade --timeout 300 pip wheel setuptools "packaging<25" >/dev/null

# ---- PyTorch stack (CUDA 12.8) via extra index, with fallback ----
PIP="${VENV_DIR}/bin/pip"
install_torch() {
  log "pip: installing torch ${TORCH_VERSION}, torchvision ${TV_VERSION}, torchaudio ${TA_VERSION} (CUDA 12.8)"
  if "${PIP}" install --prefer-binary --timeout 600 \
      --extra-index-url https://download.pytorch.org/whl/cu128_full \
      torch=="${TORCH_VERSION}" torchvision=="${TV_VERSION}" torchaudio=="${TA_VERSION}"; then
    return 0
  fi
  log "pip: fallback to cu128 index"
  "${PIP}" install --prefer-binary --timeout 600 \
      --index-url https://download.pytorch.org/whl/cu128 \
      torch=="${TORCH_VERSION}" torchvision=="${TV_VERSION}" torchaudio=="${TA_VERSION}"
}
install_torch

# Triton (optional; ignore failures)
"${PIP}" install --prefer-binary --timeout 600 \
  --extra-index-url https://download.pytorch.org/whl \
  triton=="${TRITON_VERSION}" || log "triton optional: continuing"

# Baseline libs
"${PIP}" install --prefer-binary --timeout 600 \
  onnxruntime-gpu=="${ORT_VERSION}" opencv-python-headless=="${OPENCV_VERSION}" \
  fastapi uvicorn pydantic tqdm pillow requests >/dev/null

# ---- ComfyUI repo (idempotent) ----
if [ ! -d "${COMFY_DIR}/.git" ]; then
  log "git: cloning ComfyUI"
  git clone --depth=1 "${COMFY_REPO}" "${COMFY_DIR}"
else
  log "git: ComfyUI exists; pulling"
  git -C "${COMFY_DIR}" pull --ff-only || true
fi

# ---- comfyctl utility (drop-in) ----
COMFYCTL="${WORKSPACE}/bin/comfyctl"
cat > "${COMFYCTL}" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
CMD="${1:-status}"
PORT="${COMFY_PORT:-3000}"
WORKSPACE="${WORKSPACE:-/workspace}"
VENV="${WORKSPACE}/.venvs/comfyui-perf"
APP="${WORKSPACE}/ComfyUI/main.py"
LOG="${WORKSPACE}/logs/comfyui.$(date +%Y%m%dT%H%M%S).log"

case "$CMD" in
  start)
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
    tail -n 200 -F "$LOG"
    ;;
  *)
    echo "usage: $0 {start|stop|status|logs}"; exit 2;;
esac
EOS
chmod +x "${COMFYCTL}"

# ---- sanity print ----
"${VENV_DIR}/bin/python" - <<'PY' || true
import torch, sys
print("Torch:", torch.__version__, "CUDA:", getattr(torch.version, "cuda", None), "avail:", torch.cuda.is_available())
try:
    import torchvision as tv; print("Vision:", tv.__version__)
    import torchaudio as ta; print("Audio:", ta.__version__)
except Exception as e:
    print("Torch extras missing:", e)
try:
    import triton; print("Triton:", triton.__version__)
except Exception as e:
    print("Triton missing:", e)
try:
    import onnxruntime as ort; print("ORT:", ort.__version__)
    import cv2; print("OpenCV:", cv2.__version__)
except Exception as e:
    print("I/O libs issue:", e)
PY

log "provision: complete"
