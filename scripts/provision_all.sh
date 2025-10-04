#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

VENV=/workspace/.venvs/comfyui-perf
BIN=/workspace/bin
mkdir -p "$BIN" /workspace/logs /workspace/.locks

if [ ! -d /workspace/ComfyUI/.git ]; then
  git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI || true
fi

if [ ! -x "$BIN/comfyctl" ]; then
  cat >"$BIN/comfyctl" <<'S2'
#!/usr/bin/env bash
set -Eeuo pipefail
VENV=/workspace/.venvs/comfyui-perf
. "$VENV/bin/activate"
exec python -u /workspace/ComfyUI/main.py --listen 0.0.0.0 --port ${COMFY_PORT:-3000}
S2
  chmod +x "$BIN/comfyctl"
fi

if [ ! -x "$BIN/aikitctl" ]; then
  cat >"$BIN/aikitctl" <<'S3'
#!/usr/bin/env bash
set -Eeuo pipefail
. /workspace/.venvs/comfyui-perf/bin/activate
PORT="${OSTRIS_PORT:-7860}"
python - <<'PY'
import gradio as gr
def ping(x): return x
gr.Interface(fn=ping, inputs="text", outputs="text").launch(server_name="0.0.0.0", server_port=int("${OSTRIS_PORT:-7860}"))
PY
S3
  chmod +x "$BIN/aikitctl"
fi

if [ ! -x "$BIN/aikituictl" ]; then
  cat >"$BIN/aikituictl" <<'S4'
#!/usr/bin/env bash
set -Eeuo pipefail
cd /workspace/ai-toolkit
PORT="${OSTRISDASH_PORT:-8675}"
npx http-server -p "$PORT" -a 0.0.0.0 .
S4
  chmod +x "$BIN/aikituictl"
fi
