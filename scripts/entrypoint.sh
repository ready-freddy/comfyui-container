#!/usr/bin/env bash
set -euo pipefail

LOGDIR=/workspace/logs
mkdir -p "$LOGDIR" /workspace/scripts /workspace/bin /workspace/.provision

STAMP="/workspace/.provision/complete-${PROVISION_VERSION:-unknown}"
if [[ "${AUTOPROVISION:-1}" == "1" ]] && [[ ! -f "$STAMP" ]]; then
  echo "[entrypoint] provisioning start ${PROVISION_VERSION:-unknown}" | tee -a "$LOGDIR/entrypoint.provision.log"
  /workspace/scripts/provision_all.sh 2>&1 | tee -a "$LOGDIR/entrypoint.provision.log" || true
fi

TS="$(date +%Y%m%dT%H%M%S)"
touch "$LOGDIR/entrypoint.$TS.log"
ln -sf "entrypoint.$TS.log" "$LOGDIR/entrypoint.last.log"

echo "[entrypoint] Ports COMFY:${COMFY_PORT:-3000} CODE:${CODE_SERVER_PORT:-3100} OSTRIS:${OSTRIS_PORT:-3400} JUPY:${JUPYTER_PORT:-3600}" | tee -a "$LOGDIR/entrypoint.last.log"

# Optional auto-starts (defaults off; manual control is safer)
if [[ "${START_CODE_SERVER:-0}" == "1" ]]; then
  nohup /workspace/bin/codesrvctl start > "$LOGDIR/code-server.nohup.log" 2>&1 || true
fi
if [[ "${START_JUPYTER:-0}" == "1" ]]; then
  nohup /workspace/bin/jupyterctl start > "$LOGDIR/jupyter.nohup.log" 2>&1 || true
fi>
if [[ "${START_COMFYUI:-0}" == "1" ]]; then
  nohup /workspace/bin/comfyctl start > "$LOGDIR/comfyui.nohup.log" 2>&1 || true
fi
if [[ "${START_OSTRIS:-0}" == "1" ]]; then
  nohup /workspace/bin/ai-toolkitctl start > "$LOGDIR/ostris.nohup.log" 2>&1 || true
fi

# Keep container alive and stream logs
tail -F "$LOGDIR"/entrypoint.*.log "$LOGDIR"/*.nohup.log "$LOGDIR"/entrypoint.provision.log 2>/dev/null || tail -f /dev/null
