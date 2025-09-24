#!/usr/bin/env bash
set -euo pipefail

COMFY_VENV="/workspace/.venvs/comfyui-perf"
TOOLKIT_VENV="/workspace/.venvs/ai-toolkit"

# 1) ComfyUI venv
python3.12 -m venv "$COMFY_VENV"
"$COMFY_VENV/bin/pip" install --upgrade pip wheel setuptools "numpy<2.1"
"$COMFY_VENV/bin/pip" install --index-url https://download.pytorch.org/whl/cu128 \
  torch==2.8.0 torchvision==0.19.0

# 2) ai-toolkit venv (Ostris, optional now)
python3.12 -m venv "$TOOLKIT_VENV"
"$TOOLKIT_VENV/bin/pip" install --upgrade pip wheel setuptools "numpy<2.1"

# 3) Repos (disposable)
[ -d /workspace/ComfyUI/.git ] || git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI
[ -d /workspace/ai-toolkit/.git ] || git clone https://github.com/ostris/ai-toolkit.git /workspace/ai-toolkit

echo "[bootstrap] Done."
