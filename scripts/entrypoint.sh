#!/usr/bin/env bash
set -Eeuo pipefail

LOG_DIR=/workspace/logs
mkdir -p "$LOG_DIR"
echo "[entrypoint] $(date -Iseconds)"

# 0) Emergency: do nothing, keep container alive for forensics
if [[ "${SAFE_START:-0}" == "1" ]]; then
  echo "[entrypoint] SAFE_START=1 → skipping provision + sidecars"
  exec tail -f /dev/null
fi

# 1) Provision phase (soft-fail), unless explicitly skipped
if [[ "${SKIP_PROVISION:-0}" == "1" ]]; then
  echo "[entrypoint] SKIP_PROVISION=1 → not running provision"
else
  if /scripts/provision_all.sh; then
    echo "[entrypoint] provision OK"
  else
    echo "[entrypoint] WARNING: provision failed (soft-fail). See /workspace/logs."
  fi
fi

# 2) Optional sleep-only to keep pod alive for debugging after provision
if [[ "${STARTUP_SLEEP_ONLY:-0}" == "1" ]]; then
  echo "[entrypoint] STARTUP_SLEEP_ONLY=1 → sleeping"
  exec tail -f /dev/null
fi

# 3) Sidecars (ComfyUI stays manual-only by policy)
if [[ "${START_CODE_SERVER:-1}" == "1" ]]; then
  LOG_CS="$LOG_DIR/code-server.$(date +%Y%m%dT%H%M%S).log"
  echo "[entrypoint] launching code-server → :${CODE_SERVER_PORT:-3100} (log: $LOG_CS)"
  nohup code-server --bind-addr 0.0.0.0:${CODE_SERVER_PORT:-3100} --auth none /workspace >>"$LOG_CS" 2>&1 &
fi

if [[ "${START_JUPYTER:-0}" == "1" ]]; then
  LOG_J="$LOG_DIR/jupyter.$(date +%Y%m%dT%H%M%S).log"
  JVENV=/workspace/.venvs/jupyter
  if [[ ! -d "$JVENV" ]]; then
    python3 -m venv "$JVENV"
    "$JVENV/bin/pip" install -U pip wheel setuptools jupyterlab
  fi
  echo "[entrypoint] launching Jupyter → :${JUPYTER_PORT:-3600} (log: $LOG_J)"
  nohup "$JVENV/bin/jupyter" lab \
      --ip=0.0.0.0 --port="${JUPYTER_PORT:-3600}" --no-browser \
      --ServerApp.token="${JUPYTER_TOKEN:-}" \
      --ServerApp.allow_origin='*' >>"$LOG_J" 2>&1 &
fi

# Optional policy exception: allow ComfyUI autostart when explicitly requested
if [[ "${START_COMFYUI:-0}" == "1" ]]; then
  echo "[entrypoint] START_COMFYUI=1 → starting ComfyUI (policy exception)"
  /workspace/bin/comfyctl start || true
fi

# 4) Keep PID 1 alive and stream logs
touch "$LOG_DIR/.sentinel"
exec tail -n +1 -F "$LOG_DIR/"*.log "$LOG_DIR/.sentinel"
