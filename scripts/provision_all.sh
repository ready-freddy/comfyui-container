#!/usr/bin/env bash
set -euo pipefail

export PERSIST_VENV=${PERSIST_VENV:-/workspace/.venvs/comfyui-perf}

"$PERSIST_VENV/bin/python" - <<'PY' || true
import sys
def safe_import(name):
    try:
        m = __import__(name)
        ver = getattr(m, "__version__", "unknown")
        print(f"Sanity → {name}: {ver}")
    except Exception as e:
        print(f"Sanity → {name}: not importable ({e})")

safe_import("torch")
try:
    import torch
    print("CUDA:", getattr(torch.version, "cuda", None), "avail:", torch.cuda.is_available())
except Exception as e:
    print("Torch CUDA check failed:", e)

safe_import("torchvision")
safe_import("torchaudio")
safe_import("triton")
safe_import("onnxruntime")
safe_import("cv2")
PY
