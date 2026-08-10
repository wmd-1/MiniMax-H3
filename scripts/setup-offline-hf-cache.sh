#!/usr/bin/env bash
#
# 远程离线机一次性初始化：把本地 MiniMax-H3 仓库登记为 HuggingFace 离线缓存快照，
# 供 sglang 用仓库 ID (MiniMaxAI/MiniMax-H3) 离线解析目录映射。
#
# 为什么需要它：sglang 的 MiniMax-H3 原生实现会按 HF 仓库 ID 去 HF 缓存里找文件；
# 若直接把 --model-path 指向本地目录，sglang 会回退到原生 diffusers，而 diffusers
# 没有 MiniMaxH3DiTModel，从而 AttributeError + NCCL 级联崩溃。本脚本只建 symlink，
# 不复制 ~134 GiB 权重。
#
# 用法（在远程宿主机执行一次）：
#   bash scripts/setup-offline-hf-cache.sh
# 可用环境变量覆盖路径：
#   HF_CACHE_ROOT=/model_nas/hf_cache  MODEL_DIR=/model_nas/models/MiniMax-H3
#
set -euo pipefail

HF_CACHE_ROOT="${HF_CACHE_ROOT:-/model_nas/hf_cache}"
MODEL_DIR="${MODEL_DIR:-/model_nas/models/MiniMax-H3}"
REPO_ID="MiniMaxAI/MiniMax-H3"
# 40 位 hex 假 commit，作为离线快照目录名与 refs/main 内容
REV="0000000000000000000000000000000000000000"

CACHE_REPO_DIR="$HF_CACHE_ROOT/hub/models--MiniMaxAI--MiniMax-H3"
SNAPSHOT_DIR="$CACHE_REPO_DIR/snapshots/$REV"

if [[ ! -d "$MODEL_DIR" ]]; then
  echo "ERROR: 模型目录不存在: $MODEL_DIR" >&2
  exit 1
fi

mkdir -p "$CACHE_REPO_DIR/refs" "$SNAPSHOT_DIR"

# refs/main -> REV，离线模式下 huggingface_hub 据此定位快照目录
printf '%s' "$REV" > "$CACHE_REPO_DIR/refs/main"

# 把模型根目录的每个顶层条目 symlink 进快照目录。
# 目标用容器内部绝对路径 /models/MiniMax-H3/<entry>，运行时由 docker 挂载解析。
shopt -s dotglob nullglob
for entry in "$MODEL_DIR"/*; do
  name="$(basename "$entry")"
  link="$SNAPSHOT_DIR/$name"
  # 已存在则跳过（幂等）
  if [[ -e "$link" || -L "$link" ]]; then
    echo "skip (exists): $link"
    continue
  fi
  ln -s "/models/MiniMax-H3/$name" "$link"
  echo "link: $link -> /models/MiniMax-H3/$name"
done
shopt -u dotglob nullglob

echo
echo "OK: HF 离线缓存已就绪"
echo "  快照目录: $SNAPSHOT_DIR"
echo "  容器内 sglang 会读到 /root/.cache/huggingface/hub/models--MiniMaxAI--MiniMax-H3/snapshots/$REV"
echo "  请确认 docker-compose 已挂载："
echo "    $MODEL_DIR:/models/MiniMax-H3:ro"
echo "    $HF_CACHE_ROOT:/root/.cache/huggingface:rw"
