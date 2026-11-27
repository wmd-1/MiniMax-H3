# SPDX-License-Identifier: Apache-2.0
# ---------------------------------------------------------------------------
# 来源：Hugging Face `Niehen6174/Pika-H3-Flex-overlay`
#       revision 2d8d5e4d81d2ad0ba4b0bbcf7049231bfbe3e9c2（SGLang 内置注册表为
#       Pika-Labs/Pika-H3-Flex 指向的那份 overlay），路径 `_overlay/materialize.py`。
# 本文件 = 上游逐字副本 + 两处离线补丁：
#   (1) 新增本注释块；
#   (2) base 快照可通过 PIKA_H3_LOCAL_BASE 指定为本地目录（不设时行为与上游一致，
#       仍走 snapshot_download）。原因：迁移服务器 HF_HUB_OFFLINE=1 且没有 HF cache，
#       上游的 snapshot_download 会打到 /api/models/MiniMaxAI/MiniMax-H3/tree/… 并抛
#       OfflineModeIsEnabled；改成直接链接本地 base 目录后完全不经过 Hub。
# 它随 deploy/pika-h3-flex/overlay/ 一起搬到迁移服务器，配合 compose 里的
#   SGLANG_DIFFUSION_MODEL_OVERLAY_REGISTRY={"Pika-Labs/Pika-H3-Flex":{
#       "overlay_repo_id":"/models/Pika-H3-Flex-overlay", ...}}
# 使用，从而完全离线、不下载 overlay 元数据。
#
# 离线部署要点（对应 compose 的 volumes ①②）：
#   - source_dir（Pika 适配器）由 sglang 用
#     snapshot_download("Pika-Labs/Pika-H3-Flex", revision=3ff1664…, allow_patterns=
#     manifest 里的 source_allow_patterns) 解析；离线时命中
#     $HF_HOME/hub/models--Pika-Labs--Pika-H3-Flex/snapshots/3ff1664… 即原样返回。
#   - 下面的 snapshot_download("MiniMaxAI/MiniMax-H3", revision=<manifest pin>) 同理，
#     依赖 $HF_HOME/hub/models--MiniMaxAI--MiniMax-H3/snapshots/42ed227e…。
#   - 适配器仍会做 sha256 比对（fail-fast）；不要为了“跑起来”去改这里。
# ---------------------------------------------------------------------------
"""Materialize Pika-Labs/Pika-H3-Flex into the base-H3 layout.

Pika H3 Flex ships two FP32 LoRA adapters (``fl2va/`` and ``ref2va/``, PEFT
names on the Diffusers MiniMax-H3 module layout) plus a Diffusers re-export of
the MiniMax-H3 base. SGLang serves the native MiniMax-H3 base instead, so this
materializer downloads nothing but the adapters from the source repo and links
the base partitions from ``MiniMaxAI/MiniMax-H3`` at the revision each adapter
manifest pins:

1. root and ``FL2VA/`` - the base ``FL2VA/`` partition (t2va, fl2va) plus the
   fl2va adapter at ``pika/adapter.safetensors``.
2. ``Ref2VA/`` - the base ``Ref2VA/`` partition (ref2va) plus the ref2va
   adapter at ``pika/adapter.safetensors``.
3. a ``model_index.json`` per partition whose ``_minimax_h3`` block carries
   the adapters' sampling contract, checked against each manifest here.

SGLang applies the adapter at load through its LoRA path, which maps the PEFT
``transformer_blocks.N.attn.to_{q,k,v}`` / ``ff.net.{0.proj,2}`` names onto the
native fused ``qkv_proj`` / ``mlp.fc1`` / ``mlp.fc2``.
"""

from __future__ import annotations

import copy
import hashlib
import json
import os
import shutil

UPSTREAM_H3_REPO = "MiniMaxAI/MiniMax-H3"
COMPONENTS = (
    "text_encoder",
    "tokenizer",
    "processor",
    "video_vae",
    "audio_vae",
    "transformer",
)
# partition dir -> (adapter task, trunk, numerics policy, tasks)
PARTITIONS = {
    "FL2VA": ("fl2va", "transformer", "bf16_conditioning_v1", ["t2va", "fl2va"]),
    "Ref2VA": ("ref2va", "transformer_ref", "fp32_conditioning_v1", ["ref2va"]),
}
EXPECTED_SAMPLING = {
    "knots": [1000, 750, 500, 250, 100, 40, 0],
    "video_shift": 12.0,
    "audio_shift": 3.0,
    "method": "renoise",
}
ADAPTER_REL = "pika/adapter.safetensors"


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


def _sha256(path: str) -> str:
    hasher = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 24), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def _read_adapter_manifest(source_dir: str, task: str, trunk: str, policy: str) -> dict:
    with open(os.path.join(source_dir, task, "manifest.json")) as f:
        manifest = json.load(f)
    expected = {
        "format_version": 1,
        "task": task,
        "trunk": trunk,
        "numerics_policy": policy,
        "rank": 128,
        "alpha": 128,
        "sampling": EXPECTED_SAMPLING,
    }
    for key, value in expected.items():
        if manifest.get(key) != value:
            raise ValueError(
                f"Pika H3 Flex {task}/manifest.json: expected {key}={value!r}, "
                f"got {manifest.get(key)!r}"
            )
    base = manifest.get("base") or {}
    if base.get("repo_id") != UPSTREAM_H3_REPO or not base.get("revision"):
        raise ValueError(
            f"Pika H3 Flex {task}/manifest.json must pin {UPSTREAM_H3_REPO}, got {base!r}"
        )
    adapter = os.path.join(source_dir, task, "adapter.safetensors")
    if _sha256(adapter) != manifest.get("sha256"):
        raise ValueError(f"Pika H3 Flex {adapter} does not match its manifest sha256")
    return manifest


def _model_index(template: dict, partition: str) -> dict:
    task, _, _, tasks = PARTITIONS[partition]
    model_index = copy.deepcopy(template)
    release = model_index["_minimax_h3"]
    release["partition"] = task
    release["tasks"] = tasks
    release["dmd_denoising_steps"] = [k for k in EXPECTED_SAMPLING["knots"] if k > 0]
    release["sigma_shift_scales"] = {
        "video": EXPECTED_SAMPLING["video_shift"],
        "audio": EXPECTED_SAMPLING["audio_shift"],
    }
    release["stochastic_sampling"] = True
    release["lora_adapter"] = ADAPTER_REL
    return model_index


def _write_json(path: str, payload: dict) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.lexists(path):
        os.remove(path)
    with open(path, "w") as f:
        json.dump(payload, f, indent=2)
        f.write("\n")


def _link_partition(snapshot: str, partition: str, adapter: str, dst_dir: str) -> None:
    for component in COMPONENTS:
        src = os.path.join(snapshot, partition, component)
        if not os.path.isdir(src):
            raise ValueError(f"{UPSTREAM_H3_REPO} snapshot is missing {src}")
        _copytree_link_or_copy(src, os.path.join(dst_dir, component))
    # The native decoder loads video_vae/source/model.safetensors; the
    # completeness probe only looks at the component root (as for FastH3).
    _link_or_copy_file(
        os.path.join(dst_dir, "video_vae", "source", "model.safetensors"),
        os.path.join(dst_dir, "video_vae", "model.safetensors"),
    )
    _link_or_copy_file(adapter, os.path.join(dst_dir, ADAPTER_REL))


def _resolve_base_snapshot(revisions: set[str]) -> str:
    """Locate the base MiniMax-H3 snapshot that provides ``FL2VA/`` and ``Ref2VA/``.

    Offline deployments set ``PIKA_H3_LOCAL_BASE`` to a local MiniMax-H3 root (the
    directory that contains ``FL2VA/``) and the components are linked straight from
    there without any hub access. Without that variable the original hub behaviour
    is kept.
    """
    local_base = os.environ.get("PIKA_H3_LOCAL_BASE", "").strip()
    if local_base:
        snapshot = os.path.expanduser(local_base)
        if not os.path.isdir(os.path.join(snapshot, "FL2VA")):
            raise ValueError(
                f"PIKA_H3_LOCAL_BASE={local_base!r} has no FL2VA/ directory"
            )
        return snapshot

    from huggingface_hub import snapshot_download

    return snapshot_download(
        UPSTREAM_H3_REPO,
        revision=next(iter(revisions)),
        allow_patterns=[
            f"{partition}/{component}/**"
            for partition in PARTITIONS
            for component in COMPONENTS
        ],
        max_workers=8,
    )


def materialize(*, overlay_dir: str, source_dir: str, output_dir: str, manifest: dict) -> None:
    with open(os.path.join(overlay_dir, "model_index.json")) as f:
        template = json.load(f)

    manifests = {
        partition: _read_adapter_manifest(source_dir, task, trunk, policy)
        for partition, (task, trunk, policy, _) in PARTITIONS.items()
    }
    revisions = {m["base"]["revision"] for m in manifests.values()}
    if len(revisions) != 1:
        raise ValueError(f"Pika H3 Flex adapters pin different bases: {revisions}")
    snapshot = _resolve_base_snapshot(revisions)

    for partition, (task, _, _, _) in PARTITIONS.items():
        adapter = os.path.join(source_dir, task, "adapter.safetensors")
        targets = [os.path.join(output_dir, partition)]
        if partition == "FL2VA":
            # the root serves t2va/fl2va when no --model-variant is given
            targets.append(output_dir)
        for target in targets:
            _link_partition(snapshot, partition, adapter, target)
            _write_json(
                os.path.join(target, "model_index.json"),
                _model_index(template, partition),
            )
    for name in ("LICENSE", "NOTICE"):
        src = os.path.join(source_dir, name)
        if os.path.isfile(src):
            _link_or_copy_file(src, os.path.join(output_dir, name))
