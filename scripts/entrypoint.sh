#!/usr/bin/env bash
set -euo pipefail

export WORKSPACE=${WORKSPACE:-/workspace}
export VENV_DIR=${VENV_DIR:-/opt/venvs/comfyui-perf}
export PERSIST_VENV=${PERSIST_VENV:-/workspace/.venvs/comfyui-perf}
export CODE_SERVER_PORT=${CODE_SERVER_PORT:-3100}

mkdir -p "$WORKSPACE/.venvs" "$WORKSPACE/logs" "$WORKSPACE/.locks" "$WORKSPACE/bin"

# Seed persistent venv (idempotent)
if [ ! -x "$PERSIST_VENV/bin/python" ]; then
  echo "[seed] creating persistent venv at $PERSIST_VENV"
  cp -a "$VENV_DIR" "$PERSIST_VENV"
fi

# ComfyUI repo (repos are disposable)
if [ ! -d "$WORKSPACE/ComfyUI/.git" ]; then
  echo "[provision] cloning ComfyUI"
  git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git "$WORKSPACE/ComfyUI"
fi

# Minimal provision sanity
bash /opt/provision_all.sh || true

# Start code-server only (manual ComfyUI)
LOG="$WORKSPACE/logs/code-server.$(date +%Y%m%dT%H%M%S).log"
/usr/local/bin/code-server --bind-addr 0.0.0.0:${CODE_SERVER_PORT} --auth none >>"$LOG" 2>&1 &
wait -n
