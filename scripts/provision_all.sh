#!/usr/bin/env bash
set -euo pipefail

echo "[PROVISION] Checking workspace integrity..."

# 1. Ensure ComfyUI core exists on the network volume
if [[ ! -f "/workspace/ComfyUI/main.py" ]]; then
    echo "[PROVISION] Cloning ComfyUI repository..."
    git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI
fi

# 2. Ensure model directories exist
mkdir -p /workspace/ComfyUI/models/{checkpoints,clip,clip_vision,configs,controlnet,diffusers,embeddings,gligen,hypernetworks,loras,style_models,unet,upscale_models,vae,vae_approx,LLM}

# 3. Synchronize custom repositories essential to H3, IAMCCS, and SAM3
if [[ -d "/workspace/ComfyUI/custom_nodes" ]]; then
    # Ensure IAMCCS Face Detailer dependency is present
    if [[ ! -d "/workspace/ComfyUI/custom_nodes/ComfyUI-H3-FaceRefine" ]]; then
        echo "[PROVISION] Cloning ComfyUI-H3-FaceRefine for IAMCCS..."
        git clone https://github.com/Carasibana/ComfyUI-H3-FaceRefine.git /workspace/ComfyUI/custom_nodes/ComfyUI-H3-FaceRefine || true
    fi

    # Disable conflicting comfyui_colmap to avoid polluting python sys.path / lib namespace
    if [[ -d "/workspace/ComfyUI/custom_nodes/comfyui_colmap" ]]; then
        echo "[PROVISION] Disabling comfyui_colmap namespace conflict..."
        mv /workspace/ComfyUI/custom_nodes/comfyui_colmap /workspace/ComfyUI/custom_nodes/.comfyui_colmap.disabled 2>/dev/null || true
    fi

    # Strip malformed comfy-env-root.toml from ComfyUI-SAM3 to allow clean standard load
    if [[ -f "/workspace/ComfyUI/custom_nodes/ComfyUI-SAM3/comfy-env-root.toml" ]]; then
        echo "[PROVISION] Removing deprecated comfy-env-root.toml from ComfyUI-SAM3..."
        rm -f "/workspace/ComfyUI/custom_nodes/ComfyUI-SAM3/comfy-env-root.toml" 2>/dev/null || true
    fi
fi

# 4. Synchronize experimental dependencies with strict ABI guardrail
if [[ -s "/workspace/requirements.custom.txt" ]]; then
    echo "[PROVISION] Syncing custom requirements from /workspace/requirements.custom.txt..."
    /opt/venvs/comfyui-perf/bin/uv pip install --no-cache -r /workspace/requirements.custom.txt "numpy==1.26.4" >> /workspace/logs/dependency_sync.log 2>&1 || true
    /opt/venvs/comfyui-perf/bin/pip install --no-cache-dir --force-reinstall --no-deps "numpy==1.26.4" >> /workspace/logs/dependency_sync.log 2>&1 || true
fi

# 5. Ensure bin permissions
if [[ -d "/workspace/bin" ]]; then
    chmod +x /workspace/bin/* 2>/dev/null || true
fi

# 6. Boot Assertion Log & Strict ABI Verification
/opt/venvs/comfyui-perf/bin/python -c "
import numpy as np, llama_cpp, cv2, plyfile, sam3
assert np.__version__ == '1.26.4', f'CRITICAL: NumPy drifted to {np.__version__}'
assert llama_cpp.llama_supports_gpu_offload(), 'CRITICAL: llama-cpp-python CUDA offload is inactive'
print('NumPy 1.26.4, OpenCV, plyfile, and sam3 verified cleanly.')
" >> /workspace/logs/boot_verification.log 2>&1 && echo "[PROVISION] CUDA Engine & ABI Verified." || {
    echo "[CRITICAL WARN] Provisioning check failed! Check /workspace/logs/boot_verification.log"
}

echo "[PROVISION] Workspace configuration complete."
