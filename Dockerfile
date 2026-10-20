# 固定到已发布的稳定版 tag（含 MiniMax-H3 原生 diffusion 后端，day-0 自 v0.5.17 起）。
# 切版后需在既有 Docker 环境回归 compose 依赖的 serve 参数
# （--model-variant / --performance-mode / --layerwise-offload-components /
#   --dit-layerwise-resident-layers / --watchdog-timeout）。
# 注：官方 MiniMax-H3 Cookbook 仍推荐 lmsysorg/sglang:dev + 源码重装，
#     因为 H3 diffusion 在 main 上迭代快；dev -> v0.5.21 会丢掉 tag 之后的修复。
FROM lmsysorg/sglang:v0.5.21

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

RUN apt-get update && \
    apt-get install -y --no-install-recommends ffmpeg && \
    rm -rf /var/lib/apt/lists/*