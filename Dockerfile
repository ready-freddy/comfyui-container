# syntax=docker/dockerfile:1.7
FROM nvidia/cuda:12.8.0-runtime-ubuntu24.04

SHELL ["/bin/bash","-lc"]
ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1 \
    WORKSPACE=/workspace \
    PROVISION_VERSION=2025-09-26-v4

# ---- System deps baked into the image ----
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      python3.12 python3.12-venv python3.12-dev python3-pip \
      ca-certificates curl unzip git iproute2 procps \
      libgl1 libglib2.0-0 libsm6 libxext6 libxrender1; \
    rm -rf /var/lib/apt/lists/*; \
    update-ca-certificates; \
    ln -sf /usr/bin/python3.12 /usr/local/bin/python && \
    ln -sf /usr/bin/pip3 /usr/local/bin/pip

# ---- Workspace skeleton ----
RUN set -eux; mkdir -p $WORKSPACE/{bin,models,notebooks,logs,ComfyUI,ai-toolkit,.provision,.venvs}
WORKDIR $WORKSPACE

# ---- Bring in scripts exactly as in repo ----
COPY scripts/ /scripts/

RUN set -eux; \
    find /scripts -type f -name '*.sh' -exec sed -i 's/\r$//' {} \; && \
    bash -n /scripts/entrypoint.sh /scripts/provision_all.sh && \
    chmod +x /scripts/*.sh

EXPOSE 3000 3100 3400 3600

ENTRYPOINT ["/scripts/entrypoint.sh"]
CMD []
