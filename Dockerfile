# syntax=docker/dockerfile:1.7
FROM nvidia/cuda:12.8.0-runtime-ubuntu24.04

SHELL ["/bin/bash","-lc"]
ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1 \
    WORKSPACE=/workspace

# ---- Base system (baked; no apt in running pods) ----
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      python3.12 python3.12-venv python3.12-dev python3-pip \
      git curl unzip iproute2 procps ca-certificates \
      libgl1 libglib2.0-0 libsm6 libxext6 libxrender1; \
    rm -rf /var/lib/apt/lists/*; \
    update-ca-certificates; \
    ln -sf /usr/bin/python3.12 /usr/local/bin/python && \
    ln -sf /usr/bin/pip3 /usr/local/bin/pip

# ---- Workspace skeleton ----
RUN mkdir -p $WORKSPACE/{bin,models,logs,notebooks,ComfyUI,ai-toolkit,.venvs}
WORKDIR $WORKSPACE

# ---- Scripts ----
COPY scripts/ /scripts/
RUN set -eux; \
    find /scripts -type f -name '*.sh' -exec sed -i 's/\r$//' {} \; && \
    chmod +x /scripts/*.sh

# Ports: Comfy 3000 (manual), code-server 3100, Ostris 3400, Jupyter 3600
EXPOSE 3000 3100 3400 3600

ENTRYPOINT ["/scripts/entrypoint.sh"]
CMD []
