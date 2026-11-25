# 固定到已发布的稳定版 tag（含 MiniMax-H3 原生 diffusion 后端，day-0 自 v0.5.17 起）。
# 2026-10-24：base 从 v0.5.21 切到 v0.5.22（三套变体已在该版本验证：FastH3 V2 / VDN / PDD）。
# 切版后需在既有 Docker 环境回归 compose 依赖的 serve 参数
# （--model-variant ref2va / --performance-mode / --layerwise-offload-components /
#   --dit-layerwise-resident-layers / --scheduler-rpc-timeout）。
# 注：官方 MiniMax-H3 Cookbook 仍推荐 lmsysorg/sglang:dev + 源码重装，
#     因为 H3 diffusion 在 main 上迭代快；dev -> v0.5.22 会丢掉 tag 之后的修复。
#
# ⚠️ 范围：本文件只用于部署 base 模型（MiniMaxAI/MiniMax-H3 主干，
#    即根目录 docker-compose.yml 的 minimax-h3-0..3，--model-variant ref2va）。
#    它构建出的是「base 子集」镜像：只断言原生 backend 与 ref2va 变体存在，
#    不含三套加速变体的构建期断言（FastH3-8-Step 配置 / minimax_h3_vdn pipeline /
#    PDD build·fuse 工具）。要跑 deploy/ 下的 fasth3-8step-v2、vdn-h3、
#    pai-acc-loras-ref2va，请改用 Dockerfile.sglang（根目录，内容等同
#    deploy/images/Dockerfile.sglang）；两者产出同一个 tag，用本文件构建会
#    覆盖掉变体的早失败保护。
FROM lmsysorg/sglang:v0.5.22

# PyPI 官方源在当前网络下首字节延迟高（ttfb 秒级），会让 pip 的构建隔离依赖解析
# （setuptools/setuptools-rust/setuptools-scm/wheel）与 [diffusion] 大依赖树龟速卡住。
# 用 ENV 覆盖 index，确保外层 pip 与 build isolation 内层子 pip 都走国内镜像。
# 可通过 --build-arg PIP_INDEX_URL=... 覆盖（例如切回官方源 https://pypi.org/simple）。
ARG PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
ENV PIP_INDEX_URL=${PIP_INDEX_URL}

WORKDIR /sgl-workspace/sglang

RUN pip install -e "python[diffusion]"

RUN pip install \
    huggingface_hub \
    accelerate \
    hf_transfer

# 早失败：确认这版镜像仍是 MiniMax-H3 原生 backend（宽松匹配，避免上游改名误判），
# 且 compose 默认使用的 --model-variant ref2va 在源码里存在。
RUN grep -rq "MiniMax-H3" python/sglang/multimodal_gen/configs/ && \
    grep -rqi "ref2va" python/sglang/multimodal_gen/

RUN apt-get update && \
    apt-get install -y --no-install-recommends ffmpeg && \
    rm -rf /var/lib/apt/lists/*

# 构建（仅 base；tag 与 FROM 版本对齐）：
#   docker build -f Dockerfile -t sglang-video:v0.5.22 .
# 四套共用（base + FastH3 V2 + VDN + PDD）请建这一份，它多了三套变体的构建断言：
#   docker build -f Dockerfile.sglang -t sglang-video:v0.5.22 .
#   （deploy/images/Dockerfile.sglang 与根目录 Dockerfile.sglang 是同一份内容，
#     deploy 下三个变体 compose 的 build: 指向后者；改一份要同步另一份）
# 见 docs/HANDOFF-4-variants.md。