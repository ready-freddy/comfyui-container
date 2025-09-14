#!/usr/bin/env bash
set -euo pipefail

VENV_DIR="${RUNPOD_VENV:-/workspace/.venvs/comfyui-perf}"
COMFY_PATH="${COMFY_PATH:-/workspace/ComfyUI}"
COMFY_HOST="${COMFY_HOST:-0.0.0.0}"
COMFY_PORT="${COMFY_PORT:-3000}"
EXTRA_ARGS="${EXTRA_ARGS:-}"

if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
  echo "[FATAL] Missing venv at ${VENV_DIR} (expected ${VENV_DIR}/bin/python)."
  exit 1
fi
if [[ ! -f "${COMFY_PATH}/main.py" ]]; then
  echo "[FATAL] Missing ComfyUI at ${COMFY_PATH}/main.py."
  exit 1
fi

export PATH="${VENV_DIR}/bin:${PATH}"
cd "${COMFY_PATH}"

echo "[INFO] Using python: $(command -v python)"
python --version || true

echo "[ComfyUI] starting on ${COMFY_HOST}:${COMFY_PORT}"
exec python main.py --listen "${COMFY_HOST}" --port "${COMFY_PORT}" ${EXTRA_ARGS}
