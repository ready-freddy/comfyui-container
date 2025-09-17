
#!/usr/bin/env bash
set -Eeuo pipefail

: "${START_COMFYUI:=0}"          # 0 = manual-only; 1 = auto-start ComfyUI
: "${ENABLE_CODE_SERVER:=1}"     # 1 = start code-server
: "${COMFY_PORT:=3000}"
: "${CODE_SERVER_PORT:=3100}"
: "${CODE_SERVER_PASSWORD:=}"    # set in env; if empty we’ll default below
: "${VENV_PATH:=/workspace/.venvs/comfyui-perf}"
: "${APP_PATH:=/workspace/ComfyUI}"

LOG_DIR="/workspace/logs"
mkdir -p "$LOG_DIR"

echo "[wrap] boot $(date -Iseconds)" | tee -a "$LOG_DIR/wrap.log"
echo "[wrap] APP_PATH=$APP_PATH VENV_PATH=$VENV_PATH START_COMFYUI=$START_COMFYUI" | tee -a "$LOG_DIR/wrap.log"

# (Optional) activate venv for convenience; not required for code-server
if [[ -d "$VENV_PATH" ]]; then
  # shellcheck disable=SC1090
  source "$VENV_PATH/bin/activate" || true
else
  echo "[wrap] WARN: venv not found at $VENV_PATH" | tee -a "$LOG_DIR/wrap.log"
fi

# --- code-server (auto) ---
if [[ "$ENABLE_CODE_SERVER" == "1" ]]; then
  if command -v code-server >/dev/null 2>&1; then
    # If a password is provided, code-server uses PASSWORD env; default to comfy-dev for convenience
    export PASSWORD="${CODE_SERVER_PASSWORD:-comfy-dev}"
    echo "[wrap] starting code-server on :${CODE_SERVER_PORT}" | tee -a "$LOG_DIR/wrap.log"
    nohup /usr/local/bin/code-server \
      --bind-addr "0.0.0.0:${CODE_SERVER_PORT}" \
      --auth password \
      >>"$LOG_DIR/code-server.log" 2>&1 &
    echo "[wrap] code-server pid=$!" | tee -a "$LOG_DIR/wrap.log"
  else
    echo "[wrap] ERR: code-server binary missing" | tee -a "$LOG_DIR/wrap.log"
  fi
fi

# --- ComfyUI (manual-first) ---
if [[ "$START_COMFYUI" == "1" ]]; then
  echo "[wrap] starting ComfyUI on :${COMFY_PORT}" | tee -a "$LOG_DIR/wrap.log"
  cd "$APP_PATH"
  exec python3 -u main.py --listen 0.0.0.0 --port "$COMFY_PORT" >>"$LOG_DIR/comfyui.log" 2>&1
else
  echo "[wrap] START_COMFYUI=0 → not starting ComfyUI (manual mode)" | tee -a "$LOG_DIR/wrap.log"
  # Keep container alive so web terminal works; no crash loop
  exec tail -f /dev/null
fi
