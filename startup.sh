#!/usr/bin/env bash
set -euo pipefail

echo "== ReadyFreddyGo bootstrap starting =="

VENV="${VENV_PATH:-/workspace/.venvs/comfyui-perf}"
PYBIN="/usr/bin/python3.12"
PIPBIN="$VENV/bin/pip"
PYVBIN="$VENV/bin/python"

mkdir -p "$(dirname "$VENV")" /workspace/custom_logs ${PIP_CACHE_DIR:-/workspace/.cache/pip}

# Create venv if missing
if [ ! -x "$PYVBIN" ]; then
  echo "[bootstrap] Creating venv at $VENV"
  "$PYBIN" -m venv "$VENV"
  "$PIPBIN" install -U pip wheel setuptools packaging
fi

# --- Torch >= 2.8.0 + xformers, idempotent and CUDA-aware ---
TORCH_STATUS=$($PYVBIN - <<'PY'
from packaging.version import Version
try:
    import torch
    v = Version(torch.__version__.split('+')[0])
    ok = v >= Version("2.8.0")
    cuda = torch.cuda.is_available()
    print(("OK" if ok else "NO") + ("_CUDA" if cuda else "_NO_CUDA"))
except Exception:
    print("NO_NO_CUDA")
PY
)

if [[ "$TORCH_STATUS" == OK_CUDA ]]; then
  echo "[bootstrap] Torch >=2.8.0 with CUDA already present."
elif [[ "$TORCH_STATUS" == OK_NO_CUDA ]]; then
  echo "[bootstrap] Torch >=2.8.0 present but NO CUDA -> repairing with cu128 wheels."
  $PIPBIN install --upgrade --force-reinstall \
    --extra-index-url https://download.pytorch.org/whl/cu128 \
    torch==2.8.0 torchvision==0.19.0 torchaudio==2.8.0
else
  echo "[bootstrap] Installing Torch 2.8.0 (CUDA 12.8 wheels if available)"
  set +e
  $PIPBIN install --extra-index-url https://download.pytorch.org/whl/cu128 \
    torch==2.8.0 torchvision==0.19.0 torchaudio==2.8.0
  PT_RC=$?
  set -e
  if [ "$PT_RC" -ne 0 ]; then
    echo "[bootstrap] Fallback: default index (may be CPU wheels) — will repair if needed."
    $PIPBIN install torch==2.8.0 torchvision==0.19.0 torchaudio==2.8.0 || true
  fi
fi

echo "[bootstrap] Ensuring xformers==0.0.32.post2"
set +e
$PIPBIN install xformers==0.0.32.post2
XF_RC=$?
set -e
if [ "$XF_RC" -ne 0 ]; then
  echo "[bootstrap] xformers wheel not found; compiling from source (this can take a while)"
  $PIPBIN install --no-build-isolation xformers==0.0.32.post2 || true
fi

# Core Python deps (and node deps you called out)
echo "[bootstrap] Installing Python deps"
$PIPBIN install -U \
  pytorch-lightning piexif scikit-image ultralytics webcolors qwen-vl-utils \
  opencv-contrib-python==4.12.0.88 wget imageio-ffmpeg GitPython \
  blend_modes open-clip-torch dill \
  onnx==1.16.2 onnxruntime-gpu==1.18.1

# Clone ComfyUI into /workspace if missing (workspace is your mounted storage)
if [ ! -d /workspace/ComfyUI ]; then
  echo "[bootstrap] Cloning ComfyUI"
  git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI
fi

# ControlNet Aux import path fix for DWpose
PTH="$VENV/lib/python3.12/site-packages/custom_controlnet_aux_src.pth"
echo "/workspace/ComfyUI/custom_nodes/comfyui_controlnet_aux/src" > "$PTH"
echo "[bootstrap] Wrote $PTH for ControlNet Aux import path"

# Torch sanity to logs
$PYVBIN - <<'PY'
import torch
print("=== Torch sanity ===")
print("Torch:", torch.__version__)
print("CUDA available:", torch.cuda.is_available())
print("CUDA device count:", torch.cuda.device_count())
print("====================")
PY

touch /workspace/bootstrap.log /workspace/comfyui.log /workspace/code-server.log
echo "== ReadyFreddyGo bootstrap done =="
