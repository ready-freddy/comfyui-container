#!/usr/bin/env bash
set -euo pipefail
/workspace/bin/comfyctl start
sleep 5
/workspace/bin/comfyctl status
curl -fsS http://127.0.0.1:3000/object_info > /workspace/logs/comfyui.object_info.json
echo "[ready] ComfyUI responded; node registry snapshot saved."
