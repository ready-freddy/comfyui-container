#!/usr/bin/env bash
set -euo pipefail

LOGDIR=/workspace/logs
mkdir -p "$LOGDIR" /workspace/scripts /workspace/bin

TS="$(date +%Y%m%dT%H%M%S)"
touch "$LOGDIR/entrypoint.$TS.log"
ln -sf "entrypoint.$TS.log" "$LOGDIR/entrypoint.last.log"

echo "[entrypoint] CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-<unset>}" | tee -a "$LOGDIR/entrypoint.last.log"
echo "[entrypoint] Ports COMFY:$COMFY_PORT CODE:$CODE_SERVER_PORT OSTRIS:$OSTRIS_PORT JUPY:$JUPYTER_PORT" | tee -a "$LOGDIR/entrypoint.last.log"

# Start code-server automatically only if present (not baked here)
if [[ "${START_CODE_SERVER:-0}" == "1" ]]; then
  if command -v code-server >/dev/null 2>&1; then
    nohup bash -lc 'code-server --bind-addr 0.0.0.0:$CODE_SERVER_PORT --auth none /workspace' \
      > "$LOGDIR/code-se
