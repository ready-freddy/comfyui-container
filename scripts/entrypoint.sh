#!/usr/bin/env bash
set -euo pipefail

# Ensure logs exist (prevents tail crash)
mkdir -p /workspace/logs /workspace/bin
: > /workspace/logs/code-server.log
: > /workspace/logs/comfyui.log
: > /workspace/logs/entrypoint.log
: > /workspace/logs/jupyter.log

# Start code-server automatically (ComfyUI/Ostris/Jupyter are manual via ctl scripts)
/usr/bin/nohup bash -lc "code-server --auth none --disable-telemetry --bind-addr 0.0.0.0:${CODE_SERVER_PORT:-3100} >>/workspace/logs/code-server.log 2>&1" &

# Keep container alive
tail -F /workspace/logs/code-server.log
