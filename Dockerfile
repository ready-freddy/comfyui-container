# syntax=docker/dockerfile:1.7
# --- Build stage 1 (the only stage we need) ---
FROM nvidia/cuda:12.8.0-runtime-ubuntu24.04

# Keep bash everywhere
SHELL ["/bin/bash","-lc"]

# Noninteractive apt — build-time only (we're not apt-ing inside the pod)
ENV DEBIAN_FRONTEND=noninteractive

# Tiny runtime deps that are safe and useful (curl, procps for ss)
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl procps \
    && rm -rf /var/lib/apt/lists/*

# Copy scripts (ensure repo has scripts/entrypoint.sh from my earlier message)
COPY scripts/ /scripts/

# Enforce LF endings + validate shell syntax; make scripts executable
RUN find /scripts -type f -name "*.sh" -exec sed -i 's/\r$//' {} \; \
 && bash -n /scripts/entrypoint.sh \
 && chmod +x /scripts/*.sh

# Document ports (RunPod decides exposure)
EXPOSE 3000 3100 3400 3600

# ENTRYPOINT: safe-boot with Jupyter (Comfy off by default)
ENTRYPOINT ["/scripts/entrypoint.sh"]
CMD []
