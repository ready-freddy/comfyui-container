#!/usr/bin/env bash
set -Eeuo pipefail

LOG_DIR=/workspace/logs
mkdir -p "$LOG_DIR"

echo "[entrypoint] starting; $(date -Iseconds)"

# 1) Always run provision, but DO NOT kill the container if it fails
if /scripts/provision_all.sh; then
  echo "[entrypoint] provision succeeded"
else
  echo "[entrypoint] WARNING: provision failed (soft-fail). Check logs under /workspace/logs."
fi

# 2) Optional "sleep only" to keep the pod alive for debugging
if [[ "${STARTUP_SLEEP_ONLY:-0}" == "1" ]]; then
  echo "[entrypoint] STARTUP_SLEEP_ONLY=1 → sleeping forever for inspection"
  tail -f /dev/null
fi

# 3) Start code-server (baked binary) — no auth by default; binds workspace
if [[ "${START_CODE_SERVER:-1}" == "1" ]]; then
  LOG_CS="$LOG_DIR/code-server.$(date +%Y%m%dT%H%M%S).log"
  echo "[entrypoint] launching code-server → :${CODE_SERVER_PORT} (log: $LOG_CS)"
  nohup code-server --bind-addr 0.0.0.0:${CODE_SERVER_PORT} --auth none /workspace >>"$LOG_CS" 2>&1 &
fi

# 4) Start Jupyter in its own venv (idempotent)
if [[ "${START_JUPYTER:-1}" == "1" ]]; then
  LOG_J="$LOG_DIR/jupyter.$(date +%Y%m%dT%H%M%S).log"
  JVENV=/workspace/.venvs/jupyter
  [[ -d "$JVENV" ]] || (python3 -m venv "$JVENV" && "$JVENV/bin/pip" install -U pip wheel setuptools jupyterlab)
  echo "[entrypoint] launching Jupyter → :${JUPYTER_PORT} (log: $LOG_J)"
  nohup "$JVENV/bin/jupyter" lab \
      --ip=0.0.0.0 --port="${JUPYTER_PORT}" --no-browser --ServerApp.token="${JUPYTER_TOKEN:-}" \
      --ServerApp.allow_origin='*' >>"$LOG_J" 2>&1 &
fi

# 5) ComfyUI is manual-only by policy; allow opt-in
if [[ "${START_COMFYUI:-0}" == "1" ]]; then
  echo "[entrypoint] START_COMFYUI=1 → starting ComfyUI (policy exception)"
  /workspace/bin/comfyctl start || true
fi

# 6) Keep PID 1 alive and mirror latest logs to STDOUT
echo "[entrypoint] services started; tailing logs"
touch "$LOG_DIR/.sentinel"
exec tail -n +1 -F "$LOG_DIR/"*.log "$LOG_DIR/.sentinel"
