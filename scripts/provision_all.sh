#!/usr/bin/env bash
set -euo pipefail

PROVISION_VERSION="${PROVISION_VERSION:-2025-09-26-v4}"
STAMP="/workspace/.provision/complete-${PROVISION_VERSION}"
LOG="/workspace/logs/provision.$(date +%Y%m%dT%H%M%S).log"
echo "[provision] begin ${PROVISION_VERSION}" | tee -a "$LOG"

VENV_BASE=/workspace/.venvs
mkdir -p /workspace/{bin,models,notebooks,logs,ComfyUI,ai-toolkit,.provision} "$VENV_BASE"

ensure_venv () {
  local name="$1"
  local path="$VENV_BASE/$name"
  if [[ ! -d "$path" ]]; then
    python -m venv "$path"
    "$path/bin/pip" install -U pip wheel setuptools "numpy<2.1"
    echo "[provision] created venv $name" | tee -a "$LOG"
  fi
  echo "$path"
}

COMFY_VENV="$(ensure_venv comfyui-perf)"
TORCH_SPEC='torch==2.8.0+cu128 torchvision==0.23.0+cu128 torchaudio==2.8.0+cu128 --index-url https://download.pytorch.org/whl/cu128'
"$COMFY_VENV/bin/pip" install $TORCH_SPEC \
  onnx==1.17.0 onnxruntime-gpu==1.18.1 \
  opencv-python-headless==4.11.0.86 \
  insightface==0.7.3 | tee -a "$LOG"

if [[ ! -d /workspace/ComfyUI/.git ]]; then
  echo "[provision] cloning ComfyUI" | tee -a "$LOG"
  git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI | tee -a "$LOG"
else
  echo "[provision] ComfyUI repo exists; skipping clone" | tee -a "$LOG"
fi

JUPY_VENV="$(ensure_venv jupyter)"
"$JUPY_VENV/bin/pip" install -U jupyterlab | tee -a "$LOG"

CS_VERSION="4.89.1"
CS_DIR="/workspace/bin/code-server-${CS_VERSION}"
if [[ ! -x /workspace/bin/code-server ]]; then
  echo "[provision] installing code-server ${CS_VERSION}" | tee -a "$LOG"
  mkdir -p "$CS_DIR"
  curl -fsSL "https://github.com/coder/code-server/releases/download/v${CS_VERSION}/code-server-${CS_VERSION}-linux-amd64.tar.gz" \
    | tar -xz -C "$CS_DIR" --strip-components=1
  ln -sf "$CS_DIR/bin/code-server" /workspace/bin/code-server
  echo "[provision] code-server installed" | tee -a "$LOG"
else
  echo "[provision] code-server present; skipping" | tee -a "$LOG"
fi

cat >/workspace/bin/comfyctl <<'EOS'
#!/usr
