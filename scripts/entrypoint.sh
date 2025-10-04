#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

LOG_DIR=/workspace/logs; mkdir -p "$LOG_DIR"
SRC_VENV=/opt/venvs/comfyui-perf
VENV=/workspace/.venvs/comfyui-perf

if [ ! -x "$VENV/bin/python" ]; then
  mkdir -p "$(dirname "$VENV")"
  cp -a "$SRC_VENV" "$VENV"
fi

/scripts/provision_all.sh || true

if [ -x "$VENV/bin/python" ]; then
  "$VENV/bin/python" - <<'PY' | tee -a "$LOG_DIR/sanity.$(date +%Y%m%dT%H%M%S).log"
import sys, cv2, torch, onnxruntime
print(sys.executable)
print(torch.__version__, torch.cuda.is_available())
print(getattr(cv2,'__file__','n/a'))
print(onnxruntime.__version__)
PY
fi

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

if [ "${START_COMFYUI:-0}" = "1" ]; then /workspace/bin/comfyctl start || true; fi
if [ "${START_JUPYTER:-0}" = "1" ]; then
  . "$VENV/bin/activate"
  jupyter lab --no-browser --NotebookApp.token="${JUPYTER_TOKEN:-changeme}" \
    --ServerApp.port="${JUPYTER_PORT:-3600}" --ServerApp.ip=0.0.0.0 \
    >/workspace/logs/jupyter.log 2>&1 &
  deactivate || true
fi
if [ "${START_OSTRIS:-0}" = "1" ]; then /workspace/bin/aikitctl || true; fi
if [ "${START_OSTRISDASH:-0}" = "1" ]; then /workspace/bin/aikituictl || true; fi

exec tail -f /dev/null
