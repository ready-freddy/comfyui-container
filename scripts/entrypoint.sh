#!/usr/bin/env bash
set -euo pipefail

COMFY_PORT="${COMFY_PORT:-3000}"
CODE_SERVER_PORT="${CODE_SERVER_PORT:-3100}"
JUPYTER_PORT="${JUPYTER_PORT:-3600}"
OSTRIS_PORT="${OSTRIS_PORT:-3400}"

echo "[entrypoint] Ports COMFY:${COMFY_PORT} CODE:${CODE_SERVER_PORT} OSTRIS:${OSTRIS_PORT} JUPY:${JUPYTER_PORT}"

if [[ "${STARTUP_SLEEP_ONLY:-0}" == "1" ]]; then
  echo "[entrypoint] STARTUP_SLEEP_ONLY=1 → sleeping forever (debug)"
  exec bash -lc "sleep infinity"
fi

log() { printf '%s\n' "[entrypoint] $*"; }
maybe_start() {
  local flag="$1" name="$2" cmd="$3"
  if [[ "${flag}" == "1" ]]; then
    log "start ${name}"
    eval ${cmd} || { echo "[entrypoint] ${name} failed" >&2; exit 1; }
  else
    log "skip ${name}"
  fi
}

STAMP="/workspace/.provision/complete-${PROVISION_VERSION:-unknown}"
if [[ ! -f "$STAMP" ]]; then
  log "provisioning… version=${PROVISION_VERSION:-unset}"
  /scripts/provision_all.sh || { echo "[entrypoint] provision failed" >&2; exit 1; }
else
  log "provision already complete (${STAMP})"
fi

START_CODE_SERVER="${START_CODE_SERVER:-1}"
START_JUPYTER="${START_JUPYTER:-1}"
START_COMFYUI="${START_COMFYUI:-0}"
START_OSTRIS="${START_OSTRIS:-0}"

maybe_start "${START_CODE_SERVER}" "code-server" "/workspace/bin/codesrvctl start"
maybe_start "${START_JUPYTER}"    "jupyter"     "/workspace/bin/jupyterctl start"
maybe_start "${START_COMFYUI}"    "comfyui"     "/workspace/bin/comfyctl start"
# maybe_start "${START_OSTRIS}"     "ostris"      "/workspace/bin/ai-toolkitctl start"

probe() {
  local port="$1"
  if command -v ss >/dev/null 2>&1 && ss -lnt | grep -q ":${port} "; then
    curl -sI "http://127.0.0.1:${port}/" | head -n1 || true
  fi
}
probe "${CODE_SERVER_PORT}"
probe "${JUPYTER_PORT}"
probe "${COMFY_PORT}"
probe "${OSTRIS_PORT}"

if [[ $# -gt 0 ]]; then
  log "exec CMD: $*"
  exec "$@"
else
  log "tailing forever"
  exec bash -lc "tail -f /dev/null"
fi
