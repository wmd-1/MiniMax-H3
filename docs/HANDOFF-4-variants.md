# HANDOFF：四个 MiniMax-H3 变体的 vLLM / SGLang 部署

> 适用目录：`deploy/`
> 目标机：4×A100-40G SXM（NV12）、384 GiB 主机内存
> 状态：compose 语法与插值已校验（`docker compose config -q` 全过）；
> **尚未在 GPU 上启动**，WSL 环境无 NVIDIA 驱动，峰值显存/吞吐需在 A100 机器补测。

---

## 1. 版本与选型矩阵

| 模型 | 引擎 | 镜像 tag | 拓扑 | 端口（宿主，4 实例） | 任务能力 |
|---|---|---|---|---|---|
| FastVideo-FastH3-8-Step-V2 | SGLang v0.5.22 | `video-sglang:v0.5.22` | TP2 | 30030-30033 | 仅 T2VA |
| lightx2v/Minimax-h3-Turbo | vLLM-Omni v0.32.0rc1 | `video-vllm:v0.32.0rc1` | TP2 + DLO | 8010-8013 | Ref2VA（8step 768p） |
| OpenVDN/vdn-minimax-h3 | SGLang v0.5.22 | `video-sglang:v0.5.22` | TP2 | 30040-30043 | T2VA / FL2VA |
| alibaba-pai/MiniMax-H3-Acc-LoRAs | SGLang v0.5.22 | `video-sglang:v0.5.22` | TP2 | 30020-30023 | Ref2VA（PDD 8step） |

> 每套都是 4 实例（每实例 TP2），容器内端口固定（SGLang 30010 / vLLM 8000），
> 只把宿主发布端口区段错开。base 服务另占 SGLang 30010-30013 / vLLM 8000-8003。

**为什么没有全部用 vLLM：**

- **FastH3 V2**：vLLM-Omni 的 FastH3-V2 contract 硬性要求
  `--diffusion-attention-backend FASTVIDEO_VSA`；该 VSA 面向 SM90/SM100，
  A100(SM80) 不可用，vLLM 也没有稠密回退。SGLang v0.5.22 明确允许
  `--component-attention-backends transformer=fa` 用稠密注意力跑同一份权重。
- **VDN**：SGLang 文档明确 SM80 走 bf16 DiT + layerwise offload；vLLM 的
  `VDNH3_ATTN` 要 v0.32.0rc1 才加入，且其 `check_serving_contract` 明确拒绝
  `DISTRIBUTED_LAYER_WISE`（DLO），40G 卡上没法用；本仓库 vLLM 现已升到 0.32.0rc1
  （有 VDNH3_ATTN），但 DLO 这条限制没变，所以 VDN 仍走 SGLang。
- **PAI PDD**：PDD 不是普通 LoRA，必须离线合并主干 + 融合 32 个区间输出头；
  这两个工具只在 SGLang 的 `sglang.multimodal_gen.tools` 里。
- **LightX2V**：vLLM-Omni 官方支持，请求级 LoRA，不需要离线融合，因此优先 vLLM。

**镜像策略：**base 与三套 SGLang 变体共用 `video-sglang:v0.5.22`
（根目录 `Dockerfile` 与 `deploy/images/Dockerfile.sglang` 产出同一 tag，后者多三套
变体的构建断言，建一次即可）。vLLM 侧 **不新建镜像**：LightX2V 与 base 共用
`video-vllm:v0.32.0rc1`（根目录 `Dockerfile.vllm` 产出的 tag），差别只在命令行
（base 是 50 步 ref2va，本服务多一个 `--lora-path` + 请求级 `lora`）。

---

## 2. 文件清单

```
deploy/
  images/
    Dockerfile.sglang          # v0.5.22；base + FastH3 V2 + VDN + PDD 四套共用（根目录 Dockerfile 的超集）
  fasth3-8step-v2/
    docker-compose.yml
  lightx2v-turbo-ref2va/
    docker-compose.yml         # 复用根目录 Dockerfile.vllm 的产物，无独立镜像
  vdn-h3/
    docker-compose.yml
  pai-acc-loras-ref2va/
    docker-compose.yml
```

每套 compose 都是 4 实例（每实例 TP2 独占一对卡）：实例 0/1/2/3 固定用 GPU
`0,1` / `2,3` / `4,5` / `6,7`；容器内端口固定，宿主端口按套分区发布。
要换 GPU 对，直接改对应 service 的 `deploy ... device_ids`（已不再用 `GPU0`/`GPU1` 变量）。

一套 compose 就会占满 8 张卡，四套变体（以及 base 的 4 实例）互斥，不能同时起。

---

## 3. 启动前检查

### 3.1 拉镜像 / 构建

```bash
docker pull lmsysorg/sglang:v0.5.22

# 四套（base + 三套变体）共用这个 tag，在任一目录构建一次即可
cd /home/wmd/projects/MiniMax-H3/deploy/fasth3-8step-v2 && docker compose build

# lightx2v-turbo-ref2va 无 build 段，直接用已有 video-vllm:v0.32.0rc1
```

> LightX2V 和 base 服务同样跑在 vLLM-Omni v0.32.0rc1，只是多一个 `--lora-path`，
> 所以不再单独建镜像（原 `deploy/images/Dockerfile.vllm` 已删，避免和根目录
> `Dockerfile.vllm` 两处漂移）。本机没有 `video-vllm:v0.32.0rc1` 时，在仓库
> 根目录重建：`docker build -f Dockerfile.vllm -t video-vllm:v0.32.0rc1 .`。
> 回滚方式与升级注意见 §7.1。

### 3.2 权重下载

```bash
# LightX2V Ref2VA 8step（文件名就是契约，不要改名/不要 _comfyui_ 导出）
hf download lightx2v/Minimax-h3-Turbo \
  minimax_h3_ref2v_turbo_8step_v1.0_768p_bf16.safetensors \
  --local-dir /model_nas/models/lightx2v-turbo

# PAI PDD Ref2VA adapter
hf download alibaba-pai/MiniMax-H3-Acc-LoRAs \
  MiniMax-H3-Ref2VA-Acc-8Step.safetensors \
  --local-dir /model_nas/models/h3-acc-loras

# VDN（沿用 ref 的 ModelScope legacy cache 布局）
modelscope download --model OpenVDN/vdn-minimax-h3 \
  --local_dir /model_nas/modelscope_cache/models/OpenVDN/vdn-minimax-h3

# FastH3 V2（gated，需要可访问 MiniMaxAI/MiniMax-H3 的 token）
HF_HOME=/model_nas/hf-cache HF_TOKEN=... \
  hf download FastVideo/FastVideo-FastH3-8-Step-V2
```

FastH3 V2 首次启动还会按 `provenance.json` 里 pin 的 base revision，从
`MiniMaxAI/MiniMax-H3` 拉取 video/audio VAE；离线部署请先用同一 `HF_HOME` 预热。
VDN 首次启动会从 ModelScope/HF cache 硬链接 Qwen3-VL 与 VAE。

### 3.3 磁盘

- VDN 首次 fuse 写 ~62 GB；`/model_nas` 至少留 90 GB 空闲。
- PDD prepare 输出 ~62 GB；`/model_nas/models/h3-ref2va-pdd` 预留 ≥70 GB。
- FastH3 V2 的 HF cache 建议预留 ≥150 GB（V2 权重 + base VAEs + 10 GB VAE 重序列化）。

### 3.4 基础模型

- PDD 的 prepare 直接读 `/model_nas/models/MiniMax-H3/Ref2VA/transformer`。
- PDD serve 与 VDN 沿用 ModelScope legacy cache，要的是
  `<MODELSCOPE_CACHE>/models/MiniMaxAI/MiniMax-H3`。注意它是 **bind mount 出来的**，
  不是 cache 里真有这份文件（参考根目录 `docker-compose.yml` 的写法），
  PDD compose 已按同样方式挂。A100 机器上先确认：

  ```bash
  ls -d /model_nas/models/MiniMax-H3/Ref2VA/transformer \
        /model_nas/models/MiniMax-H3/transformer_ref \
        /model_nas/modelscope_cache/models/MiniMaxAI/MiniMax-H3
  ```

  前两条是 PDD prepare / vLLM Ref2VA 的输入，第三条是 legacy cache 目标目录
  （不存在就让 compose 的 bind mount 建它，父目录必须可写）。
- 若改用 HF：去掉 `SGLANG_USE_MODELSCOPE` / `HF_HUB_OFFLINE`，并设置 `HF_TOKEN`。

---

## 4. 启动与验证

### 4.1 FastH3-8-Step-V2（SGLang）

```bash
cd deploy/fasth3-8step-v2
docker compose up -d
docker compose logs -f fasth3-8step-v2
curl -s localhost:30012/health
```

首次启动会下载 gated 权重并重序列化 ~10 GB VAE，耗时较长。A100 上日志应显示
稠密 FA（不会出现 VSA 内核）；如果看到 `FASTVIDEO_VSA` 相关报错，说明镜像/版本
不对，不要继续。

### 4.2 LightX2V Ref2VA（vLLM-Omni）

```bash
cd deploy/lightx2v-turbo-ref2va
docker compose up -d
docker compose logs -f minimax-h3-turbo-ref2va
curl -s localhost:8002/health
```

复用 0.31.0rc1 镜像，首次启动就是从零加载 ~62GB 主干 + LoRA，`start_period`
（已设为 1800s）内看不到 `/health` 属正常。上线先做一次 Ref2VA 8 步冒烟并记录峰值；
DLO resident=24 是保守值，有余量再 28 → 32。

### 4.3 VDN-H3（SGLang）

```bash
cd deploy/vdn-h3
docker compose up -d
docker compose logs -f minimax-h3-vdn
curl -s localhost:30013/health
```

首次启动会预融合 linear branch + 两个 LoRA（~62 GB 写入），并硬链接 base 组件。
确认缓存与模型在同一个文件系统（compose 整盘挂 `/model_nas`）。
`--quantization bf16` 已显式关掉 MXFP8；SM80 走 bf16 DiT。

### 4.4 PAI PDD Ref2VA（SGLang）

```bash
cd deploy/pai-acc-loras-ref2va
docker compose up pdd-prepare      # 可选：先单独看合并/融合日志
docker compose up -d               # serve 会等 pdd-prepare 成功
docker compose logs -f pdd-prepare minimax-h3-pdd
curl -s localhost:30011/health
```

prepare 成功后写 `/pdd/.done`；后续启动会跳过。`pdd_config.json` 必须和
`pdd_fused_heads.safetensors` 同目录，**不能**放进 `/pdd/transformer/`。
prepare 结束先把步数读出来再写请求：

```bash
jq '{num_inference_steps, video_shift, audio_shift}' \
  /model_nas/models/h3-ref2va-pdd/pdd_config.json
```
如果 prepare 失败后要重跑，先确认 `/pdd` 里没有半成品（必要时清空输出目录再重跑）。

---

## 5. 请求契约

> `num_inference_steps` 在两个框架、以及 SGLang 两个大版本之间的口径都不同，
> **不要跨服务复制请求体**：
>
> | 服务 | 引擎 / 版本 | 计数口径 | 取值 |
> |---|---|---|---|
> | FastH3 V2、VDN、PDD | SGLang v0.5.22 | 前向次数（N 次前向 = N+1 个 sigma 点） | 8 |
> | VDN / PDD（同一批权重跑 v0.5.21） | SGLang v0.5.21 | sigma 点个数 | 9 |
> | FastH3 4-step preview（v0.5.21） | SGLang v0.5.21 | sigma 点个数 | 5 |
> | LightX2V Turbo | vLLM-Omni | sigma 点个数（4 步 artifact 用 5） | 9 |
>
> PDD 还有一层：`pdd_config.json` 由 fuse 工具生成，服务端按它校验 sigma 网格
> （`_pdd_config["num_inference_steps"]` 必须与融合头行数自洽）。以
> `jq .num_inference_steps <PDD_DIR>/pdd_config.json` 的实际值为准，别照抄本文。

### 5.1 FastH3 V2（SGLang 异步 `/v1/videos`）

```bash
curl -sS -X POST http://127.0.0.1:30012/v1/videos \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "FastVideo/FastVideo-FastH3-8-Step-V2",
    "prompt": "A red fox runs through fresh snow at dawn.",
    "task": "t2va",
    "conditions": [],
    "num_inference_steps": 8,
    "flow_shift": 10.0,
    "audio_flow_shift": 3.0,
    "seed": 1101,
    "num_outputs_per_prompt": 1,
    "target": {"short_edge": 768, "aspect_ratio": "16:9", "duration_seconds": 5.0}
  }'
# 轮询 GET /v1/videos/{id}，完成后 GET /v1/videos/{id}/content
```

- 仅 T2VA；`fl2va` / `ref2va` 会被拒绝。
- `guidance` 由 checkpoint 固定为 1，请求不必带；步数/shift 不符会被拒绝。
- A100 用稠密 FA，质量接近，但拿不到 VSA 的加速；长片/复杂运动质量仍低于 base H3。

### 5.2 LightX2V Ref2VA（vLLM `/v1/videos/sync`）

```bash
curl -sS -X POST http://127.0.0.1:8002/v1/videos/sync \
  -F 'prompt=A white cat sits on a beige couch.' \
  -F 'aspect_ratio=adaptive' -F 'short_edge=768' \
  -F 'fps=24' -F 'seed=3100' \
  -F 'num_inference_steps=9' \
  -F 'flow_shift=6' \
  -F 'extra_params={"task":"ref2va","duration":5,"audio_flow_shift":3.0}' \
  -F 'lora={"name":"h3-turbo-ref2v-8step","path":"/models/turbo/minimax_h3_ref2v_turbo_8step_v1.0_768p_bf16.safetensors","scale":1.0}' \
  -F 'input_reference=@/path/to/ref.png;type=image/png' \
  -o turbo_ref2va.mp4
```

- `lora.path` 必须是**服务端**看到的路径（`/models/turbo/...`），不是宿主机路径。
- 文件名/步数/shift 不匹配会被拒绝；`_comfyui_` 导出会被按名字拒绝。
- 0.31 与 0.32 的 artifact 表、LoRA 契约一致：`_TURBO_NAME_RE` 解析 task/steps、
  768p 的 `flow_shift=6`、alpha 从 metadata 读，两版都有。本轮已随 base 统一升到
  v0.32.0rc1（收益是去掉 LoRA rebind），回滚见 §7.1。

### 5.3 VDN-H3（SGLang，v0.5.22）

```bash
curl -sS -X POST http://127.0.0.1:30013/v1/videos \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "OpenVDN/vdn-minimax-h3",
    "prompt": "A curious raccoon peers through sunflowers.",
    "task": "t2va",
    "conditions": [],
    "num_inference_steps": 8,
    "seed": 1000,
    "num_outputs_per_prompt": 1,
    "target": {"short_edge": 768, "aspect_ratio": "16:9", "duration_seconds": 5.0}
  }'
```

- 只服务 `t2va` / `fl2va`；`ref2va` 会被拒绝。
- v0.5.22 的采样器硬性要求 `num_inference_steps=8`（v0.5.21 曾要求 9）。
- 2 卡默认 TP2；若该 tag 在 TP 下报错，可改 `--ulysses-degree 2` 并降 resident。

### 5.4 PAI PDD Ref2VA（SGLang，v0.5.22）

```bash
curl -sS -X POST http://127.0.0.1:30011/v1/videos \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "MiniMaxAI/MiniMax-H3",
    "prompt": "A man stands beside a yellow car at night.",
    "task": "ref2va",
    "quality": "lossless",
    "num_inference_steps": 8,
    "flow_shift": 12.0,
    "audio_flow_shift": 3.0,
    "seed": 3100,
    "num_outputs_per_prompt": 1,
    "conditions": [
      {"type": "image", "uri": "file:///data/minimax-h3/ref.png", "role": "reference"}
    ],
    "target": {"short_edge": 768, "aspect_ratio": "auto", "duration_seconds": 5.0}
  }'
```

- 必须 `task=ref2va`、`steps=8`、`flow_shift=12.0`、`audio_flow_shift=3.0`、
  `quality="lossless"`；与融合头不一致会被拒绝。
  注意 v0.5.21 上同一套 PDD 权重要求 9（那时按 sigma 点计数），v0.5.22 起
  改成按前向次数计；升级/回退镜像时先看 `pdd_config.json`。
- `conditions[].uri` 用服务端可读的 `file://` 绝对路径（挂载 `/data/minimax-h3`）。
- PDD 是 8 步蒸馏；音频质量在 8 步档仍可能弱于 50 步 base。

---

## 6. 验证与调参

### 6.1 基本检查

```bash
docker compose ps
curl -s localhost:<port>/health
docker compose logs --tail=200 <service>
```

### 6.2 峰值显存

```bash
nvidia-smi --query-gpu=index,memory.used,memory.total --format=csv -l 1
```

建议在**首次真实请求**期间观察；目标真实峰值 <38 GB，留 2 GB 余量。

| 服务 | 当前 resident | 调整建议 |
|---|---|---|
| FastH3 V2 | `--dit-layerwise-resident-layers 24` | <36G 可 32 → 40；OOM 回退 16 |
| VDN | 24 | 同上；若改用 Ulysses2（不切权重）先降到 16 |
| PDD | 24 | 同上；PDD 头常驻，先保守 |
| LightX2V | `--dlo-resident-layers 24` | 带 LoRA 常驻缓冲；有余量 28 → 32 |

### 6.3 观察点

- **FastH3 V2**：日志不应出现 VSA 内核加载；应为稠密 FA。若报
  `FASTVIDEO_VSA`/`fastvideo_kernel`，说明误用了 vLLM 路径或镜像版本不对。
- **VDN**：首次启动应看到 overlay/fuse 与 linear branch 加载；不要用稠密后端，
  否则会跳过 linear branch（配置已强制 `hybrid_window_attn_h3`）。
- **PDD**：serve 启动应读取 `pdd_config.json`；文件缺失、位置错误（放进
  `transformer/`）或请求步数与之一致性不符都会被拒绝。
- **LightX2V**：请求里的 `lora.path` 与启动时 `--lora-path` 必须指向同一文件。

---

## 7. 已知风险 / 回滚

1. **vLLM 已统一升到 v0.32.0rc1**：0.31/0.32 的 H3 LoRA 契约一致
   （`_TURBO_NAME_RE` 含 `fl2v|ref2v`、768p 的 `flow_shift=6`、alpha 从 metadata 读、
   请求级 `lora` 字段、`--lora-backend peft`、`--dlo-resident-layers`），
   0.32 额外去掉 LoRA rebind（vLLM-Omni #7195）。升级后先跑一次 Ref2VA 8 步冒烟，
   对比峰值/出片；异常时把 compose 的 `image` 换回 `video-vllm:v0.31.0rc1`
   回滚（旧镜像保留，不要用新版覆盖旧 tag）。
2. **FastH3 V2 在 A100 没有 VSA**：只能稠密 FA；质量接近，但吞吐拿不到 VSA 收益。
   若后续换 H100/B200，可改 vLLM-Omni + `FASTVIDEO_VSA` 或 SGLang
   `transformer=video_sparse_attn_h3`。
3. **VDN 首次启动写 62 GB**：`/model_nas` 需 ≥90 GB 空闲，且缓存与模型同文件系统；
   compose 已整盘挂载 `/model_nas` 以避免跨 mount 硬链接失败。
4. **PDD prepare 写 62 GB**：只跑一次；`.done` 是完成标记。`pdd_config.json`
   必须与 fused heads 同目录，不能进 `transformer/`。
5. **SGLang diffusion 的调度器超时**：`--watchdog-timeout` 是 srt/LLM 参数，
   diffusion 路径不读它（no-op）；v0.5.21/v0.5.22 都仍接受它
   （`srt/arg_groups/fields/device.py:66`、`arg_groups/field_order.py:110`），
   所以加不加都不影响扩散，根 base 命令里已移除。v0.5.21 起扩散侧改用
   `--scheduler-rpc-timeout <秒>`，默认 `None` = 不设 transport 层超时（上限
   2147483s），所以不用再像旧镜像那样打 `SGLANG_DIFFUSION_SCHED_RCVTIMEO_MS` patch。
   四处 compose（base + 三套 SGLang）**都已显式设为 10800（3h）**：保留旧 handoff
   的意图，同时避免异常时无限挂住（超时后 job 标 failed，不会卡死 GPU）。
   该 flag 在 v0.5.21 镜像内已验证，v0.5.22 源码
   （`multimodal_gen/runtime/server_args/server_args.py:2517`）里同样存在，
   不会出现 `unrecognized arguments`。
6. **FastH3 V2 与 base VAEs 都是 gated**：需要 `HF_TOKEN` 且有
   `MiniMaxAI/MiniMax-H3` 访问权；离线部署先预热 HF cache。
7. **GPU/端口冲突**：每套 compose 默认 4 实例、占满 8 卡（0,1 / 2,3 / 4,5 / 6,7），
   容器内端口固定（SGLang 30010、vLLM 8000），宿主端口按套分区：
   base SGLang 30010-30013、PDD 30020-30023、FastH3 30030-30033、
   VDN 30040-30043、base vLLM 8000-8003、LightX2V 8010-8013。
   一套就占满 8 卡，套与套之间不能同时起；要混跑只能手改 `device_ids` 与宿主端口。
8. **TP2 只在 base H3 上实测过**：FastH3 V2 / VDN 的官方示例都是纯 Ulysses，
   LightX2V 的官方示例是 8 卡纯 Ulysses；三者都没有公开的 TP2 实测。
   退路已写进各 compose 注释：SGLang 改 `--ulysses-degree 2`（不切权重，
   resident 降到 16）；vLLM 改 `--tensor-parallel-size 1 --usp 2
   --text-encoder-tp-size 1`（vae 并行度保持 2）。
9. **warmup 帧数**：三套 SGLang 都用 `--warmup-num-frames 124`（≈5s），
   而本项目实际生成 15s 片（345～362 帧）。warmup 参数确实生效：v0.5.22 里
   `--enable-torch-compile false` + 显式 warmup 形状时 `_adjust_warmup` 会把
   `--warmup-mode` 落到 `request`（`sglang serve` help 写默认 `server`）；
   首条长请求会额外付 allocator 增长与 kernel setup，若首次 15s 请求就压到
   显存上限，把 warmup 改成 345 再重启。
10. **首启健康检查**：四套变体的 `start_period` 都是 1800s（VDN 首启 fuse
    ~62GB、PDD serve 要加载 ~62GB 合并权重、LightX2V 要从 /model_nas 读 ~62GB +
    LoRA 建 DLO）。base 服务保持 600s（已在目标机跑通过）。`start_period`
    只影响 `up --wait`/监控判定，不会因 unhealthy 自动重启容器。

---

## 8. 待办（A100 机器上）

- [ ] 确认 `lmsysorg/sglang:v0.5.22` 与 `vllm/vllm-omni:v0.32.0rc1` 可 pull。
- [ ] 构建 `video-sglang:v0.5.22` 一个镜像，记录 digest。
- [ ] 构建 `video-vllm:v0.32.0rc1`（`docker build -f Dockerfile.vllm -t video-vllm:v0.32.0rc1 .`），记录 digest。
- [ ] 下载四套权重（LightX2V、PDD、VDN、FastH3 V2）。
- [ ] 逐套启动：FastH3 V2 → VDN → PDD → LightX2V，记录首次启动耗时。
- [ ] 每套发一次固定种子请求，记录 nvidia-smi 峰值与 E2E。
- [ ] 按峰值调 resident/DLO 层数，锁定最终值。
- [ ] （可选）需要 0.32 的 rebind 优化时，再单独建 tag 跑同请求对比，否则不升。
- [ ] 若需要 FL2VA 版 PDD：换 adapter/`--model-variant fl2va`/base transformer，另起一套。
- [ ] 验证通过后把镜像 tag 改成 digest，避免 rc tag 被重推。

---

## 9. 参考

- SGLang Cookbook（2026-10-15）：
  `docs/MiniMax-H3_docs/MiniMax-H3-SGLang-Cookbook.2026-10-15.md`
- vLLM Recipes：
  `docs/MiniMax-H3_docs/MiniMax-H3-vLLM-Recipes.2026-10-15.md`
  （更完整的 FastH3 V2 / LightX2V 细节见调研稿
  `/mnt/d/Qoder-Work/MiniMax-H3/MiniMax-H3-加速方案调研报告.md` §9/§10）
- 现有超时 handoff：`docs/HANDOFF-generation-timeout-3h.md`
- 上游：
  - https://huggingface.co/FastVideo/FastVideo-FastH3-8-Step-V2
  - https://huggingface.co/lightx2v/Minimax-h3-Turbo
  - https://huggingface.co/OpenVDN/vdn-minimax-h3
  - https://huggingface.co/alibaba-pai/MiniMax-H3-Acc-LoRAs
