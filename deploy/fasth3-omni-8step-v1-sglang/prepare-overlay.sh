#!/usr/bin/env bash
# FastH3-Omni：单进程预热 overlay 物化（幂等，可反复执行）
#
# 作用：在起任何实例之前，用一个一次性容器把
#   /sglang-cache/omni/materialized_models/FastVideo__FastVideo-FastH3-Omni-8-Step-V1-<key>
# 物化出来。4 个实例启动时都会直接命中这份成品，不再各自物化，
# 从而避免多容器同时删同一个 <key>.tmp 而报 FileNotFoundError。
#
# 只在「首次部署」或「改过 ./overlay 下文件」后需要跑一次；
# 物化已经完整时它会立刻返回（几秒）。
#
# 用法：
#   bash prepare-overlay.sh                 # 默认路径
#   CACHE_HOST=/data/xxx IMG=... bash prepare-overlay.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

IMG="${IMG:-sglang-video:v0.5.23}"
SRC_HOST="${SRC_HOST:-/model_nas/models/minimax_models/FastVideo/FastVideo-FastH3-Omni-8-Step-V1}"
BASE_HOST="${BASE_HOST:-/model_nas/models/MiniMax-H3}"
CACHE_HOST="${CACHE_HOST:-/model_nas/sglang-cache}"
HF_HOST="${HF_HOST:-/model_nas/hf-cache}"
BASE_REV="${BASE_REV:-9bfb6693f2cf6de171db46d1aa586f67d773a1da}"

echo "[prepare-overlay] image=$IMG"
echo "[prepare-overlay] overlay=$HERE/overlay"
echo "[prepare-overlay] cache=$CACHE_HOST -> /sglang-cache"

docker run --rm -i \
  -v "$HERE/overlay:/models/FastH3-Omni-overlay:ro" \
  -v "$SRC_HOST:/models/FastVideo/FastVideo-FastH3-Omni-8-Step-V1:ro" \
  -v "$CACHE_HOST:/sglang-cache:rw" \
  -v "$HF_HOST:/hf-cache:rw" \
  -v "$BASE_HOST:/hf-cache/hub/models--MiniMaxAI--MiniMax-H3/snapshots/$BASE_REV:ro" \
  -e HF_HOME=/hf-cache \
  -e HF_HUB_OFFLINE=1 \
  -e PYTHONDONTWRITEBYTECODE=1 \
  -e SGLANG_DIFFUSION_CACHE_ROOT=/sglang-cache/omni \
  -e 'SGLANG_DIFFUSION_MODEL_OVERLAY_REGISTRY={"FastVideo/FastVideo-FastH3-Omni-8-Step-V1":{"overlay_repo_id":"/models/FastH3-Omni-overlay","overlay_revision":"953ede55daf20a70cc6f0b59464293e2f408608c","source_revision":"53e0d26a1691aa473b6262d8196a8feb2c297df0"}}' \
  --entrypoint python "$IMG" - <<'PY'
from sglang.multimodal_gen.runtime.utils.model_overlay import (
    materialize_overlay_model,
    resolve_model_overlay_target,
)
from sglang.multimodal_gen.runtime.utils.hf_diffusers_utils import (
    _verify_diffusers_model_complete,
)

SRC = "/models/FastVideo/FastVideo-FastH3-Omni-8-Step-V1"
src_id, spec = resolve_model_overlay_target(SRC)
print("[prepare-overlay] source:", src_id)
out = materialize_overlay_model(
    source_model_id=src_id,
    overlay_spec=spec,
    overlay_dir=spec["overlay_repo_id"],
    source_dir=SRC,
    verify_diffusers_model_complete_fn=_verify_diffusers_model_complete,
    source_revision=spec.get("source_revision"),
)
print("[prepare-overlay] MATERIALIZED:", out)
PY

echo "[prepare-overlay] done."
