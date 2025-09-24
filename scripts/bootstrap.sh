#!/usr/bin/env bash
set -euo pipefail

VENV_BASE=/workspace/.venvs
PYVER=3.12
PY=/usr/bin/python${PYVER}
LOG=/workspace/logs/bootstrap.$(date +%Y%m%dT%H%M%S).log

echo "[bootstrap] begin" | tee -a "$LOG"
mkdir -p /workspace/{.venvs,ComfyUI,ai-toolkit,models,notebooks,logs,bin}

# --- helper: create venv if missing ---
mkvenv () {
  local name="$1"
  local path="$VENV_BASE/$name"
  if [[ ! -d "$path" ]]; then
    $PY -m venv "$path"
    "$path/bin/pip" install -U pip wheel setuptools
    echo "[bootstrap] created venv $name" | tee -a "$LOG"
  fi
}

mkvenv comfyui-perf
mkvenv jupyter
mkvenv ai-toolkit

# --- Torch stack for CUDA 12.8 only (single image policy) ---
TORCH_SPEC='torch==2.8.0+cu128 torchvision==0.19.0+cu128 torchaudio==2.8.0+cu128 --index-url https://download.pytorch.org/whl/cu128'
"$VENV_BASE/comfyui-perf/bin/pip" install $TORCH_SPEC onnx onnxruntime-gpu==1.18.1
echo "[bootstrap] torch/onnx stack installed" | tee -a "$LOG"

# --- service wrappers ---

# ComfyUI launcher
cat >/workspace/bin/comfyctl <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
VENV=/workspace/.venvs/comfyui-perf
LOG=/workspace/logs/comfyui.$(date +%Y%m%dT%H%M%S).log
CMD="$VENV/bin/python -X faulthandler -u /workspace/ComfyUI/main.py --listen 0.0.0.0 --port ${COMFY_PORT:-3000}"
case "${1:-start}" in
  start) nohup bash -lc "$CMD" > "$LOG" 2>&1 & echo "ComfyUI starting… log=$LOG";;
  stop)  pkill -f "python.*ComfyUI/main.py" || true; echo "ComfyUI stopped.";;
  log)   tail -n 200 -f "$LOG" ;;
  *)     echo "usage: comfyctl {start|stop|log}"; exit 2;;
esac
EOS
chmod +x /workspace/bin/comfyctl

# JupyterLab launcher
cat >/workspace/bin/jupyterctl <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
VENV=/workspace/.venvs/jupyter
"$VENV/bin/pip" install -q jupyterlab || true
LOG=/workspace/logs/jupyter.$(date +%Y%m%dT%H%M%S).log
case "${1:-start}" in
  start) nohup "$VENV/bin/jupyter" lab --ip 0.0.0.0 --port ${JUPYTER_PORT:-3600} --allow-root --NotebookApp.token= --NotebookApp.password= > "$LOG" 2>&1 & echo "Jupyter starting… log=$LOG";;
  stop)  pkill -f "jupyter.*lab" || true; echo "Jupyter stopped.";;
  log)   tail -n 200 -f "$LOG" ;;
  *)     echo "usage: jupyterctl {start|stop|log}"; exit 2;;
esac
EOS
chmod +x /workspace/bin/jupyterctl

# Ostris placeholder (wire later)
cat >/workspace/bin/ai-toolkitctl <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
VENV=/workspace/.venvs/ai-toolkit
LOG=/workspace/logs/ai-toolkit.$(date +%Y%m%dT%H%M%S).log
case "${1:-start}" in
  start) echo "Ostris not wired yet; pin repo and update me." | tee -a "$LOG";;
  stop)  pkill -f "ai-toolkit" || true; echo "Ostris stopped.";;
  log)   tail -n 200 -f "$LOG" ;;
  *)     echo "usage: ai-toolkitctl {start|stop|log}"; exit 2;;
esac
EOS
chmod +x /workspace/bin/ai-toolkitctl

echo "[bootstrap] done" | tee -a "$LOG"
