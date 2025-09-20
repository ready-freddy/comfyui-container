#!/usr/bin/env bash
set -euo pipefail

# ---- Config (override via env if needed) ----
VENV_PATH="${VENV_PATH:-/workspace/.venvs/comfyui-perf}"
APP_PATH="${APP_PATH:-/workspace/ComfyUI}"
COMFY_PORT="${COMFY_PORT:-3000}"
CODE_SERVER_PORT="${CODE_SERVER_PORT:-3100}"
AI_TOOLKIT_PORT="${AI_TOOLKIT_PORT:-8675}"
START_COMFYUI="${START_COMFYUI:-0}"
START_AI_TOOLKIT="${START_AI_TOOLKIT:-0}"
IMAGE_VENV="${IMAGE_VENV:-/opt/venvs/comfyui-perf}"   # baked venv (if image provides)

LOG_DIR="/workspace/logs"
mkdir -p "$LOG_DIR"

log(){ printf "[run-comfy] %s\n" "$*"; }

# 0) Seed from image venv/wheels if missing (idempotent)
if [ ! -x "${VENV_PATH}/bin/python" ] && [ -x "${IMAGE_VENV}/bin/python" ]; then
  log "Seeding venv from image → ${VENV_PATH}"
  mkdir -p "$(dirname "${VENV_PATH}")"
  cp -a "${IMAGE_VENV}" "${VENV_PATH}"
fi
if [ -d /opt/wheels ]; then
  mkdir -p /workspace/wheels
  rsync -a --ignore-existing /opt/wheels/ /workspace/wheels/ || true
fi

# 1) Ensure venv exists (idempotent fallback)
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
    >"${LOG_DIR}/code-server.log" 2>&1 &
else
  log "code-server already running"
fi

# 3) (Reserved) AI Toolkit block — OFF by default; requires /workspace/ai-toolkit/start.sh
start_ai_toolkit() {
  local START_SCRIPT="/workspace/ai-toolkit/start.sh"
  if [ ! -x "$START_SCRIPT" ]; then
    log "AI Toolkit start script not found at ${START_SCRIPT}; skipping."
    return 0
  fi
  if pgrep -af "ai-toolkit.*:${AI_TOOLKIT_PORT}" >/dev/null 2>&1 || nc -z 127.0.0.1 "${AI_TOOLKIT_PORT}" >/dev/null 2>&1; then
    log "AI Toolkit already running or port ${AI_TOOLKIT_PORT} in use; skipping."
    return 0
  fi
  log "Starting AI Toolkit on :${AI_TOOLKIT_PORT}"
  nohup "${START_SCRIPT}" --port "${AI_TOOLKIT_PORT}" \
    >"${LOG_DIR}/ai-toolkit.log" 2>&1 &
}
if [ "${START_AI_TOOLKIT}" = "1" ]; then
  start_ai_toolkit || true
else
  log "AI Toolkit is disabled (START_AI_TOOLKIT=0). Port reserved: ${AI_TOOLKIT_PORT}"
fi

# 4) ComfyUI manual starter
is_port_in_use() {
  (exec 3<>/dev/tcp/127.0.0.1/"$1") >/dev/null 2>&1 && { exec 3>&-; return 0; } || return 1
}

start_comfy() {
  if [ ! -f "${APP_PATH}/main.py" ]; then
    log "ComfyUI not found at ${APP_PATH}. Mount or clone before starting."
    return 1
  fi
  if pgrep -af "python.*${APP_PATH}/main.py" >/dev/null 2>&1; then
    log "ComfyUI already running"
    return 0
  fi
  if is_port_in_use "${COMFY_PORT}"; then
    log "Port ${COMFY_PORT} is already in use; not starting another instance."
    return 0
  fi
  log "Starting ComfyUI on :${COMFY_PORT}"
  nohup "${VENV_PATH}/bin/python" "${APP_PATH}/main.py" \
      --listen 0.0.0.0 --port "${COMFY_PORT}" \
      >> "${LOG_DIR}/comfyui.log" 2>&1 &
  log "ComfyUI started; tail: ${LOG_DIR}/comfyui.log"

  # quick readiness probe + snapshot
  for i in $(seq 1 90); do
    sleep 1
    if curl -fsS "http://127.0.0.1:${COMFY_PORT}/" >/dev/null 2>&1; then
      TS=$(date +%Y%m%dT%H%M%S)
      curl -fsS "http://127.0.0.1:${COMFY_PORT}/object_info?no_cache=1" \
        -o "${LOG_DIR}/object_info.${TS}.json" || true
      log "ComfyUI ready; snapshot saved: ${LOG_DIR}/object_info.${TS}.json"
      break
    fi
  done
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

log "Container ready. code-server :${CODE_SERVER_PORT} | AI Toolkit (reserved) :${AI_TOOLKIT_PORT} | ComfyUI manual :${COMFY_PORT}"
tail -f /dev/null
