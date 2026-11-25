# 模型落位（五个模型 + 运行时目录）

> 配套：`deploy/` 四套 compose、`docs/HANDOFF-4-variants.md`
> 目标机：4×A100-40G；模型/缓存根 `/model_nas`，素材根 `/data/minimax-h3`
> 原则：宿主机路径必须和 compose 的 volume 源一致；换盘要同步改 compose。

---

## 1. 落位总表

| 模型 | 宿主机路径 | 容器内路径 | 读写 | 谁在用 |
|---|---|---|---|---|
| MiniMaxAI/MiniMax-H3（base，通常已有） | `/model_nas/models/MiniMax-H3` | LightX2V / PDD prepare：`/models/MiniMax-H3`；PDD serve：`/root/.cache/modelscope/models/MiniMaxAI/MiniMax-H3`；VDN：同名路径（在 `/model_nas` 内） | 模型 ro；两条 legacy cache 挂载给 rw（sglang 首次解析会写元数据） | LightX2V 的 DiT、PDD prepare 的 `Ref2VA/transformer`、PDD serve 与 VDN 的 base 组件 |
| FastVideo/FastVideo-FastH3-8-Step-V2 | `/model_nas/hf-cache`（HF cache 布局，**gated**） | `/hf-cache` | rw | FastH3 V2 服务 |
| lightx2v/Minimax-h3-Turbo | `/model_nas/models/lightx2v-turbo/` | `/models/turbo` | ro | LightX2V 服务（Ref2VA 8step） |
| OpenVDN/vdn-minimax-h3 | `/model_nas/modelscope_cache/models/OpenVDN/vdn-minimax-h3/` | 同路径（整盘挂 `/model_nas`） | rw | VDN 服务 |
| alibaba-pai/MiniMax-H3-Acc-LoRAs | `/model_nas/models/h3-acc-loras/` | `/models/h3-acc-loras` | ro | PDD prepare（Ref2VA 8step） |

例外：**FastH3 V2 不吃 `/model_nas/models/MiniMax-H3`**，它按 `provenance.json`
里 pin 的 revision 从 HF 拉 base 的 video/audio VAE（t2va 走 FL2VA 分区；
vLLM 源码的 allow_patterns 是 `FL2VA/video_vae/**`、`FL2VA/audio_vae/**`，
SGLang overlay 以 pin 的 revision 为准）到同一个 `HF_HOME=/model_nas/hf-cache`。

### 运行时写出的目录（不是下载）

| 目录 | 用途 | 容量/约束 |
|---|---|---|
| `/model_nas/sglang-cache/vdn` | VDN 首启 fuse linear branch + LoRA | ~62GB；`/model_nas` 需 ≥90GB 空闲，且与 ModelScope cache 同一文件系统 |
| `/model_nas/models/h3-ref2va-pdd` | PDD prepare 输出：`transformer/`、`pdd_fused_heads.safetensors`、`pdd_config.json`、`.done` | ~62GB |
| `/model_nas/hf-cache/sglang` | FastH3 V2 overlay 的 ~10GB VAE 重序列化 | 随 HF cache 计 |

---

## 2. 下载命令

```bash
# 1) base：先确认目标机已有，且 Ref2VA/transformer 有分片和 index
ls -d /model_nas/models/MiniMax-H3/Ref2VA/transformer
ls /model_nas/models/MiniMax-H3/Ref2VA/transformer/model.safetensors.index.json

# 2) FastH3 V2（gated，落到 HF cache）
HF_HOME=/model_nas/hf-cache HF_TOKEN=... \
  hf download FastVideo/FastVideo-FastH3-8-Step-V2

# 2b) 它的 base VAEs（同一个 HF cache；离线部署先预热）
HF_HOME=/model_nas/hf-cache HF_TOKEN=... \
  hf download MiniMaxAI/MiniMax-H3 \
  --include "FL2VA/video_vae/*" "FL2VA/audio_vae/*"

# 3) LightX2V Turbo（文件名不能改；目录里只放这一个文件）
hf download lightx2v/Minimax-h3-Turbo \
  minimax_h3_ref2v_turbo_8step_v1.0_768p_bf16.safetensors \
  --local-dir /model_nas/models/lightx2v-turbo

# 4) VDN（ModelScope legacy cache 布局，和 compose 的解析路径一致）
modelscope download --model OpenVDN/vdn-minimax-h3 \
  --local_dir /model_nas/modelscope_cache/models/OpenVDN/vdn-minimax-h3

# 5) PAI PDD LoRA
hf download alibaba-pai/MiniMax-H3-Acc-LoRAs \
  MiniMax-H3-Ref2VA-Acc-8Step.safetensors \
  --local-dir /model_nas/models/h3-acc-loras
```

> 国内网络：非 gated 的 LightX2V / PAI 走 HF，可加 `HF_ENDPOINT=https://hf-mirror.com`；
> FastH3 V2 是 gated，镜像站一般不带鉴权，走官方 endpoint + `HF_TOKEN`；
> VDN 走 ModelScope，不受 `HF_ENDPOINT` 影响。
>
> VDN 若不走 ModelScope：去掉 `SGLANG_USE_MODELSCOPE` / `HF_HUB_OFFLINE`，
> 把 VDN 与 base 都下到 `/model_nas/hf-cache`，其余 compose 路径不变。

---

## 3. 各目录内必须长什么样（自查）

```
/model_nas/models/MiniMax-H3/
  Ref2VA/transformer/{config.json, model.safetensors.index.json, model-*.safetensors}

/model_nas/models/lightx2v-turbo/
  minimax_h3_ref2v_turbo_8step_v1.0_768p_bf16.safetensors   # 只此一个

/model_nas/modelscope_cache/models/OpenVDN/vdn-minimax-h3/
  model_spec.json  metadata.json  stage-dmd-step-250/...

/model_nas/models/h3-acc-loras/
  MiniMax-H3-Ref2VA-Acc-8Step.safetensors
```

---

## 4. 权限

- **可写**：`/model_nas/modelscope_cache`、`/model_nas/hf-cache`、
  `/model_nas/sglang-cache`、`/model_nas/models/h3-ref2va-pdd`。
- **只读即可**：三个模型权重目录 + base 目录（不过 PDD serve / VDN 把 base 挂到
  legacy cache 路径时给的是 rw，以便 sglang 首次解析写元数据；模型文件本身仍只读）。
- 容器内是 root；宿主机把模型目录设成 `a+rX`，缓存目录保证可写即可。

---

## 5. 常见坑

1. **FastH3 V2 的 base VAE 来源**不是 `/model_nas/models/MiniMax-H3`，而是
   按 pinned revision 从 HF cache 拉；只给本地 base 目录不够。
2. **VDN 需要 base 的 Qwen3-VL/VAE，而那个目录可能是空的**：根 base compose 的嵌套挂载
   会在宿主机 `/model_nas/modelscope_cache/models/MiniMaxAI/MiniMax-H3` 留下一个
   **root 所有的空目录**（实测：嵌套 bind 的 mountpoint 由 docker 在父挂载里 mkdir
   出来），空目录会被当成「模型存在」而回退联网下载。所以 VDN compose 已把
   `/model_nas/models/MiniMax-H3` 显式挂到该路径；改路径时 `vdn-h3` 与
   `pai-acc-loras-ref2va` 两个 compose 要同步。
   另外，嵌套 bind 是独立 mount，overlay 的 hardlink 会 EXDEV 并回退 symlink
   （<64MB 文件直接 copy），大权重不会被复制；只要该挂载在，symlink 就能解析。
3. **LightX2V 文件名就是契约**：不要改名、不要用 `_comfyui_` 导出、
   目录里只放一个被识别的 artifact。
4. **PDD prepare 需要完整分片**：`Ref2VA/transformer` 只有 `config.json` +
   index 会失败；必须是完整模型目录。
5. **换盘/换目录**：下载路径可以改，但必须同步改 compose 的 volume 源；
   VDN 是整盘挂 `/model_nas`，换根要连 `MODELSCOPE_CACHE`、`HF_HOME`、
   `SGLANG_DIFFUSION_CACHE_ROOT` 一起改。
6. `/data/minimax-h3` 不是模型，是参考图/音频的挂载点，按需放素材。

---

## 6. 一句话自查

```bash
ls -d /model_nas/models/MiniMax-H3/Ref2VA/transformer \
      /model_nas/models/lightx2v-turbo \
      /model_nas/modelscope_cache/models/OpenVDN/vdn-minimax-h3 \
      /model_nas/models/h3-acc-loras \
      /model_nas/hf-cache
```

---

## 7. 新增：Pika-H3-Flex 与 FastH3-Omni-8-Step-V1

> 这两个模型**现有镜像都不支持**（`sglang-video:v0.5.22` 只注册了
> FastH3-V2/base/VDN；`video-vllm:v0.32.0rc1` 只有 FastH3-V2）。需要新镜像。

### 7.1 引擎 / 版本 / 镜像

| 服务目录 | 模型 | 引擎 | 镜像 tag | FROM | 说明 |
|---|---|---|---|---|---|
| `deploy/pika-h3-flex` | Pika-Labs/Pika-H3-Flex | SGLang | `sglang-video:dev` | `lmsysorg/sglang:dev` | vLLM 全树 0 命中 Pika，只能 SGLang；Pika 支持（#47378，10-31）晚于 v0.5.23 切点，**任何已发布 tag 都没有**，只能 dev/nightly，等 v0.5.24 再定版 |
| `deploy/fasth3-omni-8step-v1-sglang` | FastVideo/FastVideo-FastH3-Omni-8-Step-V1 | SGLang | `sglang-video:v0.5.23` | `lmsysorg/sglang:v0.5.23` | Omni 支持（#45530，10-22）已进 v0.5.23；A100 走稠密 `transformer=fa`（报告推荐的 A100 路径） |
| `deploy/fasth3-omni-8step-v1-vllm` | 同上 | vLLM-Omni | `video-vllm:v0.34.0` | `vllm/vllm-omni:v0.34.0` | 与 base H3 共用根目录 `Dockerfile.vllm` 的统一镜像；已装 `fastvideo-kernel==0.3.4`（`.[vsa]`）；A100 走 **triton** VSA + BF16 |

SGLang Dockerfile 在 `deploy/images/`：`Dockerfile.sglang-dev`、`Dockerfile.sglang-v0.5.23`；
vLLM 统一镜像用根目录 `Dockerfile.vllm`。构建例：
```bash
docker build -f deploy/images/Dockerfile.sglang-v0.5.23  -t sglang-video:v0.5.23  deploy/images
docker build -f deploy/images/Dockerfile.sglang-dev      -t sglang-video:dev deploy/images
docker build -f Dockerfile.vllm                          -t video-vllm:v0.34.0    .
```

### 7.2 落位（全部走 HF cache，与 FastH3-V2 同套路）

| 模型 | 宿主机路径 | 容器内 | 读写 |
|---|---|---|---|
| Pika-Labs/Pika-H3-Flex | `/model_nas/hf-cache`（HF cache 布局） | `/hf-cache` | rw |
| FastVideo/FastVideo-FastH3-Omni-8-Step-V1 | `/model_nas/hf-cache` | `/hf-cache` | rw |
| base 组件（两者的 overlay 都链接 pinned `MiniMaxAI/MiniMax-H3`，**gated**） | `/model_nas/hf-cache` | `/hf-cache` | rw |

运行时 overlay 产物目录（各服务独立子目录，避免互相踩）：
- Pika：`/hf-cache/sglang-pika`（→ 宿主 `/model_nas/hf-cache/sglang-pika`）
- Omni-SGLang：`/hf-cache/sglang-omni`
- Omni-vLLM：直接用 `/hf-cache`（vLLM 自管）

### 7.3 下载（HF；base 为 gated，需 `HF_TOKEN` 且已接受 MiniMax-H3 条款）

```bash
# 两个新模型各自权重
HF_HOME=/model_nas/hf-cache HF_TOKEN=... hf download Pika-Labs/Pika-H3-Flex
HF_HOME=/model_nas/hf-cache HF_TOKEN=... hf download FastVideo/FastVideo-FastH3-Omni-8-Step-V1

# 两者都要链接的 base（Pika 是 base+LoRA，Omni 链接 pinned Ref2VA 的 TE/VAE）
HF_HOME=/model_nas/hf-cache HF_TOKEN=... hf download MiniMaxAI/MiniMax-H3
```
> Pika overlay 只下 ~5.5GB 适配器并校验 sha256，其余链接 base；base 已在本地
> `/model_nas/models/MiniMax-H3` 时，仍需让 HF resolver 在 `/model_nas/hf-cache` 找到它
> （离线就预热同一 HF_HOME）。

### 7.4 端口段（接 §1 之后，互不撞车）

| 服务 | 宿主端口（4 实例） | 容器内 |
|---|---|---|
| Pika-H3-Flex | 30050-30053 | 30010 |
| FastH3-Omni（SGLang） | 30060-30063 | 30010 |
| FastH3-Omni（vLLM） | 8020-8023 | 8000 |

### 7.5 契约与 A100 注意

- **Pika**：`--model-variant ref2va`；请求 `num_inference_steps=6`（只接受 6）、
  shift 保持 12/3、`quality` 用默认 lossless（**禁 high**）；适配器 `--lora-merge-mode dynamic`
  **不合并**（BF16 merge 削掉约 1/3 更新量）；`--lora-path` 不能替换自带适配器。
- **FastH3-Omni（SGLang）**：**仅 ref2va**、8 步、默认 shift 12/3、clean references；
  拒绝 `--model-variant`；A100 显式 `--component-attention-backends transformer=fa`
  （无 VSA-H3 内核，比 SM90 的 VSA 慢约 25%）；overlay 自动融合 32→8 头，无需手工 fuse。
- **FastH3-Omni（vLLM）**：`--task-type ref2va`、8 步、guidance 1；VSA provider 必须
  **triton**（SM80+；cudnn 仅 SM90+）；**BF16 不加 fp8**（A100 无原生 FP8）。
  ⚠️ 官方只基准过 1 卡 DLO 与 8 卡 USP+HSDP；本仓库的 **2 卡 USP2+DLO** 契约合法但
  **未在 A100 实测**，报错/显存尖峰就退化为每 GPU 单卡实例（`--num-gpus 1 --usp 1`+DLO，8 实例）。
- 三者首启都拉 gated 权重，4 实例共用 HF/overlay cache → **先单起实例 0 预热，再 up -d 拉其余**。