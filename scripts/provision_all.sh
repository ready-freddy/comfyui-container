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

# 3. Synchronize experimental dependencies with strict ABI guardrail
if [[ -s "/workspace/requirements.custom.txt" ]]; then
    echo "[PROVISION] Syncing custom requirements from /workspace/requirements.custom.txt..."
    # Always include the numpy constraint directly in the resolution solver
    /opt/venvs/comfyui-perf/bin/uv pip install --no-cache -r /workspace/requirements.custom.txt "numpy==1.26.4" >> /workspace/logs/dependency_sync.log 2>&1 || true
    # Force lock numpy to 1.26.4 without dependencies
    /opt/venvs/comfyui-perf/bin/pip install --no-cache-dir --force-reinstall --no-deps "numpy==1.26.4" >> /workspace/logs/dependency_sync.log 2>&1 || true
fi

# 4. Ensure bin permissions
if [[ -d "/workspace/bin" ]]; then
    chmod +x /workspace/bin/* 2>/dev/null || true
fi

# 5. Boot Assertion Log & Strict ABI Verification
/opt/venvs/comfyui-perf/bin/python -c "
import numpy as np, llama_cpp, cv2, plyfile
assert np.__version__ == '1.26.4', f'CRITICAL: NumPy drifted to {np.__version__}'
assert llama_cpp.llama_supports_gpu_offload(), 'CRITICAL: llama-cpp-python CUDA offload is inactive'
print('NumPy 1.26.4, OpenCV, and plyfile verified cleanly.')
" >> /workspace/logs/boot_verification.log 2>&1 && echo "[PROVISION] CUDA Engine & ABI Verified." || {
    echo "[CRITICAL WARN] Provisioning check failed! Check /workspace/logs/boot_verification.log"
}

echo "[PROVISION] Workspace configuration complete."
