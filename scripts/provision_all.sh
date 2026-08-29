#!/usr/bin/env bash
set -euo pipefail

echo "[PROVISION] Checking workspace integrity..."

# 1. Clone ComfyUI core if not present on network volume
if [[ ! -f "/workspace/ComfyUI/main.py" ]]; then
    echo "[PROVISION] Cloning ComfyUI repository..."
    git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI
fi

# 2. Ensure model directories exist
mkdir -p /workspace/ComfyUI/models/{checkpoints,clip,clip_vision,configs,controlnet,diffusers,embeddings,gligen,hypernetworks,loras,style_models,unet,upscale_models,vae,vae_approx}

# 3. Ensure bin permissions
if [[ -d "/workspace/bin" ]]; then
    chmod +x /workspace/bin/* 2>/dev/null || true
fi

echo "[PROVISION] Workspace configuration complete."
