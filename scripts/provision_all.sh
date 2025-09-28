#!/usr/bin/env bash
set -Eeuo pipefail

LOG_DIR=/workspace/logs
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/provision.$(date +%Y%m%dT%H%M%S).log"

# Mirror stdout/stderr to file AND container logs
exec > >(tee -a "$LOG_FILE") 2>&1
echo "[provision] begin $(date -Iseconds)"

# --- Diagnostics switch: allow a clean skip when debugging ---
if [[ "${SKIP_PROVISION:-0}" == "1" ]]; then
  echo "[provision] SKIP_PROVISION=1 → skipping provision safely"
  exit 0
fi

# --- Comfy venv ---
CVENV=/workspace/.venvs/comfyui-perf
if [[ ! -d "$CVENV" ]]; then
  echo "[provision] create venv @ $CVENV"
  python3 -m venv "$CVENV"
  "$CVENV/bin/pip" install -U pip wheel setuptools
fi

# --- Torch stack (CUDA 12.8) ---
echo "[provision] install torch stack (CUDA 12.8)"
"$CVENV/bin/pip" install \
  "torch==2.8.0+cu128" "torchvision==0.23.0+cu128" "torchaudio==2.8.0+cu128" \
  --extra-index-url https://download.pytorch.org/whl/cu128

# --- Core libs (ABI-safe) + HF pins ---
echo "[provision] install core libs and HF pins"
"$CVENV/bin/pip" install -U \
  "numpy<2" \
  "onnx==1.17.0" \
  "onnxruntime-gpu==1.18.1" \
  "opencv-python-headless==4.11.0.86" \
  "insightface==0.7.3" \
  "protobuf>=4.25.1" \
  "transformers==4.56.2" \
  "tokenizers==0.22.1"

# Ensure GUI cv2 is NOT present (some nodes try to pull it)
"$CVENV/bin/pip" uninstall -y opencv-python || true

# --- ComfyUI repo (disposable) ---
if [[ ! -d /workspace/ComfyUI/.git ]]; then
  echo "[provision] clone ComfyUI"
  git clone --depth=1 https://github.com/comfyanonymous/ComfyUI /workspace/ComfyUI
fi

# --- comfyctl helper (ComfyUI stays manual-only) ---
BIN=/workspace/bin
mkdir -p "$BIN"
cat > /workspace/bin/comfyctl <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
export GIT_PYTHON_GIT_EXECUTABLE=/usr/bin/git
export GIT_PYTHON_REFRESH=quiet
PY=/workspace/.venvs/comfyui-perf/bin/python
LOG=/workspace/logs/comfyui.$(date +%Y%m%dT%H%M%S).log
CMD="$PY -u /workspace/ComfyUI/main.py --listen 0.0.0.0 --port ${COMFY_PORT:-3000}"
case "${1:-start}" in
  start)
    pkill -f "python.*ComfyUI/main.py" || true
    nohup $CMD >>"$LOG" 2>&1 &
    for i in $(seq 1 180); do curl -sI 127.0.0.1:${COMFY_PORT:-3000}/ | grep -q '200 OK' && { echo READY; exit 0; }; sleep 1; done
    echo "NOT READY (timeout)"; exit 1;;
  stop) pkill -f "python.*ComfyUI/main.py" || true; echo STOPPED;;
  restart) "$0" stop; "$0" start;;
  *) echo "Usage: comfyctl {start|stop|restart}"; exit 2;;
esac
EOF
chmod +x /workspace/bin/comfyctl

# --- sanity imports ---
echo "[provision] sanity import: torch/vision/audio | numpy/cv2 | onnx/ort | transformers"
"$CVENV/bin/python" - <<'PY'
import torch, torchvision, torchaudio, numpy as np, cv2, onnx, onnxruntime as ort, transformers
print("torch", torch.__version__, "| tv", torchvision.__version__, "| ta", torchaudio.__version__)
print("numpy", np.__version__, "| cv2", cv2.__version__, "| onnx", onnx.__version__, "| ort", ort.__version__)
print("transformers", transformers.__version__)
print("cuda_available", torch.cuda.is_available(), "| devices", torch.cuda.device_count())
PY

echo "[provision] done $(date -Iseconds)"
