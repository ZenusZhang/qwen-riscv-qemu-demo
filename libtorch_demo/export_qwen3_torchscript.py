#!/usr/bin/env python3

import argparse
import importlib.metadata
from pathlib import Path

import contextlib
import sys
import types

import torch


def _install_register_fake_noop() -> None:
    register_fake = getattr(getattr(torch, "library", None), "register_fake", None)
    if register_fake is None:
        return

    def _noop_register_fake(*args, **kwargs):
        def decorator(fn):
            return fn

        return decorator

    torch.library.register_fake = _noop_register_fake


_install_register_fake_noop()


def _compiler_disable_stub(fn=None, recursive=True, *, reason=None):
    if fn is None:
        def decorator(f):
            return f
        return decorator
    return fn


class _CompilerStub:
    disable = staticmethod(_compiler_disable_stub)

    @staticmethod
    def is_compiling() -> bool:
        return False

    @staticmethod
    def is_exporting() -> bool:
        return False


if "torch.compiler" not in sys.modules:
    sys.modules["torch.compiler"] = _CompilerStub()
else:
    compiler_module = sys.modules["torch.compiler"]
    setattr(compiler_module, "disable", _CompilerStub.disable)


class _DynamoStub(types.ModuleType):
    def __init__(self) -> None:
        super().__init__("torch._dynamo")

    def allow_in_graph(self, fn=None):
        if fn is None:
            def decorator(func):
                return func
            return decorator
        return fn

    def disable(self, fn=None, recursive=True, reason=None):
        if fn is None:
            def decorator(func):
                return func
            return decorator
        return fn

    def is_compiling(self) -> bool:
        return False

    def is_exporting(self) -> bool:
        return False

    def assume_constant_result(self, fn):
        return fn

    def substitute_in_graph(self, original_fn, **kwargs):
        return original_fn

    def list_backends(self, exclude_tags=None):
        return []

    def __getattr__(self, name):
        def _noop(*args, **kwargs):
            return None

        return _noop


sys.modules.setdefault("torch._dynamo", _DynamoStub())

_trace_stub = types.ModuleType("torch._dynamo._trace_wrapped_higher_order_op")
_trace_stub.TransformGetItemToIndex = lambda *args, **kwargs: None
sys.modules.setdefault("torch._dynamo._trace_wrapped_higher_order_op", _trace_stub)


_model_debug_module = types.ModuleType("transformers.model_debugging_utils")
_model_debug_module.model_addition_debugger_context = contextlib.nullcontext
sys.modules.setdefault("transformers.model_debugging_utils", _model_debug_module)

_real_importlib_version = importlib.metadata.version


def _patched_version(package: str) -> str:
    if package == "torch":
        return "2.5.0"
    return _real_importlib_version(package)


importlib.metadata.version = _patched_version

from transformers import AutoModelForCausalLM, AutoTokenizer
importlib.metadata.version = _real_importlib_version

from typing import Dict


def resolve_dtype(dtype_str: str) -> torch.dtype:
    normalized = dtype_str.lower()
    aliases = {
        "float32": torch.float32,
        "fp32": torch.float32,
        "f32": torch.float32,
        "float": torch.float32,
        "float16": torch.float16,
        "fp16": torch.float16,
        "f16": torch.float16,
        "half": torch.float16,
        "bfloat16": torch.bfloat16,
        "bf16": torch.bfloat16,
        "float64": torch.float64,
        "double": torch.float64,
    }
    if normalized not in aliases:
        raise ValueError(f"Unsupported dtype: {dtype_str}")
    return aliases[normalized]


def prepare_inputs(tokenizer, prompt: str, device: torch.device, enable_thinking: bool) -> Dict[str, torch.Tensor]:
    encoded = None

    if enable_thinking:
        apply_chat = getattr(tokenizer, "apply_chat_template", None)
        if callable(apply_chat):
            messages = [{"role": "user", "content": prompt}]
            try:
                text = apply_chat(
                    messages,
                    tokenize=False,
                    add_generation_prompt=False,
                    enable_thinking=True,
                )
            except TypeError:
                text = apply_chat(
                    messages,
                    tokenize=False,
                    add_generation_prompt=False,
                )
            encoded = tokenizer(text, return_tensors="pt")

    if encoded is None:
        encoded = tokenizer(prompt, return_tensors="pt")

    return {k: v.to(device) for k, v in encoded.items()}


def install_torchscript_friendly_mask() -> None:
    try:
        from transformers import masking_utils
    except ImportError:
        masking_utils = None

    if masking_utils is None:
        return

    def eager_mask(
        batch_size: int,
        cache_position: torch.Tensor,
        kv_length: int,
        kv_offset: int = 0,
        mask_function=None,
        attention_mask: torch.Tensor | None = None,
        dtype: torch.dtype = torch.float32,
        **kwargs,
    ) -> torch.Tensor:
        q_positions = cache_position.unsqueeze(-1)
        kv_positions = torch.arange(kv_length, device=cache_position.device)
        base_mask = kv_positions.unsqueeze(0) <= q_positions
        base_mask = base_mask.unsqueeze(0).expand(batch_size, -1, -1)

        if attention_mask is not None:
            slice_end = min(attention_mask.size(-1), kv_offset + kv_length)
            attn_slice = attention_mask[:, kv_offset:slice_end]
            if attn_slice.size(-1) != kv_length:
                pad = torch.zeros(
                    (attention_mask.size(0), kv_length),
                    dtype=attention_mask.dtype,
                    device=attention_mask.device,
                )
                pad[:, : attn_slice.size(-1)] = attn_slice
                attn_slice = pad
            attn_slice = attn_slice.bool().unsqueeze(1).expand_as(base_mask)
            base_mask = base_mask & attn_slice

        zeros = torch.zeros((), dtype=dtype, device=base_mask.device)
        neg_inf = torch.tensor(torch.finfo(dtype).min, dtype=dtype, device=base_mask.device)
        return torch.where(base_mask.unsqueeze(1), zeros, neg_inf)

    masking_utils.ALL_MASK_ATTENTION_FUNCTIONS["eager"] = eager_mask


class CausalLMForwardWrapper(torch.nn.Module):
    def __init__(self, model: torch.nn.Module):
        super().__init__()
        self.model = model

    def forward(self, input_ids: torch.Tensor, attention_mask: torch.Tensor) -> torch.Tensor:
        outputs = self.model(
            input_ids=input_ids,
            attention_mask=attention_mask,
            use_cache=False,
            return_dict=False,
        )
        return outputs[0]


def export_model(model_dir: Path, output_path: Path, prompt: str, dtype_str: str, enable_thinking: bool) -> None:
    device = torch.device("cpu")
    dtype = resolve_dtype(dtype_str)

    install_torchscript_friendly_mask()

    tokenizer = AutoTokenizer.from_pretrained(
        model_dir,
        local_files_only=True,
        trust_remote_code=True,
    )
    model_load_kwargs = dict(
        attn_implementation="eager",
        torch_dtype=dtype,
        local_files_only=True,
        trust_remote_code=True,
    )
    try:
        model = AutoModelForCausalLM.from_pretrained(
            model_dir,
            **model_load_kwargs,
        )
    except ValueError:
        from transformers.models.qwen3.modeling_qwen3 import Qwen3ForCausalLM

        model = Qwen3ForCausalLM.from_pretrained(
            model_dir,
            **model_load_kwargs,
        )
    model.to(device)
    model.eval()

    wrapper = CausalLMForwardWrapper(model)
    wrapper.eval()

    inputs = prepare_inputs(tokenizer, prompt, device, enable_thinking)
    example_inputs = (inputs["input_ids"], inputs["attention_mask"])

    with torch.inference_mode():
        scripted = torch.jit.trace(wrapper, example_inputs, strict=False)
        scripted = torch.jit.freeze(scripted)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    torch.jit.save(scripted, output_path)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Export Qwen model to TorchScript")
    parser.add_argument("--model-dir", type=Path, default=Path("models/Qwen3-0.6B"))
    parser.add_argument("--output", type=Path, default=Path("models/Qwen3-0.6B/qwen3_0_6b.ts"))
    parser.add_argument("--prompt", type=str, default="Hello, how are you?")
    parser.add_argument("--dtype", type=str, default="float32")
    parser.add_argument("--enable-thinking", action="store_true")
    parser.add_argument("--disable-thinking", action="store_false", dest="enable_thinking")
    parser.set_defaults(enable_thinking=True)

    args = parser.parse_args()
    export_model(args.model_dir, args.output, args.prompt, args.dtype, args.enable_thinking)
