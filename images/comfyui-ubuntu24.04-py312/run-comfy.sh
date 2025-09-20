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

# Feature flags (future-proof, optional)
PACK_PRESET="${PACK_PRESET:-core}"   # core|none
WITH_SAM="${WITH_SAM:-0}"            # 0/1 (wheel-only)
WITH_DINO="${WITH_DINO:-0}"          # must stay 0 (no compile path)
PIP_CONSTRAINTS="${PIP_CONSTRAINTS:-}"  # optional: /workspace/constraints.txt

LOG_DIR="/workspace/logs"
mkdir -p "$LOG_DIR"

log(){ printf "[run-comfy] %s\n" "$*"; }

# 1) Ensure venv exists
if [ ! -x "${VENV_PATH}/bin/python" ]; then
  log "Creating venv at ${VENV_PATH}"
  mkdir -p "$(dirname "${VENV_PATH}")"
  python3 -m venv "${VENV_PATH}"
  "${VENV_PATH}/bin/pip" install --upgrade pip wheel setuptools
fi

pip_install() {
  if [ -n "${PIP_CONSTRAINTS}" ] && [ -f "${PIP_CONSTRAINTS}" ]; then
    "${VENV_PATH}/bin/pip" install -r "${PIP_CONSTRAINTS}" "$@"
  else
    "${VENV_PATH}/bin/pip" install "$@"
  fi
}

# 1b) wheel-only runtime deps (idempotent)
if [ ! -f "${VENV_PATH}/.deps.ok" ]; then
  log "Installing runtime wheels (torch/cu128, ORT, OpenCV, rembg)"
  pip_install --upgrade pip wheel setuptools
  # Torch cu128 (no compile)
  pip_install --extra-index-url https://download.pytorch.org/whl/cu128 "torch==2.8.*"
  # ORT GPU + onnx (no compile)
  pip_install "onnx" "onnxruntime-gpu==1.18.1"
  # OpenCV (wheel-only)
  pip_install --only-binary=:all: "opencv-python-headless==4.10.*"
  # rembg without deps (we control ORT)
  pip_install --no-deps rembg

  # Optional: SAM (wheel-only)
  if [ "${WITH_SAM}" = "1" ]; then
    pip_install --only-binary=:all: "segment-anything==*" || true
  fi

  # GroundingDINO/SegmentV2 explicitly OFF (requires compile)
  if [ "${WITH_DINO}" = "1" ]; then
    log "WITH_DINO=1 requested but blocked (no compile path). Skipping."
  fi

  touch "${VENV_PATH}/.deps.ok"
fi

# 2) Start code-server (auto)
if ! pgrep -af "code-server.*--bind-addr 0.0.0.0:${CODE_SERVER_PORT}" >/dev/null 2>&1; then
  log "Starting code-server on :${CODE_SERVER_PORT}"
  nohup code-server --bind-addr 0.0.0.0:${CODE_SERVER_PORT} /workspace \
    >"${LOG_DIR}/code-server.log" 2>&1 &
else
  log "code-server already running"
fi

# 3) AI Toolkit (reserved; disabled by default)
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

# 4) Node manifests (optional, future-proof)
sync_nodes_from_manifest() {
  local MANIFEST="/workspace/node_manifest.${PACK_PRESET}.json"
  [ -f "$MANIFEST" ] || { log "No manifest for PACK_PRESET='${PACK_PRESET}' (skipping)."; return 0; }
  log "Syncing nodes from ${MANIFEST}"
  python3 - "$MANIFEST" <<'PY'
import json, os, subprocess, sys
m=json.load(open(sys.argv[1]))
base="/workspace/ComfyUI/custom_nodes"
os.makedirs(base, exist_ok=True)
for r in m.get("repos", []):
    name, url, commit = r["name"], r["url"], r["commit"]
    dst=os.path.join(base, name)
    if not os.path.isdir(dst):
        subprocess.check_call(["git","clone","--depth","1",url,dst])
    subprocess.check_call(["git","-C",dst,"fetch","--depth","1","origin",commit])
    subprocess.check_call(["git","-C",dst,"checkout",commit])
print("OK")
PY
}

# 5) ComfyUI starter (manual by default)
is_port_in_use() { (exec 3<>/dev/tcp/127.0.0.1/"$1") >/dev/null 2>&1 && { exec 3>&-; return 0; } || return 1; }

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

  # Optional: sync nodes from manifest
  sync_nodes_from_manifest || log "Manifest sync skipped/failed (continuing)."

  log "Starting ComfyUI on :${COMFY_PORT}"
  nohup "${VENV_PATH}/bin/python" "${APP_PATH}/main.py" \
      --listen 0.0.0.0 --port "${COMFY_PORT}" \
      >> "${LOG_DIR}/comfyui.log" 2>&1 &
  log "ComfyUI started; tail: ${LOG_DIR}/comfyui.log"

  # readiness probe + snapshot
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

# Manual-only by default
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
