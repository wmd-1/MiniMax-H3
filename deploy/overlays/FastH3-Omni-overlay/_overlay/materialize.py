# SPDX-License-Identifier: Apache-2.0
"""Materialize FastVideo/FastVideo-FastH3-Omni-8-Step-V1 into the base-H3 layout.

FastH3 Omni is a Ref2VA PDD student. The release carries only the
transformer (``transformer_ref/``, the same Diffusers export as FastH3 V2
plus a 32-interval PDD output head) and ``fastvideo_inference.json``; the
conditioner and both VAEs are the base MiniMax-H3 Ref2VA ones, pinned by that
contract's ``base_model_revision``.

This materializer produces a directory that SGLang's MiniMax-H3 loaders
consume with no Omni-specific weight handling at runtime:

1. ``transformer/`` - ``transformer_ref/`` (manifest tree mapping). The
   ``pdd_steps`` key is dropped from ``config.json`` so the DiT builds the
   standard-width output projections.
2. ``transformer/sglang_rope_inv_freq.safetensors`` - the derivable RoPE
   buffer the Diffusers export drops (FastH3's helper).
3. ``pdd/pdd_fused_heads.safetensors`` + ``pdd/pdd_config.json`` - the 32
   interval heads in ``proj_out`` / ``audio_proj_out`` fused into one head
   per 4-interval block with SGLang's ``tools/fuse_minimax_h3_pdd_heads``
   math. The release samples on a grid scaled to ``grid_max_t`` (0.999);
   scaling every sigma by one constant leaves the in-block dsigma weights
   unchanged, so the fusion is the tool's, and ``sigma_max`` in
   ``pdd_config.json`` tells the schedule stage to scale the grid. The model
   index points at these files through ``_minimax_h3.pdd_fused_heads``.
4. ``transformer/diffusion_pytorch_model-00001-of-00014.safetensors`` - the
   one shard holding the 32-wide heads, re-written with the first fused head
   at standard width. The DiT never uses it while the PDD heads are loaded;
   it only keeps the checkpoint shape-compatible with the native DiT.
5. ``text_encoder/``, ``tokenizer/``, ``processor/``, ``video_vae/``,
   ``audio_vae/`` - linked from ``MiniMaxAI/MiniMax-H3``'s ``Ref2VA/``
   partition at the pinned revision (already in the native-loader form),
   plus FastH3's root ``video_vae/model.safetensors`` link for the cache
   completeness probe.
"""

from __future__ import annotations

import json
import os
import shutil

import torch
from safetensors import safe_open
from safetensors.torch import save_file

UPSTREAM_H3_REPO = "MiniMaxAI/MiniMax-H3"
UPSTREAM_PARTITION = "Ref2VA"
UPSTREAM_COMPONENTS = ("text_encoder", "tokenizer", "processor", "video_vae", "audio_vae")
CONTRACT_FILE = "fastvideo_inference.json"
INDEX_FILE = "diffusion_pytorch_model.safetensors.index.json"
HEAD_KEYS = {"proj_out": "video_out", "audio_proj_out": "audio_out"}

_ROPE_FILE = "sglang_rope_inv_freq.safetensors"


def _link_or_copy_file(src: str, dst: str) -> None:
    src = os.path.realpath(src)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if os.path.lexists(dst):
        os.remove(dst)
    try:
        os.link(src, dst)
        return
    except OSError:
        pass
    try:
        os.symlink(src, dst)
        return
    except OSError:
        pass
    shutil.copy2(src, dst)


def _copytree_link_or_copy(src_dir: str, dst_dir: str) -> None:
    for root, _, files in os.walk(src_dir):
        rel_root = os.path.relpath(root, src_dir)
        target_root = dst_dir if rel_root == "." else os.path.join(dst_dir, rel_root)
        os.makedirs(target_root, exist_ok=True)
        for file_name in files:
            _link_or_copy_file(
                os.path.join(root, file_name), os.path.join(target_root, file_name)
            )


def _read_contract(source_dir: str) -> dict:
    with open(os.path.join(source_dir, CONTRACT_FILE)) as f:
        contract = json.load(f)
    expected = {
        "model_type": "ref2va",
        "transformer_component": "transformer_ref",
        "pdd_steps": 32,
        "num_inference_steps": 8,
        "pdd_step_indices": list(range(0, 33, 4)),
    }
    for key, value in expected.items():
        if contract.get(key) != value:
            raise ValueError(
                f"FastH3 Omni {CONTRACT_FILE}: expected {key}={value!r}, "
                f"got {contract.get(key)!r}"
            )
    return contract


def _link_upstream_components(contract: dict, output_dir: str) -> None:
    """Link the Ref2VA conditioner and VAEs at the contract's pinned revision.

    Offline deployments can set ``FASTH3_OMNI_LOCAL_BASE`` to a local MiniMax-H3
    root (the directory that contains ``Ref2VA/``) and the components are linked
    straight from there without any hub access. Without that variable the
    original hub behaviour is kept.
    """
    local_base = os.environ.get("FASTH3_OMNI_LOCAL_BASE", "").strip()
    if local_base:
        snapshot = os.path.expanduser(local_base)
        if not os.path.isdir(os.path.join(snapshot, UPSTREAM_PARTITION)):
            raise ValueError(
                f"FASTH3_OMNI_LOCAL_BASE={local_base!r} has no "
                f"{UPSTREAM_PARTITION}/ directory"
            )
    else:
        from huggingface_hub import snapshot_download

        base = str(contract.get("base_model_revision", ""))
        prefix = f"hf://{UPSTREAM_H3_REPO}@"
        if not base.startswith(prefix):
            raise ValueError(
                f"FastH3 Omni base_model_revision must pin {UPSTREAM_H3_REPO}, got {base!r}"
            )
        snapshot = snapshot_download(
            UPSTREAM_H3_REPO,
            revision=base[len(prefix) :],
            allow_patterns=[
                f"{UPSTREAM_PARTITION}/{component}/**" for component in UPSTREAM_COMPONENTS
            ],
            max_workers=8,
        )
    for component in UPSTREAM_COMPONENTS:
        src = os.path.join(snapshot, UPSTREAM_PARTITION, component)
        if not os.path.isdir(src):
            raise ValueError(f"{UPSTREAM_H3_REPO} snapshot is missing {src}")
        _copytree_link_or_copy(src, os.path.join(output_dir, component))
    # The native decoder loads video_vae/source/model.safetensors; the
    # completeness probe only looks at the component root (as for FastH3).
    _link_or_copy_file(
        os.path.join(output_dir, "video_vae", "source", "model.safetensors"),
        os.path.join(output_dir, "video_vae", "model.safetensors"),
    )


def _write_transformer_config(output_dir: str) -> int:
    path = os.path.join(output_dir, "transformer", "config.json")
    with open(path) as f:
        config = json.load(f)
    pdd_steps = int(config.pop("pdd_steps"))
    if os.path.lexists(path):
        os.remove(path)
    with open(path, "w") as f:
        json.dump(config, f, indent=2, sort_keys=True)
    return pdd_steps


def _write_rope_inv_freq(*, source_dir: str, output_dir: str) -> None:
    with open(os.path.join(source_dir, "transformer_ref", "config.json")) as f:
        rope_freq_dim = int(json.load(f)["rope_freq_dim"])
    exponents = torch.arange(0, 2 * rope_freq_dim, 2, dtype=torch.float32) / (
        2 * rope_freq_dim
    )
    inv_freq = 1.0 / (10000.0**exponents)
    transformer_dir = os.path.join(output_dir, "transformer")
    save_file({"rope.inv_freq": inv_freq}, os.path.join(transformer_dir, _ROPE_FILE))

    index_path = os.path.join(transformer_dir, INDEX_FILE)
    with open(index_path) as f:
        index = json.load(f)
    index["weight_map"]["rope.inv_freq"] = _ROPE_FILE
    if os.path.lexists(index_path):
        os.remove(index_path)
    with open(index_path, "w") as f:
        json.dump(index, f, indent=2, sort_keys=True)


def _fuse_pdd_heads(*, contract: dict, pdd_steps: int, output_dir: str) -> None:
    """Fuse the interval heads and re-write their shard at standard width."""
    from sglang.multimodal_gen.tools.fuse_minimax_h3_pdd_heads import fuse, sigma_grid

    transformer_dir = os.path.join(output_dir, "transformer")
    with open(os.path.join(transformer_dir, INDEX_FILE)) as f:
        weight_map = json.load(f)["weight_map"]
    shards = {weight_map[f"{name}.{kind}"] for name in HEAD_KEYS for kind in ("weight", "bias")}
    if len(shards) != 1:
        raise ValueError(f"FastH3 Omni output heads span several shards: {shards}")
    shard = shards.pop()
    shard_path = os.path.join(transformer_dir, shard)

    steps = int(contract["num_inference_steps"])
    block = pdd_steps // steps
    shifts = {
        "proj_out": float(contract["video_scheduler_shift"]),
        "audio_proj_out": float(contract["audio_scheduler_shift"]),
    }
    tensors: dict[str, torch.Tensor] = {}
    fused: dict[str, torch.Tensor] = {}
    with safe_open(shard_path, "pt") as f:
        for key in f.keys():
            name, _, kind = key.rpartition(".")
            if name not in HEAD_KEYS:
                tensors[key] = f.get_tensor(key)
                continue
            # Interval-major: rows [i * out, (i + 1) * out) are interval i's head.
            stored = f.get_tensor(key)
            heads = stored.float().unflatten(0, (pdd_steps, -1))
            stacked = fuse(heads, sigma_grid(pdd_steps + 1, shifts[name]), block)
            fused[f"{HEAD_KEYS[name]}.{kind}"] = stacked.contiguous()
            tensors[key] = stacked[0].to(stored.dtype).contiguous()
    if len(fused) != 4:
        raise ValueError(f"FastH3 Omni shard {shard} is missing output heads")

    # The shard is a link into the hub cache; replace it, never write through it.
    os.remove(shard_path)
    save_file(tensors, shard_path, metadata={"format": "pt"})

    pdd_dir = os.path.join(output_dir, "pdd")
    os.makedirs(pdd_dir, exist_ok=True)
    save_file(
        fused,
        os.path.join(pdd_dir, "pdd_fused_heads.safetensors"),
        metadata={"format": "pt"},
    )
    config = {
        "num_steps": pdd_steps,
        "block_size": block,
        "fused_steps": steps,
        "num_inference_steps": steps,
        "video_shift": shifts["proj_out"],
        "audio_shift": shifts["audio_proj_out"],
        "sigma_max": float(contract.get("grid_max_t", 1.0)),
    }
    with open(os.path.join(pdd_dir, "pdd_config.json"), "w") as f:
        json.dump(config, f, indent=2)
        f.write("\n")


def materialize(
    *, overlay_dir: str, source_dir: str, output_dir: str, manifest: dict
) -> None:
    contract = _read_contract(source_dir)
    _link_upstream_components(contract, output_dir)
    pdd_steps = _write_transformer_config(output_dir)
    _write_rope_inv_freq(source_dir=source_dir, output_dir=output_dir)
    _fuse_pdd_heads(contract=contract, pdd_steps=pdd_steps, output_dir=output_dir)
