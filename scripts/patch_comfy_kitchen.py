import pathlib
import torch
import torch.nn.functional as F
import comfy_kitchen

# --- 1. Global scaled_mm monkey-patch with memory contiguous enforcement ---
_orig_scaled_mm = torch._scaled_mm

def _safe_scaled_mm(mat1, mat2, *args, **kwargs):
    # Ensure tensors are contiguous and cast uint8 storage to float8_e4m3fn
    if isinstance(mat1, torch.Tensor) and mat1.dtype == torch.uint8:
        mat1 = mat1.contiguous().view(torch.float8_e4m3fn)
    if isinstance(mat2, torch.Tensor) and mat2.dtype == torch.uint8:
        mat2 = mat2.contiguous().view(torch.float8_e4m3fn)
    
    try:
        return _orig_scaled_mm(mat1, mat2, *args, **kwargs)
    except Exception:
        # Fallback to high-precision dequantized matmul if CUDA 12.8 driver lacks hardware kernel
        scale_a = kwargs.get("scale_a", None)
        scale_b = kwargs.get("scale_b", None)
        m1 = mat1.to(torch.bfloat16)
        m2 = mat2.to(torch.bfloat16)
        if scale_a is not None:
            m1 = m1 * scale_a
        if scale_b is not None:
            m2 = m2 * scale_b
        return torch.matmul(m1, m2), None

torch._scaled_mm = _safe_scaled_mm

# --- 2. Patch comfy_kitchen internals directly ---
p = pathlib.Path(comfy_kitchen.__file__)

patch_code = """
import torch
import torch.nn.functional as F
import comfy_kitchen as _ck

DTYPE_CODE_TO_TORCH = {0: torch.float32, 1: torch.float16, 2: torch.bfloat16}

_orig_torch_scaled_mm = torch._scaled_mm
def _safe_torch_scaled_mm(mat1, mat2, *args, **kwargs):
    if isinstance(mat1, torch.Tensor) and mat1.dtype == torch.uint8:
        mat1 = mat1.contiguous().view(torch.float8_e4m3fn)
    if isinstance(mat2, torch.Tensor) and mat2.dtype == torch.uint8:
        mat2 = mat2.contiguous().view(torch.float8_e4m3fn)
    try:
        return _orig_torch_scaled_mm(mat1, mat2, *args, **kwargs)
    except Exception:
        scale_a = kwargs.get("scale_a", None)
        scale_b = kwargs.get("scale_b", None)
        m1 = mat1.to(torch.bfloat16)
        m2 = mat2.to(torch.bfloat16)
        if scale_a is not None:
            m1 = m1 * scale_a
        if scale_b is not None:
            m2 = m2 * scale_b
        return torch.matmul(m1, m2), None
torch._scaled_mm = _safe_torch_scaled_mm

def _native_dequantize_per_tensor_fp8(x, scale, dtype):
    target_dtype = DTYPE_CODE_TO_TORCH.get(dtype, dtype) if isinstance(dtype, int) else dtype
    if x.dtype == torch.uint8:
        x = x.contiguous().view(torch.float8_e4m3fn)
    if scale is None:
        return x.to(target_dtype)
    return (x.to(torch.float32) * scale).to(target_dtype)

_ck.dequantize_per_tensor_fp8 = _native_dequantize_per_tensor_fp8
dequantize_per_tensor_fp8 = _native_dequantize_per_tensor_fp8

def _native_stochastic_rounding_fp8(tensor, dtype=torch.float8_e4m3fn, seed=None):
    return tensor.to(dtype)

_ck.stochastic_rounding_fp8 = _native_stochastic_rounding_fp8
stochastic_rounding_fp8 = _native_stochastic_rounding_fp8

def _native_rms_rope_split_half_(q, k, freqs_cis, q_scale=1.0, k_scale=1.0, epsilon=1e-5, rot_dim=None):
    q_norm = F.rms_norm(q, (q.shape[-1],), eps=epsilon)
    k_norm = F.rms_norm(k, (k.shape[-1],), eps=epsilon)
    if q_scale != 1.0:
        q_norm = q_norm * q_scale
    if k_scale != 1.0:
        k_norm = k_norm * k_scale
    rot_dim = rot_dim or (freqs_cis.shape[-1] * 2 if torch.is_complex(freqs_cis) else freqs_cis.shape[-1])
    q_rot, q_pass = q_norm[..., :rot_dim], q_norm[..., rot_dim:]
    k_rot, k_pass = k_norm[..., :rot_dim], k_norm[..., rot_dim:]
    freqs = freqs_cis
    if freqs.ndim == 3 and q_rot.ndim == 4:
        freqs = freqs.unsqueeze(1)
    elif freqs.ndim == 4 and q_rot.ndim == 4 and freqs.shape[1] != q_rot.shape[1] and freqs.shape[2] == 1:
        freqs = freqs.transpose(1, 2)
    while freqs.ndim < q_rot.ndim:
        freqs = freqs.unsqueeze(1)
    if torch.is_complex(freqs):
        q_c = torch.view_as_complex(q_rot.float().reshape(*q_rot.shape[:-1], -1, 2))
        k_c = torch.view_as_complex(k_rot.float().reshape(*k_rot.shape[:-1], -1, 2))
        q_rot = torch.view_as_real(q_c * freqs).flatten(-2).to(q.dtype)
        k_rot = torch.view_as_real(k_c * freqs).flatten(-2).to(k.dtype)
    else:
        cos = freqs.cos().to(dtype=q.dtype)
        sin = freqs.sin().to(dtype=q.dtype)
        q1, q2 = q_rot.chunk(2, dim=-1)
        k1, k2 = k_rot.chunk(2, dim=-1)
        q_rot = torch.cat([q1 * cos - q2 * sin, q1 * sin + q2 * cos], dim=-1)
        k_rot = torch.cat([k1 * cos - k2 * sin, k1 * sin + k2 * cos], dim=-1)
    if q_pass.numel() > 0:
        q.copy_(torch.cat([q_rot, q_pass], dim=-1))
        k.copy_(torch.cat([k_rot, k_pass], dim=-1))
    else:
        q.copy_(q_rot)
        k.copy_(k_rot)
    return q, k

_ck.rms_rope_split_half_ = _native_rms_rope_split_half_
_ck.rms_rope_split_half = _native_rms_rope_split_half_
rms_rope_split_half_ = _native_rms_rope_split_half_
rms_rope_split_half = _native_rms_rope_split_half_
"""

current_content = p.read_text()
if "_native_dequantize_per_tensor_fp8" not in current_content:
    p.write_text(current_content + "\n" + patch_code)
