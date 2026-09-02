#!/usr/bin/env bash
set -euo pipefail

echo "[PROVISION] Checking workspace integrity..."

# 1. Clone ComfyUI core if not present on network volume
if [[ ! -f "/workspace/ComfyUI/main.py" ]]; then
    echo "[PROVISION] Cloning ComfyUI repository..."
    git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI
fi

# 2. Ensure model directories exist
mkdir -p /workspace/ComfyUI/models/{checkpoints,clip,clip_vision,configs,controlnet,diffusers,embeddings,gligen,hypernetworks,loras,style_models,unet,upscale_models,vae,vae_approx,LLM}

# 3. Ensure ComfyUI core requirements are installed
if [[ -f "/workspace/ComfyUI/requirements.txt" ]]; then
    echo "[PROVISION] Ensuring ComfyUI core requirements via uv..."
    /opt/venvs/comfyui-perf/bin/uv pip install --no-cache -r /workspace/ComfyUI/requirements.txt >> /workspace/logs/dependency_sync.log 2>&1 || true
fi

# 4. Synchronize custom requirements cleanly without breaking pre-baked ABI
if [[ -f "/workspace/requirements.custom.txt" ]]; then
    echo "[PROVISION] Syncing custom requirements via uv..."
    /opt/venvs/comfyui-perf/bin/uv pip install --no-cache -r /workspace/requirements.custom.txt >> /workspace/logs/dependency_sync.log 2>&1 || true
    
    # Enforce locks in case any third-party node pulled an unconstrained dependency
    /opt/venvs/comfyui-perf/bin/pip install --no-cache-dir --no-deps "numpy==1.26.4" "pillow>=9.2.0,<12.0" >> /workspace/logs/dependency_sync.log 2>&1 || true
fi

# 5. Ensure bin permissions
if [[ -d "/workspace/bin" ]]; then
    chmod +x /workspace/bin/* 2>/dev/null || true
fi

# 6. Boot Assertion Log
/opt/venvs/comfyui-perf/bin/python -c "
import numpy as np, llama_cpp
assert np.__version__ == '1.26.4', f'CRITICAL: NumPy drifted to {np.__version__}'
assert llama_cpp.llama_supports_gpu_offload(), 'CRITICAL: llama-cpp-python CUDA offload is inactive'
" >> /workspace/logs/boot_verification.log 2>&1 && echo "[PROVISION] CUDA Engine & ABI Verified." || echo "[WARN] Provisioning check reported warnings. See /workspace/logs/boot_verification.log"

echo "[PROVISION] Workspace configuration complete."
