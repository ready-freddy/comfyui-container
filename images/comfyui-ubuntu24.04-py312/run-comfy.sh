#!/usr/bin/env bash
set -euo pipefail

# ---- Config (override via env if needed) ----
VENV_PATH="${VENV_PATH:-/workspace/.venvs/comfyui-perf}"
APP_PATH="${APP_PATH:-/workspace/ComfyUI}"
COMFY_PORT="${COMFY_PORT:-3000}"
CODE_SERVER_PORT="${CODE_SERVER_PORT:-3100}"
AI_TOOLKIT_PORT="${AI_TOOLKIT_PORT:-8675}"
START_COMFYUI="${START_COMFYUI:-0}"
IMAGE_VENV="${IMAGE_VENV:-/opt/venvs/comfyui-perf}"   # baked venv (if image provides)

log(){ printf "[run-comfy] %s\n" "$*"; }
mkdir -p /workspace/logs

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
    >/workspace/logs/code-server.log 2>&1 &
else
  log "code-server already running"
fi

# 3) (Port reserved for AI-Toolkit on :${AI_TOOLKIT_PORT})

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
      >> /workspace/logs/comfyui.log 2>&1 &
  log "ComfyUI started; tail: /workspace/logs/comfyui.log"

  # quick readiness probe + snapshot
  for i in $(seq 1 90); do
    sleep 1
    if curl -fsS "http://127.0.0.1:${COMFY_PORT}/" >/dev/null 2>&1; then
      TS=$(date +%Y%m%dT%H%M%S)
      curl -fsS "http://127.0.0.1:${COMFY_PORT}/object_info?no_cache=1" \
        -o "/workspace/logs/object_info.${TS}.json" || true
      log "ComfyUI ready; snapshot saved: /workspace/logs/object_info.${TS}.json"
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

log "Container ready. code-server :${CODE_SERVER_PORT} | ComfyUI manual :${COMFY_PORT}"
tail -f /dev/null
