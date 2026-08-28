#!/usr/bin/env bash
set -euo pipefail

# --- env -------------------------------------------------------------
WORKSPACE="${WORKSPACE:-/workspace}"
VENV_DIR="${WORKSPACE}/.venvs/comfyui-perf"

COMFY_PORT="${COMFY_PORT:-3000}"
CODE_SERVER_PORT="${CODE_SERVER_PORT:-3100}"
JUPYTER_PORT="${JUPYTER_PORT:-3600}"

START_CODE_SERVER="${START_CODE_SERVER:-1}"
START_JUPYTER="${START_JUPYTER:-0}"
# Manual-only policy: ComfyUI auto-start is disabled regardless of this flag.
START_COMFYUI="${START_COMFYUI:-0}"

STARTUP_SLEEP_ONLY="${STARTUP_SLEEP_ONLY:-0}"
SKIP_PROVISION="${SKIP_PROVISION:-0}"
SAFE_START="${SAFE_START:-0}"

# Ensure workspace layout exists early
mkdir -p "${WORKSPACE}/"{bin,logs,.locks,.venvs,models,ComfyUI}

# Prefer the project venv tools in all child processes and forward CUDA compat libs
export VIRTUAL_ENV="${VENV_DIR}"
export PATH="${WORKSPACE}/bin:${VENV_DIR}/bin:${PATH}"
export PIP_REQUIRE_VIRTUALENV=1
export LD_LIBRARY_PATH="/usr/local/cuda-12.8/compat:/usr/local/cuda/compat:/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"

# --- helpers ---------------------------------------------------------
log(){ printf '%s %s\n' "[$(date +'%Y-%m-%dT%H:%M:%S')]" "$*"; }
start_bg(){ ("$@" & echo $! >"${WORKSPACE}/.locks/.$(basename "$1").pid" ) || true; }

# --- provision (idempotent) -----------------------------------------
if [ "${SKIP_PROVISION}" != "1" ]; then
  log "provision: running /scripts/provision_all.sh"
  /scripts/provision_all.sh || log "provision: continued after non-fatal issue"
else
  log "provision: skipped by SKIP_PROVISION=1"
fi

# --- services --------------------------------------------------------
pids=()

# Code-Server (auto)
if [ "${START_CODE_SERVER}" = "1" ]; then
  LOG="${WORKSPACE}/logs/code-server.$(date +%Y%m%dT%H%M%S).log"
  log "start: code-server :${CODE_SERVER_PORT} (log: ${LOG})"
  start_bg /usr/local/bin/code-server --bind-addr 0.0.0.0:"${CODE_SERVER_PORT}" --auth none >>"${LOG}" 2>&1
  pids+=("code-server")
fi

# JupyterLab (optional)
if [ "${START_JUPYTER}" = "1" ]; then
  LOG="${WORKSPACE}/logs/jupyter.$(date +%Y%m%dT%H%M%S).log"
  log "start: jupyterlab :${JUPYTER_PORT} (log: ${LOG})"
  # ensure package is present in venv, then start
  "${VENV_DIR}/bin/python" -m pip show jupyterlab >/dev/null 2>&1 || \
    "${VENV_DIR}/bin/pip" install --prefer-binary jupyterlab >>"${LOG}" 2>&1
  start_bg "${VENV_DIR}/bin/python" -m jupyterlab \
      --ServerApp.token='' --ServerApp.password='' \
      --ServerApp.ip=0.0.0.0 --ServerApp.port="${JUPYTER_PORT}" >>"${LOG}" 2>&1
  pids+=("jupyterlab")
fi

# ComfyUI (manual-only policy)
log "ComfyUI auto-start disabled by policy; manual start via: /workspace/bin/comfyctl start"
log "target port for ComfyUI: :${COMFY_PORT}"

# If nothing is running, idle the container
if [ "${STARTUP_SLEEP_ONLY}" = "1" ] || [ "${#pids[@]}" = "0" ]; then
  log "idle: no long-running services requested; sleeping"
  exec sleep infinity
fi

# --- keep container alive while at least one service lives -----------
while :; do
  alive=false
  for name in "${pids[@]}"; do
    pidfile="${WORKSPACE}/.locks/.${name}.pid"
    if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
      alive=true
      break
    fi
  done
  $alive || { log "all services exited"; exit 0; }
  sleep 3
done
