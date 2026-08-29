#!/usr/bin/env bash
set -euo pipefail

echo "=== [BOOT] INITIALIZING CONTAINER ENVIRONMENT ==="

# 1. Ensure directory skeleton on network mount
mkdir -p /workspace/{bin,models,logs,notebooks,ComfyUI,ai-toolkit} /workspace/.venvs /workspace/.locks

# 2. Redirect legacy network venv paths cleanly to /opt NVMe
ln -sfn /opt/venvs/comfyui-perf /workspace/.venvs/comfyui-perf

# 3. Clear stale lock/PID files from previous boots
rm -f /workspace/.locks/.*.pid /workspace/comfy_env.sh 2>/dev/null || true

# 4. Run workspace provisioning if enabled
if [[ "${SKIP_PROVISION:-0}" != "1" ]] && [[ -f "/scripts/provision_all.sh" ]]; then
    /scripts/provision_all.sh || echo "[WARN] Provision script exited with errors."
fi

# 5. Start Code-Server if enabled
if [[ "${START_CODE_SERVER:-1}" == "1" ]]; then
    echo "[BOOT] Starting Code-Server on port ${CODE_SERVER_PORT:-3100}..."
    code-server --bind-addr 0.0.0.0:${CODE_SERVER_PORT:-3100} --auth none /workspace > /workspace/logs/code-server.log 2>&1 &
fi

# 6. Start ComfyUI if configured to auto-start
if [[ "${START_COMFYUI:-0}" == "1" ]] && [[ -f "/workspace/bin/comfy-singleton" ]]; then
    echo "[BOOT] Starting ComfyUI via comfy-singleton..."
    /workspace/bin/comfy-singleton start || true
fi

echo "=== [BOOT] SYSTEM READY ==="

# 7. Keep container alive
exec tail -f /dev/null
