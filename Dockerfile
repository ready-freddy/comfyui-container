# Dockerfile — Stable (main)
# Ubuntu 24.04 + CUDA 12.8 runtime; no baked venvs/models; manual ComfyUI.
FROM nvidia/cuda:12.8.0-cudnn-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 LC_ALL=C.UTF-8 TZ=UTC

# Minimal system deps (build-time only; NEVER apt inside a running pod)
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3.12 python3.12-venv python3-pip git curl ca-certificates tini \
  && rm -rf /var/lib/apt/lists/*

# Workspace contract
RUN mkdir -p /workspace/bin /workspace/logs /workspace/notebooks \
    /workspace/models/{checkpoints,clip,vae,loras,ipadapter,controlnet,grounding} \
    /workspace/.venvs /workspace/ComfyUI /workspace/ai-toolkit

# code-server (auto)
ARG CODE_SERVER_VERSION=4.92.2
RUN curl -fsSL https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz \
    | tar -xz -C /opt \
 && ln -s /opt/code-server-${CODE_SERVER_VERSION}-linux-amd64/bin/code-server /usr/local/bin/code-server

# Stable defaults & guardrails
ENV COMFY_PORT=3000 \
    CODE_SERVER_PORT=3100 \
    AI_TOOLKIT_PORT=3400 \
    COMFY_DISABLE_XFORMERS=1 \
    XFORMERS_FORCE_DISABLE=1 \
    PYTORCH_CUDA_ALLOC_CONF="max_split_size_mb=128,expandable_segments=True,garbage_collection_threshold=0.9"

# Optional healthcheck: passes only when ComfyUI is running
HEALTHCHECK --interval=30s --timeout=3s --start-period=30s \
  CMD curl -fsS http://127.0.0.1:${COMFY_PORT}/ || exit 0

# Entrypoint: code-server auto; apps launched via helpers
COPY --chown=root:root <<'BASH' /usr/local/bin/entrypoint.sh
#!/usr/bin/env bash
set -euo pipefail
mkdir -p /root/.local/share/code-server
nohup code-server /workspace \
  --bind-addr 0.0.0.0:${CODE_SERVER_PORT} \
  --auth none >/workspace/logs/code-server.log 2>&1 &
echo "[entrypoint] code-server :${CODE_SERVER_PORT}"
# Keep container running; use /workspace/bin/* to start apps
exec tail -f /workspace/logs/code-server.log
BASH
RUN chmod +x /usr/local/bin/entrypoint.sh

# Helper launchers (installed at build so you have them from day one)
COPY --chown=root:root <<'BASH' /workspace/bin/comfyctl
#!/usr/bin/env bash
set -euo pipefail
VENV="/workspace/.venvs/comfyui-perf"
PY="$VENV/bin/python"
LOGDIR="/workspace/logs"
PORT="${COMFY_PORT:-3000}"
case "${1:-}" in
  start)
    pkill -f "python.*ComfyUI/main.py" || true
    TS=$(date +%Y%m%dT%H%M%S); LOG="$LOGDIR/comfyui.$TS.run.log"
    echo "[comfyctl] starting ComfyUI on :$PORT → $LOG"
    nohup "$PY" -X faulthandler -u /workspace/ComfyUI/main.py \
      --listen 0.0.0.0 --port "$PORT" >"$LOG" 2>&1 &
    ;;
  stop) pkill -f "python.*ComfyUI/main.py" || true; echo "[comfyctl] stopped" ;;
  status)
    if curl -fsS "http://127.0.0.1:$PORT/" >/dev/null 2>&1; then
      echo "ComfyUI READY on :$PORT"
    else
      echo "ComfyUI not running"
    fi
    ;;
  *) echo "Usage: comfyctl {start|stop|status}"; exit 1;;
esac
BASH

COPY --chown=root:root <<'BASH' /workspace/bin/ai-toolkitctl
#!/usr/bin/env bash
set -euo pipefail
VENV="/workspace/.venvs/ai-toolkit"
PY="$VENV/bin/python"
LOGDIR="/workspace/logs"
PORT="${AI_TOOLKIT_PORT:-3400}"
APP="/workspace/ai-toolkit/app.py"
case "${1:-}" in
  start)
    pkill -f "python.*ai-toolkit" || true
    TS=$(date +%Y%m%dT%H%M%S); LOG="$LOGDIR/ai-toolkit.$TS.run.log"
    echo "[ai-toolkitctl] starting Ostris on :$PORT → $LOG"
    nohup "$PY" -X faulthandler -u "$APP" --port "$PORT" \
      >"$LOG" 2>&1 &
    ;;
  stop) pkill -f "python.*ai-toolkit" || true; echo "[ai-toolkitctl] stopped" ;;
  status)
    if curl -fsS "http://127.0.0.1:$PORT/" >/dev/null 2>&1; then
      echo "ai-toolkit READY on :$PORT"
    else
      echo "ai-toolkit not running"
    fi
    ;;
  *) echo "Usage: ai-toolkitctl {start|stop|status}"; exit 1;;
esac
BASH

RUN chmod +x /workspace/bin/comfyctl /workspace/bin/ai-toolkitctl

EXPOSE 3000 3100 3400
ENTRYPOINT ["/usr/bin/tini","--","/usr/local/bin/entrypoint.sh"]
