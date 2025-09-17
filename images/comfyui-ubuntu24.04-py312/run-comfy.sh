#!/usr/bin/env bash
set -euo pipefail

# ---- Config (override via env if needed) ----
VENV_PATH="${VENV_PATH:-/workspace/.venvs/comfyui-perf}"
APP_PATH="${APP_PATH:-/workspace/ComfyUI}"
COMFY_PORT="${COMFY_PORT:-3000}"
CODE_SERVER_PORT="${CODE_SERVER_PORT:-3100}"
AI_TOOLKIT_PORT="${AI_TOOLKIT_PORT:-8675}"
START_COMFYUI="${START_COMFYUI:-0}"

log(){ printf "[run-comfy] %s\n" "$*"; }
mkdir -p /workspace/logs

# 1) Ensure venv exists (idempotent)
if [ ! -x "${VENV_PATH}/bin/python" ]; then
  log "Creating venv at ${VENV_PATH}"
  mkdir -p "$(dirname "${VENV_PATH}")"
  python3 -m venv "${VENV_PATH}"
  "${VENV_PATH}/bin/pip" install --upgrade pip wheel
fi

# 2) Start code-server (auto)
if ! pgrep -af "code-server.*--bind-addr 0.0.0.0:${CODE_SERVER_PORT}" >/dev/null 2>&1; then
  log "Starting code-server on :${CODE_SERVER_PORT}"
  nohup code-server --bind-addr 0.0.0.0:${CODE_SERVER_PORT} /workspace \
    >/workspace/logs/code-server.log 2>&1 &
else
  log "code-server already running"
fi

# 3) (Port reserved for AI-Toolkit on :${AI_TOOLKIT_PORT})

# 4) ComfyUI manual starter
start_comfy() {
  if [ ! -f "${APP_PATH}/main.py" ]; then
    log "ComfyUI not found at ${APP_PATH}. Mount or clone before starting."
    return 1
  fi
  if pgrep -af "python.*${APP_PATH}/main.py" >/dev/null 2>&1; then
    log "ComfyUI already running"
    return 0
  fi
  log "Starting ComfyUI on :${COMFY_PORT}"
  nohup "${VENV_PATH}/bin/python" "${APP_PATH}/main.py" \
      --listen 0.0.0.0 --port "${COMFY_PORT}" \
      >> /workspace/logs/comfyui.log 2>&1 &
  log "ComfyUI started; tail: /workspace/logs/comfyui.log"
}

# Auto-start only if explicitly enabled
if [ "${START_COMFYUI}" = "1" ]; then
  start_comfy || true
else
  log "ComfyUI is manual-only. Start later with:"
  log "  /usr/local/bin/run-comfy.sh comfy"
fi

# Subcommand to start on demand
if [ "${1:-}" = "comfy" ]; then
  start_comfy
  exit 0
fi

log "Container ready. code-server :${CODE_SERVER_PORT} | ComfyUI manual :${COMFY_PORT}"
tail -f /dev/null
