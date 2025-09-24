# CUDA 12.8 runtime + Ubuntu 24.04 + Python 3.12
FROM nvidia/cuda:12.8.0-cudnn-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    COMFY_PORT=3000 \
    CODE_SERVER_PORT=3100 \
    AI_TOOLKIT_PORT=3400 \
    JUPYTER_PORT=3600 \
    COMFY_DISABLE_XFORMERS=1 \
    XFORMERS_FORCE_DISABLE=1 \
    PYTORCH_CUDA_ALLOC_CONF="max_split_size_mb:128,expandable_segments=True,garbage_collection_threshold=0.9"

RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-venv python3-pip git curl ca-certificates tini \
    && rm -rf /var/lib/apt/lists/*

# Add entrypoint
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Create workspace layout
RUN mkdir -p /workspace/bin /workspace/logs \
    /workspace/models/{checkpoints,clip,vae,loras,ipadapter,controlnet,grounding}

EXPOSE 3000 3100 3400 3600

ENTRYPOINT ["/usr/bin/tini","-s","--","/usr/local/bin/entrypoint.sh"]
CMD []
