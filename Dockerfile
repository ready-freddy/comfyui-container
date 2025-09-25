# syntax=docker/dockerfile:1.7
FROM nvidia/cuda:12.8.0-runtime-ubuntu24.04

SHELL ["/bin/bash","-lc"]
ENV DEBIAN_FRONTEND=noninteractive

# Small runtime tools only
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl procps \
    && rm -rf /var/lib/apt/lists/*

# Your hardened entrypoint (assumes scripts/entrypoint.sh exists in repo)
COPY scripts/ /scripts/
RUN find /scripts -type f -name "*.sh" -exec sed -i 's/\r$//' {} \; \
 && bash -n /scripts/entrypoint.sh \
 && chmod +x /scripts/*.sh

EXPOSE 3000 3100 3400 3600
ENTRYPOINT ["/scripts/entrypoint.sh"]
CMD []
