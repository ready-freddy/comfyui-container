#!/usr/bin/env bash
set -euo pipefail

export PERSIST_VENV=${PERSIST_VENV:-/workspace/.venvs/comfyui-perf}

# Basic sanity: print versions (to logs)
"$PERSIST_VENV/bin/python" - <<'PY' || true
import torch, onnxruntime as ort, cv2
print("Sanity → Torch:", torch.__version__, "CUDA:", torch.version.cuda, "avail:", torch.cuda.is_available())
print("Sanity → ORT:", ort.__version__)
print("Sanity → OpenCV:", cv2.__version__)
PY
