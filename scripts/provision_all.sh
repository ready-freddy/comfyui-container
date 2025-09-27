#!/usr/bin/env bash
set -Eeuo pipefail
LOG_DIR=/workspace/logs
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/provision.$(date +%Y%m%dT%H%M%S).log"

# Mirror stdout/stderr to file AND container logs
exec > >(tee -a "$LOG_FILE") 2>&1
echo "[provision] begin $(date -Iseconds)"

# --- Comfy venv ---
CVENV=/workspace/.venvs/comfyui-perf
if [[ ! -d "$CVENV" ]]; then
  echo "[provision] create venv @ $CVENV"
  python3 -m venv "$CVENV"
  "$CVENV/bin/pip" install -U pip wheel setuptools
fi

# Pinned userland per baseline
echo "[provision] install pinned packages"
"$CVENV/bin/pip" install \
  "torch==2.8.0+cu128" "torchvision==0.19.0+cu128" "torchaudio==2.8.0+cu128" \
  --extra-index-url https://download.pytorch.org/whl/cu128
"$CVENV/bin/pip" install \
  "onnx==1.16.2" "onnxruntime-gpu==1.18.1" \
  "opencv-python-headless==4.11.0.86" "insightface==0.7.3"

# --- ComfyUI repo (disposable) ---
if [[ ! -d /workspace/ComfyUI/.git ]]; then
  echo "[provision] clone ComfyUI"
  git clone --depth=1 https://github.com/comfyanonymous/ComfyUI /workspace/ComfyUI
fi

# --- comfyctl helper ---
BIN=/workspace/bin
mkdir -p "$BIN"
cat >/workspace/bin/comfyctl <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
PY=/workspace/.venvs/comfyui-perf/bin/python
LOG=/workspace/logs/comfyui.$(date +%Y%m%dT%H%M%S).log
CMD="$PY -u /workspace/ComfyUI/main.py --listen 0.0.0.0 --port ${COMFY_PORT:-3000}"
case "${1:-start}" in
  start)
    pkill -f "python.*ComfyUI/main.py" || true
    nohup $CMD >>"$LOG" 2>&1 &
    for i in $(seq 1 180); do curl -sI 127.0.0.1:${COMFY_PORT:-3000}/ | grep -q '200 OK' && echo READY && exit 0; sleep 1; done
    echo "NOT READY (timeout)"; exit 1;;
  stop) pkill -f "python.*ComfyUI/main.py" || true; echo STOPPED;;
  restart) "$0" stop; "$0" start;;
  *) echo "Usage: comfyctl {start|stop|restart}"; exit 2;;
esac
EOF
chmod +x /workspace/bin/comfyctl

# --- sanity imports ---
echo "[provision] sanity import: cv2 / onnx / onnxruntime"
"$CVENV/bin/python" - <<'PY'
import sys; print("python:", sys.version)
import cv2, onnx, onnxruntime as ort
print("cv2:", cv2.__version__)
print("onnx:", onnx.__version__)
print("ort:", ort.__version__)
PY

echo "[provision] done $(date -Iseconds)"
