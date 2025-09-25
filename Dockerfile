# Copy scripts into the image
COPY scripts/ /scripts/

# Enforce LF endings and validate bash syntax at build time (fail fast)
RUN find /scripts -type f -name "*.sh" -exec sed -i 's/\r$//' {} \; \
 && bash -n /scripts/entrypoint.sh \
 && chmod +x /scripts/*.sh

# Ports (documentational; RunPod controls exposure)
EXPOSE 3000 3100 3400 3600

# Hardened entrypoint (safe-boot with Jupyter; Comfy off by default)
ENTRYPOINT ["/scripts/entrypoint.sh"]
CMD []
