# Ubuntu 24.04 + CUDA 12.8 runtime + Python 3.12
FROM nvidia/cuda:12.8.0-cudnn-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1 \
    RUNPOD_VENV=/workspace/.venvs/comfyui-perf \
    COMFY_PATH=/workspace/ComfyUI \
    COMFY_HOST=0.0.0.0 \
    COMFY_PORT=3000 \
    CODE_SERVER_PORT=3100 \
    ENABLE_CODE_SERVER=1 \
    START_COMFYUI=0

# Runtime deps + minimal build toolchain for insightface (g++, headers)
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common ca-certificates curl git git-lfs \
    libgl1 libopengl0 libglib2.0-0 libsm6 libxext6 libxrender1 \
    libgtk-3-0 ffmpeg unzip p7zip-full wget \
    build-essential python3-dev \
 && rm -rf /var/lib/apt/lists/*

# Python 3.12 (Ubuntu 24.04 default) — matches your existing venv
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-venv python3-distutils \
 && rm -rf /var/lib/apt/lists/*

# Bake code-server so it’s always available
RUN set -eux; \
  curl -fsSL https://github.com/coder/code-server/releases/download/v4.89.1/code-server-4.89.1-linux-amd64.tar.gz \
  | tar xz -C /opt && \
  ln -sf /opt/code-server-4.89.1-linux-amd64/bin/code-server /usr/local/bin/code-server

# Non-root user + writable workspace
RUN useradd -m -s /bin/bash comfy || true && \
    mkdir -p /workspace && chown -R comfy:comfy /workspace
USER comfy
WORKDIR /workspace

# Write the entrypoint inline (so no external COPY can break the build)
RUN bash -lc 'cat > /usr/local/bin/run-comfy.sh << "EOF"\n\
#!/usr/bin/env bash\n\
set -Eeuo pipefail\n\
: "${START_COMFYUI:=0}"\n\
: "${ENABLE_CODE_SERVER:=1}"\n\
: "${COMFY_PORT:=3000}"\n\
: "${CODE_SERVER_PORT:=3100}"\n\
: "${CODE_SERVER_PASSWORD:=}"\n\
: "${RUNPOD_VENV:=/workspace/.venvs/comfyui-perf}"\n\
: "${COMFY_PATH:=/workspace/ComfyUI}"\n\
LOG_DIR="/workspace/logs"; mkdir -p "$LOG_DIR"\n\
echo "[wrap] boot $(date -Iseconds)" | tee -a "$LOG_DIR/wrap.log"\n\
echo "[wrap] COMFY_PATH=$COMFY_PATH VENV=$RUNPOD_VENV START_COMFYUI=$START_COMFYUI" | tee -a "$LOG_DIR/wrap.log"\n\
if [[ -d "$RUNPOD_VENV" ]]; then source "$RUNPOD_VENV/bin/activate" || true; fi\n\
if [[ "$ENABLE_CODE_SERVER" == "1" ]] && command -v code-server >/dev/null 2>&1; then\n\
  export PASSWORD="${CODE_SERVER_PASSWORD:-comfy-dev}";\n\
  nohup code-server --bind-addr "0.0.0.0:${CODE_SERVER_PORT}" --auth password >>"$LOG_DIR/code-server.log" 2>&1 &\n\
  echo "[wrap] code-server pid=$!" | tee -a "$LOG_DIR/wrap.log"\n\
fi\n\
if [[ "$START_COMFYUI" == "1" ]]; then\n\
  cd "$COMFY_PATH"; exec python3 -u main.py --listen 0.0.0.0 --port "$COMFY_PORT" >>"$LOG_DIR/comfyui.log" 2>&1\n\
else\n\
  echo "[wrap] START_COMFYUI=0 → manual mode" | tee -a "$LOG_DIR/wrap.log"\n\
  exec tail -f /dev/null\n\
fi\n\
EOF\n\
chmod +x /usr/local/bin/run-comfy.sh'

EXPOSE 3000 3001 3100 8675
ENTRYPOINT ["/usr/local/bin/run-comfy.sh"]
