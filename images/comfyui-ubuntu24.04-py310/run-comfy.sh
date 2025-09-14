#!/usr/bin/env bash
set -euo pipefail

export PYTHONUNBUFFERED=1
export COMFYUI_PATH=/workspace/ComfyUI
export VENV_DIR=/opt/venvs/comfyui-perf
export TBG_API_KEY="${TBG_API_KEY:-}"   # optional for ETUR PRO
: "${XFORMERS_FORCE_DISABLE_FLASH_ATTN:=1}"
export XFORMERS_FORCE_DISABLE_FLASH_ATTN

cd "$COMFYUI_PATH"

# Quick canary info
python --version
python -c "import sys,platform; print('glibc:', platform.libc_ver())"
ldd --version | head -n1 || true

# Free requested port if reused
fuser -k ${PORT:-3000}/tcp 2>/dev/null || true

# Launch (PORT can be 3000 or 3001)
exec python main.py --listen 0.0.0.0 --port "${PORT:-3000}"
