# MiniMax-H3 加速方案调研报告

> 目标：在 **2×A100-40GB** 或 **4×A100-40GB** 的 Linux 服务器上部署 MiniMax-H3，**必须支持 Ref2VA**，并尽可能提高推理速度。
> **版本记录：v1 2026-10-08 初版（§1–§9）；v2 2026-11-06 增量更新（新增 §10 少步横评、§11 与第三份调研的交叉核对、§12 一个月增量；并原地修订 §2/§3.3/§5/§6/§9/§10 中已过时的结论，改动处均标注〔2026-11-06〕）。**
> 资料源：MiniMax 官方 GitHub/HF 卡片、SGLang Diffusion cookbook 与量化/注意力后端文档、vLLM-Omni 官方 recipe 与生产级 serving 博客、HuggingFace（经 hf-mirror，本机 huggingface.co 直连不通）仓库元数据与文件清单、两框架 Issue/PR 跟踪、NVlabs/Sana 仓库与模型卡原文。
> 表中"开源日期"= 该仓库在 HuggingFace 的 `createdAt`（ModelScope/GitHub 单独标注）；文件体积一律用 **GiB**（1 GiB = 1024³ B，很多网页写的 "GB" 是十进制，同一文件会差 7%）。

---

## 0. 结论先说

**1）H3 在 40GB 卡上的瓶颈不是速度，是"装不下"。**
一个分区的权重约 **108 GiB**：DiT 61.73 GiB（33B，BF16/FP32 混精度）+ Qwen3-VL-32B 文本编码器 46.18~47.97 GiB + 视频 VAE 4.85 GiB + 音频 VAE 0.56 GiB。官方 4×H100-80GB 的**无损驻留**实测峰值是 **49.80 / 57.01 / 66.04 GiB per GPU**（分别对应 TP4+Ulysses1 / FSDP+Ulysses4 / TP2+Ulysses2）——**全部超过 40GB**。所以 2×/4×A100-40G 上，"原精度 + 全驻留"这条路不存在，必须做下面三件事中的至少两件：权重瘦身（剪枝/量化）、显存换主存（layerwise offload / DLO）、步数削减（蒸馏 LoRA）。

**2）A100 是 Ampere（SM80），这决定了可用方案的边界。**
不可用：NVFP4 / MXFP8 / MXFP4 / FP8 张量核心（A100 无 FP8 单元）、`TRTLLM_ATTN`、`subblock_sparse_attn`、`video_sparse_attn_h3`(VSA)、SGLang 的 `quality="high"` 预设（被硬锁在 4×H200）。
可用：INT8 ConvRot（`comfy-kitchen`，官方写 "Turing+"）、**W4A8 ConvRot（文档明确 "Requires SM80+"）**、W4A4 ConvRot（SM75+）、GGUF K-quant、Quanto qint8（只省显存不提速）、W4A16 GPTQ/Marlin、`fa`/`sage_attn`/SpargeAttn、Ulysses/TP/FSDP/layerwise offload、以及**AdaLN 在线重建（无损省 24.2 GiB）**。

**3）推荐主方案（Ref2VA + 速度优先，SGLang 路线）：** 〔2026-11-06 修订：把"8 步 PDD 手工融合"换成 **Pika H3 Flex 的 ref2va 适配器（6 步，SGLang 一等支持，零预处理）** 作首选，FastH3-Omni-8-Step-V1 为次选；下方代码块作为"可选手工路线"保留。高分辨率改用 **Open-H3-Regenerate-2K**（3 步，见 §12.3）。详见 §10.2 与 §12.7。〕

```
Ref2VA 分区 + pruned W4A8-ConvRot DiT (11.68 GiB)
        + Qwen3-VL W4A8-ConvRot 编码器 (14.62 GiB)
        + 8 步 PDD 蒸馏（alibaba-pai 官方 Ref2VA 版）
        + TP2 × Ulysses2（4 卡）或 TP2（2 卡）+ text_encoder layerwise offload
```
权重合计 **26.3 GiB**，TP2 后每卡约 13 GiB，剩 25+ GiB 给激活 → 1344×768 有戏；8 步相对 50 步约 **5~6×** 提速。
如果不想折腾离线权重融合，用**一体化文件**更省事：`PulpCut/MiniMax-H3-Ref2VA-Turbo-INT8-ConvRot`（Ref2VA + 4 步 Turbo + INT8，19.53 GiB 单文件）或 `MATLOWAI/minimax-h3-fused-turbo-int8-convrot`（800K 下载，FL/Ref 融合 + INT8）。

**4）如果更看重画质/可控性，用 vLLM-Omni 路线：**
它把 2×24/32GB 消费卡的 **DLO（分布式 layerwise offload）**配方写得最完整、且**官方支持 Ref2VA 的 Turbo LoRA**（两档：4 步 / 8 步），2×40GB 只是把 `--dlo-resident-layers` 从 12 往上抬。代价：FP8 在线量化在 A100 上只能当"权重存储压缩"用，`CUDNN_ATTN`/`TRTLLM_ATTN` 在文档里对 Ampere 的说法互相矛盾（见 §6）。

**5）你的硬件已确认（2026-10-08）：384 GiB 主机内存 + GPU 间 `NV12`（12×NVLink 绑定 = 600 GB/s 全互联，A100 SXM）。**
→ vLLM-Omni 的 DLO 门槛（≥200 GiB 可用 / 384 GiB 推荐）**满足**；PCIe all-to-all 的顾虑**不成立**，并行策略应往 Ulysses 倾斜。**分阶段叠加的落地顺序、可叠加/互斥矩阵、终态命令见 §9。**
（仍请顺手确认一件事：`topo -m` 矩阵里**两两 GPU 相交的格子**是否都是 `NV12`；若出现 `PHB`/`NODE`/`SYS`，Ulysses 分组要限制在 NVLink 子集内。）

**6）"先上一个方案再叠加"的答案（详见 §9）**：
`FastH3 / VDN-H3 不能当第一步`（两者都拒绝 `ref2va` 请求，只能做旁路 T2VA 服务）。主线顺序是
**① AdaLN 在线（无损，每卡省 24.2 GiB + video_vae=36 让解码 60~209 s→~10 s）→ ② TP2×Ulysses2（NV12 下 4 卡相对 2 卡 ≈1.6×）→ ③ 量化（pruned INT8 19.53 GiB 或 W4A8 11.68 GiB + W4A8 编码器，锚点 1.34~1.40×）→ ④ 8 步 PDD（Ref2VA 版，最大杠杆）→ ⑤ 需要再快才动 sol_attn/sage_attn（锚点 1.81~2.48×）或 latent 超分**。
其中 **①与③互斥**（无损在线重建要求原生 `adaln_proj`，剪枝/量化后就没有它），**④与 Spectrum/Cache-DiT 互斥或至少无标定**。2×A100 上的实用地板约 15–25 s/条（编码+解码+mux），所以建议终点停在 ③+④（量化 + 8 步），预期 35–70 s 一条 1344×768/5 s 片。

---

## 1. 模型本体：为什么慢、为什么大

| 项 | 数值 / 说明 | 来源 |
|---|---|---|
| 发布 | 2026-07-31 发布，2026-07-28 建 HF 仓库，权重 BF16 开源 | Reuters；HF `createdAt` |
| 架构 | 33B **dense single-stream** Omni-Transformer，其中 **约 13B 在 AdaLN 分支**（可预计算/基近似替代） | 官方 README |
| 文本编码器 | **Qwen3-VL-32B 全权重**，取第 **50** 层 hidden state 喂给 Omni-Transformer | 官方 README |
| VAE | Visual VAE f16t4d24（时间 4×、空间 16×，再 patchify 1×2×2 → 有效 32×）≈4.85 GiB；Audio VAE 32 kHz 立体声 0.56 GiB | 官方 README / Comfy-Org 文件表 |
| 分区 | **两个独立 checkpoint**：`FL2VA`（t2va+fl2va）与 `Ref2VA`（ref2va，含 V2V）；每分区约 **134 GiB**（磁盘 ~135 GiB），两分区 ~270 GiB | vLLM-Omni recipe |
| 采样 | 官方权重是 **CFG-distilled**（无 negative branch）→ **没有 guidance scale**，CFG 并行完全无效（多卡只是重复算） | 官方 README + SGLang/vLLM 文档 |
| 默认超参 | 50 步、`flow_shift=12`、`audio_flow_shift=3`、24 fps、短边 768、时长 4–15 s | 两框架文档一致 |
| 序列长度 | 1344×768 × 124 帧 → **58,758 有效 token**（对齐到 58,816）；362 帧（15 s）≈ 104k token | vLLM 博客 |
| 稀疏注意力 | 训练时用了 native sparse attention，**首期开源只有 dense attention**，稀疏实现"未来更新" | 官方 README |
| 未开源 | `H3-Context-IR`（多模态上下文预处理）与 `H3-Regenerate-2K`（2K 再生成）只有 API | 官方 README |
| 许可 | MiniMax H3 Community License；**本地生成内容的商用需另购商用授权**（Comfy 为独家代理） | 官方 README / Comfy 教程 |

一句话：**单步就是 33B 稠密 Transformer 在 6 万 token 上的全注意力**，所以步数削减（蒸馏）和注意力近似才是提速主力，量化主要解决"装得下"。

---

## 2. A100（SM80 / Ampere）能力矩阵

| 机制 | 具体名字 | A100-40G | 依据（原话摘录） |
|---|---|---|---|
| FlashAttention | SGLang `--attention-backend fa`；vLLM-Omni `FLASH_ATTN` | ✅ | "CUDA requires SM80+ and fp16/bf16" |
| SDPA | `torch_sdpa` | ✅ | "universally available" |
| SageAttention | `sage_attn` | ✅（有质量坑） | "Upstream SageAttention CUDA extensions target SM80/SM86/SM89/SM90/SM120"；Comfy 文档警告 H3 末层 block 的 INT8 attention 会造成结尾 morphing / 字幕乱码 |
| SpargeAttn | `slant_attn`/sparge 系列 | ✅ | "CUDA SM80/86/87/89/90 only" |
| Sol-Attn | `sol_attn` | ✅（走 Triton 路径） | SGLang 侧只写 "BF16, head dim 128"；**上游 NVlabs/Sana@sol-engine 的支持表逐行写明 `| SM80 | A100 | Triton |`**（SM89/90/100/120 才是 CuTe DSL kernel），要求 CUDA ≥ 12.8、Triton ≥ 3.6，forward-only、 contiguous BF16 QKV |
| VDN 混合注意力 | `hybrid_window_attn_h3` | ✅ | "on SM80 / SM86 / SM89 the same FA3 build runs its Sm80 mainloop at FA2-class speed"，且 "Ampere and Ada are enabled but not benchmarked" |
| Cube 稀疏注意力 | `cube_sparse_attn`（FlexAttention，纯 PyTorch） | ⚠️ 大概率可用 | 文档未标 CC，只说 "runs on pure PyTorch plus FlexAttention, so it has no third-party kernel dependency" → FlexAttention 编译出的 Triton 内核在 Ampere 上可用；但文档同时警告 "FlexAttention's routing overhead can outweigh sparse-kernel savings on short sequences"，且**不支持 Ring 并行**。Ref2VA 下独立参考图保持 dense，参考视频与目标视频共用一个全局 TopK 池 |
| SubBlock 稀疏 | `subblock_sparse_attn` | ❌ | "Training-free SubBlock sparsity for MiniMax-H3 on CUDA SM90, SM100, and SM120"，`sage_fp8` 仅 SM90 |
| VSA（FastH3） | `video_sparse_attn_h3` / `FASTVIDEO_VSA` | ❌ | 〔2026-11-06 精确化〕SGLang 现版写清内核谱系："FastVideo's native tcgen05 forward on **SM100 / SM103**, a **Triton tile-64 kernel on SM90**" → **SM80 两种都没有**（旧表述 "SM90/SM100/SM103 + FastVideo 原生 SM100a" 结论一致）。替代路径 `--component-attention-backends transformer=fa`，代价参照 4×H200："dense FA 比 VSA-H3 慢约 25%（12.6 s vs 10.0 s）" |
| TRT-LLM 注意力 | vLLM-Omni `TRTLLM_ATTN`（含 SAGE-FP8、Skip-Softmax） | ❌ | "Scoped to datacenter Blackwell silicon (sm_100/sm_103)"，"not auto-selected on workstation Blackwell" |
| cuDNN 注意力 | vLLM-Omni `CUDNN_ATTN` | ⚠️ 文档自相矛盾 | 后端文档写"Restricted to Blackwell + cuDNN 9.5+"，但官方 4090 recipe 就是用 `CUDNN_ATTN` 实测通过的 → A100 上先按 `FLASH_ATTN` 起，再试 |
| FP8 在线量化 | SGLang `--quantization fp8` | ❌（不建议） | SGLang 文档：该 recipe "limited to the resident B200 and B300 topologies"；VDN 段写 "SM80 runs the bf16 DiT (62 GB)" |
| FP8（vLLM-Omni 在线） | `--quantization fp8` | ⚠️ 仅省显存 | vLLM-Omni FP8 文档把 Ampere(SM80+) 列为支持，但 "FP8 on Ampere may use a weight-only path where available" → 无算力收益。根因在 `comfy-kitchen` 的硬件门限表：**`TensorCoreFP8Layout` = FP8 E4M3，`HW Requirement: SM ≥ 8.9 (Ada)`**，NVFP4/MXFP8 是 `SM ≥ 10.0` |
| Skip-Softmax（跳过 softmax 稀疏） | vLLM-Omni `skip_softmax` / SGLang "Request-scoped Skip Softmax" | ❌ | SGLang 文档："Current support is FP16/BF16, head dimension 128 or 256, and unmasked self-attention on **Hopper SM90 and Blackwell SM100/SM103/SM107**"，且 "Ring Attention、attention mask、torch.compile、breakable CUDA graph 会**直接拒绝请求**而不是偷偷退回 dense" |
| **INT8 ConvRot（在线）** | `--quantization convrot_int8`（`kitchen_int8` 已废弃为别名） | ✅ | "per layer on the fused JIT-compiled ops (CC 9.0,10.0,12.0,12.1) or on `comfy_kitchen.int8_linear` (**Turing+**)" → 先 `pip install comfy-kitchen`；`comfy-kitchen` 能力矩阵里 `int8_linear`/`convrot_w4a4_linear`/`gemv_awq_w4a16`/`sol_attn`/`int8_attention` **都有 cuda 后端 kernel**（只有 FP8/NVFP4/MXFP8 的 TensorCore layout 被 CC 卡住） |
| INT8 ConvRot（预量化文件） | `comfy-int8-convrot` | ✅ | "requires SM80+"（同段）；注意 "The H3 256-group DiT supports **TP1/2/4, not TP8**" |
| **W4A8 ConvRot** | `comfy-w4a8-convrot` | ✅ | "**Requires SM80+**"，依赖 `comfy-kitchen>=0.2.27`；FL2VA/Ref2VA DiT 与 Qwen3-VL 编码器都有验证过的 tensor contract |
| W4A4 ConvRot | `comfy-w4a4-convrot` | ✅ | "CUDA requires SM75+"，依赖 `comfy-kitchen` |
| GGUF（DiT 与编码器） | `gguf` | ✅ | "CUDA only and auto-detected; supports standard and K-quant GGML types. TP requires aligned GGML blocks; component/layerwise offload supported, **FSDP 与 LoRA 不支持**" |
| Quanto qint8 | `quanto-int8`（权重侧） | ✅（只省显存） | "Each active matrix is dequantized to the compute dtype … reduces stored/resident weight memory rather than promising INT8 GEMM speed" |
| W4A16 AutoRound | `auto-round` W4A16（GPTQ/Marlin） | ⚠️ 需实测 | 文档未标 CC，"reuses the SRT GPTQ/Marlin backend. Use TP/SP rather than FSDP"；Marlin 本身支持 sm80 |
| NVFP4 / MXFP8 / MXFP4 | `comfy-nvfp4` / `mxfp8` / `mxfp4` | ❌ | NVFP4 matmul "on NVIDIA SM100+"；MXFP4 需 ROCm MI350+ |
| SVDQuant NVFP4 W4A4 | vLLM-Omni 离线 loader | ❌ | NVFP4 计算需 Blackwell（博客列为未来工作："native fused NVFP4 kernels"） |
| AdaLN 在线重建（**无损**） | `--minimax-h3-adaln-online true` | ✅ | "the server drops the **24.2 GiB** of `adaln_proj` weights from the GPU … **bit-exact** with the resident-weight path" |
| AdaLN 离线 sidecar | `--minimax-h3-adaln-cache-path` | ✅（仅未量化权重） | "Cache mode supports the matching unquantized checkpoint only"，且只覆盖建缓存时的 step/shift/mode |
| Cache-DiT | SGLang `--enable-cache-dit` / `SGLANG_CACHE_DIT_*` | ✅ 手动；❌ `quality=high` | `quality:"high"` "currently accepts only the exact workload and **4×H200** deployment; other hardware … fail before denoising" |
| Cache-DiT | vLLM-Omni `quality=high` / `--cache-backend cache_dit` | ⚠️ 未见硬件锁 | "high" 装保守 Cache-DiT profile，实测 4×H200 1.35× / SSIM 0.9709，"may vary by hardware" |
| TeaCache | vLLM-Omni `--cache-backend tea_cache` | ✅ 但**仅 FL2VA** | "MiniMax-H3 TeaCache is currently calibrated only for the FL2VA partition … **Ref2VA-only serving rejects TeaCache**" |
| Spectrum 跳步 | `--enable-spectrum` | ✅（有约束） | "On H3 it cannot combine with Cache-DiT / quality=high **or SP > 1**" → 用 TP2+Ulysses1 而非 Ulysses2 |
| torch.compile | `--enable-torch-compile true` | ⚠️ 不划算 | "the current torch.compile path **changes the model's numerical output**"；H200 实测收益低于噪声；layerwise offload 下无效 |
| FSDP | `--use-fsdp-inference true`（只切 DiT） | ✅ | 保留 BF16/FP32 精度策略；4×H100 实测 ~57 GiB/GPU；**注意** 与 ConvRot/GGUF/mixed 格式互斥 |
| CFG 并行 | `--cfg-parallel-size` | ➖ 无意义 | CFG-distilled 单分支，"extra ranks only recompute the same branch" |
| 连续批处理 | vLLM-Omni `--step-execution --max-num-seqs 4` | ❌ 更慢 | 2×H100 实测：request mode 174.8 s → max-num-seqs 4 反而 182.1 s（"a single H3 denoise step is a compute-bound dense GEMM"） |

---

## 3. 加速方案总表（含链接与开源日期）

### 3.1 DiT 权重瘦身：剪枝 + 量化（决定"能不能装下"）

| 仓库 / 文件 | 类型 | 体积(GiB) | FL/Ref | 首发 | A100 | 链接 |
|---|---|---|---|---|---|---|
| MiniMaxAI/MiniMax-H3 | 官方 BF16/FP32 混精度，CFG-distilled | 61.73 | 都有 | 2026-07-28 | ✅ 基线 | https://huggingface.co/MiniMaxAI/MiniMax-H3 |
| Comfy-Org/MiniMax-H3 → `*_pruned_bf16` | **AdaLN 剪枝**（curve basis 代替全宽 AdaLN，61.73→37.46） | 37.46 | 都有 | 2026-07-30 | ✅ | https://huggingface.co/Comfy-Org/MiniMax-H3/tree/main/diffusion_models |
| Comfy-Org → `*_int8_convrot` | INT8 W8A8 ConvRot（未剪枝） | 31.70 | 都有 | 2026-07-30 | ✅ comfy-kitchen | 同上 |
| Comfy-Org → `*_pruned_int8_convrot` | 剪枝+INT8（**官方 12GB 路线用这个**） | 19.53 | 都有 | 2026-07-30 | ✅ | 同上 |
| Comfy-Org → `*_pruned_fp8_scaled` | 剪枝+FP8 | 19.52 | 都有 | 2026-07-30 | ⚠️ 仅省显存 | 同上 |
| Comfy-Org → `*_pruned_w6a8` | 剪枝+W6A8 | 14.89 | 都有 | 2026-07-30 | ⚠️ SGLang 未列该格式 | 同上 |
| multimodalart/MiniMax-H3-Pruned | 剪枝 Diffusers 组件（带 `adaln_basis`/`adaln_mean` 元数据，可继续吃全宽 LoRA） | ≈37.4 | 都有 | 2026-08-09 | ✅ | https://huggingface.co/multimodalart/MiniMax-H3-Pruned |
| **Winnougan/MiniMax-H3-INT4_Convrot_ComfyUI** → `ref2va_pruned-w4a8` | 剪枝+W4A8 ConvRot | **11.68** | 都有 | 2026-08-03 | ✅ 文档明写 SM80+ | https://huggingface.co/Winnougan/MiniMax-H3-INT4_Convrot_ComfyUI |
| Merserk/MiniMax-H3-INT4-ConvRot → `*_pruned_int4_convrot` | 剪枝+W4A4 | 10.56 | 都有 | 2026-08-03 | ✅ SM75+ | https://huggingface.co/Merserk/MiniMax-H3-INT4-ConvRot |
| leejet/MiniMax-H3-GGUF | GGUF 未剪枝 Q4_K_M / 剪枝 Q4_K_M | 17.49 / 10.64 | 都有 | 2026-08-03 | ✅（不能配 LoRA/FSDP） | https://huggingface.co/leejet/MiniMax-H3-GGUF |
| unsloth/MiniMax-H3-GGUF | 剪枝 GGUF：Q2_K→Q8_0（6.26/8.16/10.64/12.97/15.45/19.97）+ UD-Q2/Q3_XL | 6.26–19.97 | 都有 | 2026-08-07 | ✅ | https://huggingface.co/unsloth/MiniMax-H3-GGUF |
| Abiray/MiniMax-H3-GGUF；Abiray/MiniMax-H3-Pruned-GGUF；realrebelai/MiniMax-H3_GGUFs；molbal/MiniMax-H3-GGUF；vantagewithai/MiniMax-H3-comfyUI-GGUF；convertor/minimax-h3-gguf | GGUF 各家（Q3→Q8、含 Q8_CR/U16G 等） | 6–27 |  mostly 都有 | 2026-08-03～08-06 | ✅ | https://huggingface.co/Abiray/MiniMax-H3-GGUF |
| Ar4ikov/MiniMax-H3-transformer-W4A16-RTN | AutoRound W4A16（GPTQ/Marlin） | ≈34.2 | **仅 FL2VA** | 2026-08-03 | ⚠️ 需实测 | https://huggingface.co/Ar4ikov/MiniMax-H3-transformer-W4A16-RTN |
| DeepBeepMeep/MiniMax-H3 | 剪枝 int8 20.62 / rank8 变体 / ONNX / 含 8 步 PDD Comfy LoRA、X2-Detail、SeedVR2、Viggle-Animate | 19.6–61.7 | 都有 | 2026-08-02 | ✅ | https://huggingface.co/DeepBeepMeep/MiniMax-H3 |
| Gluttony10/MiniMax-H3-INT8-CONVROT | INT8 ConvRot（未剪枝 34.0 十进制 GB） | — | 都有 | 2026-08-02 | ✅ | https://huggingface.co/Gluttony10/MiniMax-H3-INT8-CONVROT |
| rzgar/minimax_h3_fl2va_fp8_e4m3fn | FP8 e4m3fn / fp16attn_fp8 | 28.7–47.6 | FL2VA | 2026-08-03 | ⚠️ 仅省显存 | https://huggingface.co/rzgar/minimax_h3_fl2va_fp8_e4m3fn |
| unsloth/MiniMax-H3-FP8 | FP8 / INT8 / int8-convrot + TE int8 | ≈20.3 十进制GB | 都有 | 2026-08-07 | ✅（用它的 int8） | https://huggingface.co/unsloth/MiniMax-H3-FP8 |
| AX1Y2JP/MiniMax-H3-W4A8-ConvRot；koongrizzly/MiniMax_H3_int4_W4A8_ConvRot_Pruned；berryber09/MiniMax-H3-ref2va-fl2va-hybrid-w4a8 | W4A8 家族 | 11–14 | 都有 | 2026-08-04 / 08-09 / 08-16 | ✅ | https://huggingface.co/AX1Y2JP/MiniMax-H3-W4A8-ConvRot |
| DiffSynth-Studio/MiniMax-H3-NF4 | **NF4**：剪枝 10.5 / 全量 17.2 + TE 15.3 + VAE | 10.5–17.2 | 都有 | 2026-08-04 | ⚠️ 生态在 DiffSynth，不在 SGLang/vLLM | https://huggingface.co/DiffSynth-Studio/MiniMax-H3-NF4 |
| Abiray/Minimax-H3-nvfp4-INT4-INT8-Convrot；lilcheaty/MiniMax-H3-NVFP4；coolthor/MiniMax-H3-pruned-NVFP4；rockerBOO/minimax-h3-nvfp4-convrot；MATLOWAI/minimax-h3-nvfp4 | NVFP4 / mixed int4+int8 | 11.7–22.8 | 都有 | 2026-08-03～08-20 | ❌ NVFP4 需 SM100+（mixed 里的 INT8 层可用） | https://huggingface.co/Abiray/Minimax-H3-nvfp4-INT4-INT8-Convrot |
| QuantFunc/Minimax-H3-Quantfunc-4bit | INT4 rank128 4-bit + 蒸馏一体 | 12.4 | FL2VA 4步 / Ref2VA 8步 | 2026-09-28 | ⚠️ 需实测（diffusers 自定义类） | https://huggingface.co/QuantFunc/Minimax-H3-Quantfunc-4bit |
| FX-FeiHou/MiniMax-H3-Remix | LoRA 合并/remix BF16（含 int8_convrot 31.67） | 61.7/31.67 | — | 2026-08-25 | ✅（自定义 sampler 契约不在保证范围） | https://huggingface.co/FX-FeiHou/MiniMax-H3-Remix |
| WarmBloodAban/Minimax-h3_Singularity v1.3 | **FL/Ref 融合微调**：pruned_int8 19.53 / int8 31.67 / pruned_w4a8 10.96，一套权重同时服务 t2va+fl2va+ref2va | 10.96–31.67 | 融合 | 2026-09-05 | ✅（`--model-variant hybrid`） | https://huggingface.co/WarmBloodAban/Minimax-h3_Singularity |
| brurpo/DaSiWa-MiniMax-H3-Hybrid；Winnougan/Cobijada_..._Hybrid_Pruned；sandpies/...hybrid-unpruned-int8；xmarre/...Ref-Delta-Fused-r1024；t8star/...Super-Acceleration-Comfy；hoidhxd/MiniMax-H3-x-Z-Image-hybrid | 社区 FL/Ref hybrid、加速向融合权重 | 10–40 | 融合 | 2026-08-21～09-22 | ⚠️ 逐个实测 | https://huggingface.co/brurpo/DaSiWa-MiniMax-H3-Hybrid |

### 3.2 文本编码器瘦身（H3 上它跟 DiT 一样大，2×40GB 的真正拦路虎）

| 仓库 / 文件 | 格式 | 体积 | 首发 | A100 | 说明 |
|---|---|---|---|---|---|
| Qwen3-VL-32B（H3 版，bf16） | BF16 | 46.18–47.97 GiB | 2026-07-28 | ✅ | "retained 50 layers ≈ 51.5 GB" |
| Comfy-Org → `qwen3vl_32b_minimax_h3_int8_convrot` | INT8 ConvRot | 25.28 | 2026-07-30 | ✅ | TP8 可用（不兼容的行投影靠复制保留） |
| DeepBeepMeep → `..._layer50_quanto_bf16_int8` | Quanto qint8 | 24.89 | 2026-08-02 | ✅ 仅省显存 | 文档明确"不做 INT8 GEMM 提速" |
| **Comfy-Org → `qwen3vl_32b_minimax_h3_nvfp4_awq`** | NVFP4-AWQ | 14.61 | 2026-07-30 | ✅ 作为**存储压缩**（dequant 后 BF16 计算）；❌ 作为 NVFP4 计算 | SGLang 把这两类分开描述，**名字里的 NVFP4 会误导** |
| Winnougan → `qwen3vl_32b_minimax_h3-w4a8_convrot` / `-int4_convrot` | W4A8 / W4A4 | 14.62 / 13.20 | 2026-08-03 | ✅ | 与 W4A8 DiT 同仓库，一套下完 |
| Merserk → `qwen3vl_32b_minimax_h3_int4_convrot` | W4A4 | 13.93 | 2026-08-03 | ✅ | |
| unsloth / leejet / Abiray → `qwen3vl_32b_minimax_h3-Q2_K_M / -Q4_K_M` | GGUF | 12.20 / 16.97（另有 Q2_K 7.91、Q4_K_M 13.58） | 2026-08-03～08-07 | ✅ | "CUDA capacity path with encoder TP/layerwise support; encoder FSDP 不支持" |
| joeygambino/MiniMax-H3-encoder-GGUF；nif0/Qwen3-VL-32B-Instruct-MiniMax-H3-GGUF（imatrix）；pottokao/...-abliterated-GGUF | GGUF/微改 | 8–17 | 2026-08-04～09-05 | ✅ | abliterated = 去审查权重修改，不是新加载器 |
| Qwen/Qwen3-VL-32B-Instruct-FP8 | 序列化 FP8 组件 | ≈半精度体积 | 2025-10-19 | ⚠️ A100 上只能 weight-only 路径 | SGLang: "only eligible language-model linears use FP8" |
| **NicoLab28/ClipProj-MiniMax-H3** | **换成 Qwen3-VL 4B/8B + ClipProj 侧挂** | 投影 0.05–0.56（+4B/8B 本体） | 2026-08-09 | ✅ | 最大幅度的显存解放（47.97→~8-17），**条件是近似替换、会掉一致性**；含 celeb/identity 控制变体 |
| llmfan46/Qwen3-VL-32B-Instruct-ultra-uncensored-heretic；ethanfel/...Heretic-H3-ComfyUI-INT8-ConvRot；sakamakismile/...Heretic-...-NVFP4 | 编码器微调/量化 | — | 2026-04-09 / 08-03 / 08-04 | ✅ INT8；❌ NVFP4 | 换编码器只改 conditioning，不改采样日程 |

### 3.3 少步数蒸馏（提速主力）

| 仓库 / 文件 | 方法 | 步数(NFE) | 任务 | 首发 | A100 | 备注 |
|---|---|---|---|---|---|---|
| **Pika-Labs/Pika-H3-Flex**〔2026-11-06 新增〕 | H3 **后训练** + 固定 6 步（knots `1000/750/500/250/100/40`，shift 12/3，**每步预测 x0 后重新加噪**） | **6** | **FL2VA + Ref2VA 两个适配器都有** | 2026-10-29 | ✅ | **SGLang 一等支持**：`sglang serve --model-path Pika-Labs/Pika-H3-Flex [--model-variant ref2va]`，请求**只接受 6 步**；FP32 LoRA rank/α128（各 2.58 GiB，overlay 只下 ≈5.5 GB 并校验 sha256）；**适配器不许合并**（"a BF16 merge rounds away about a third of its update"）、`--lora-path` 不能替换、**不支持 `quality:"high"`**；"generic six-step Euler is not equivalent"。官方时延（1×H200，5 s）：t2va **37 s** / fl2va 42 s / **ref2va（2 图+1 带音频视频）260 s**。详见 §12.2 |
| **FastVideo/FastVideo-FastH3-Omni-8-Step-V1**〔2026-11-06 新增〕 | **PDD**（Ref2VA 分区学生），8 次去噪 / 32 区间网格，VSA 0.9 稀疏 + 128-token (4,4,8) tile | **8** | **仅 `ref2va`** | 2026-10-05 | ⚠️ | **heads 由 SGLang overlay 自动融合**（省去手工 `fuse_minimax_h3_pdd_heads`）。但 **VSA-H3 内核只覆盖 SM100/SM103（tcgen05）与 SM90（Triton tile-64）→ SM80 无**，须显式 `--component-attention-backends transformer=fa`（参照 4×H200：dense FA 比 VSA 慢约 25%）。2×H200 驻留 39.0 s / 三件套 CPU offload 43.8 s；480p 单图 26.9 s、768p 单图 46.6 s |
| **zjwfufu/SMD-MiniMax-H3-{T2VA,Ref2VA}-{4,8}step**〔2026-11-06 新增〕 | **SMD** 蒸馏（代码 `github.com/zjwfufu/SMD`） | 4 / **8** | **含 Ref2VA 独立 checkpoint** | 2026-10-07（ComfyUI 版 10-13） | ⚠️ | 标准 Comfy `Load LoRA` 布局（无自定义节点），**框架侧未收录**，SGLang `--lora-path` 可否直读**未验证** |
| **berryber09/MiniMax-H3-FastH3-VSA-4step-pruned-w4a8**〔2026-11-06 新增〕 | FastH3 4 步 + pruned + **W4A8 ConvRot** 合并 | 4 | FL2VA（t2va/fl2va） | 2026-10-18 | ✅ | 单文件 **15.27 GiB**，是 A100 上最省的 t2va 快车道；W4A8 路径"Requires SM80+"，依赖 `comfy-kitchen>=0.2.27` |
| **alibaba-pai/MiniMax-H3-Acc-LoRAs** | **PDD（Parallel Decoding Distillation）** | **8** | **FL2VA 与 Ref2VA 两个文件都有** | 2026-08-26 | ✅ | 〔2026-11-06 更正〕~~唯一被 SGLang cookbook 写进正式流程的 Ref2VA 蒸馏~~ → 现在 Pika H3 Flex 与 FastH3-Omni 都已进一等文档，PDD 变成"需要手工离线融合（`build_minimax_h3_pdd_weights` + `fuse_minimax_h3_pdd_heads`）的那一条"；**请求步数已从 `9` 改为 `8`**（shift 12/3、`quality:"lossless"` 不变）；论文 arXiv:2607.26004 |
| lightx2v/Minimax-h3-Turbo | DMD 类 Turbo LoRA（rank128） | 4 / 8 | FL2VA(4 文件 v0.1~v1.2) + **Ref2VA(4step v0.1、8step v1.0)** | 2026-08-07 | ✅ | vLLM-Omni **官方支持表**：Ref2VA 4step→steps=5/shift=12/α=8；8step→steps=9/shift=6/α=8。SGLang 侧"Ref2VA 文件尚未成为 pinned 配方"。注意 `_comfyui_` 导出（QKV 融合）在 vLLM-Omni 被**按名字拒绝** |
| larryvrh/MiniMax-H3-Turbo-Lora | Turbo LoRA | 8 evals（请求写 9） | FL2VA | 2026-08-05 | ✅ | SGLang 推荐"速度/质量平衡首选"；文件 `minimax_h3_turbo_v4_step600_ema.safetensors` |
| drbaph/MiniMax-H3-Turbo-Lora-ComfyUI；Kijai/MiniMax-H3_comfy；Ap0ex/…Turbo-Pruned-ComfyUI；Abiray/…Turbo-Lora-Pruned-ComfyUI | Turbo 的 Comfy 版 + **rank 缩减(19~31)** | 4 / 8 | FL/Ref 混 | 2026-08-06～08-11 | ✅ | rank 缩减版 0.18–0.44 GiB，最便宜的提速；质量随之下降 |
| **PulpCut/MiniMax-H3-Ref2VA-Turbo-INT8-ConvRot** | **Turbo+INT8 一体化** | 4 | **Ref2VA** | 2026-08-15 | ✅ | 19.53 GiB 单文件解决"量化+蒸馏+Ref2VA"三件事 |
| MATLOWAI/minimax-h3-fused-turbo-int8-convrot | Turbo-8 + 风格(Mystic) + INT8 融合 | 4–8 | FL/Ref 融合 | 2026-08-29 | ✅ | 800K 下载；单文件 ~19.5 GiB |
| FastVideo/FastVideo-FastH3-4-step-Preview-v1-VSA-DataFree（及 `-LoRA`） | **DMD2 4 步**蒸馏 + VSA 稀疏注意力 | 4 | **仅 t2va** | 2026-08-27 | ⚠️ 权重可用、**VSA kernel 不支持 sm80** | 稠密后端（`fa`/`torch_sdpa`）可直接跑 FastH3 权重；`-LoRA` 仓库含 full-rank `.diff`/`set_weight`，SGLang 的 `--lora-path` 会拒绝，只能用合并版 |
| FastVideo/FastVideo-FastH3-8-Step-V2 | 8 步全量 checkpoint（带 VSA 学习门控） | 8 | **仅 t2va** | 2026-09-04 | ⚠️ 同上（`FASTVIDEO_VSA` 需 SM100a kernel） | vLLM-Omni 支持；steps=8、shift 10/3、guidance 1；明确"Ref2VA/FL2VA 不支持" |
| **OpenVDN/vdn-minimax-h3** | **VDN 混合注意力（滑窗 softmax + Video Delta 线性分支）+ 8 步 DMD2 LoRA** | 8 | t2va + **fl2va**（拒绝 ref2va） | 2026-09-02 | ✅ **文档明写 SM80 可跑**（滑窗走 FA3 的 Sm80 mainloop，FA2 级速度） | 加 4.3 GB 线性分支；A100 上按文档走 bf16 DiT + `--layerwise-offload-components`；SM80 未做基准；`--warmup-resolutions/--warmup-num-frames` 按你的成片尺寸设 |
| t8star/Vdn-Minimax-H3-Comfy；drbaph/vdn-minimax-h3-int8-convrot-comfyui；DeepBeepMeep → `minimax_h3_vdn_turbo_8step_lora` + `modules/vdn_module` | VDN 的 Comfy/INT8 版本 | 8 | FL2VA | 2026-09-03～09-04 | ✅ int8 版 | 线性分支 module 3.99 GiB(bf16)/2.02(int8) |
| FlashGen/Minimax-H3-4step-lora-flashgen（**ModelScope**） | FlashGen 原生布局 4 步，metadata 自带 sigma 日程 | 4 | T2VA | — | ✅ | vLLM-Omni 原生 LoRA 后端可直接吃 |
| pdmd2026/pdmd_2NFE_lora、pdmd_4NFE_lora；Iwannapose/minimax_h3_pdmd_2nfe_comfyui | PDMd 极端口径 | **2** / 4 | FL2VA | 2026-09-23 / 09-29 / 09-30 | ⚠️ | 2 NFE 属激进实验，画质风险高 |
| DeepBeepMeep → `minimax_h3_hyperflow_8step_v1.0`(2.60) / `taomate_3step`(0.17,rank19) / `joyfox_fl2va_4step`(0.70) | 社区少步 LoRA | 3 / 4 / 8 | FL2VA 为主 | 2026-08 起 | ⚠️ | rank 越小越省显存、越掉细节 |
| mvp-lab/MiniMax-H3-RAVEN-Streaming-LoRA | **因果流式**蒸馏（arXiv:2605.15190） | 4 | 长视频流式 | 2026-08-18 | ❌/⚠️ | 声称 24 GiB 跑 192×1376×768；SGLang 明确"RAVEN 这类 causal-streaming adapter 需要配套流式管线，**不是标准 H3 LoRA**" |
| Efficient-Large-Model/LongLive-Plug-MiniMax-H3-few-step | few-step plug-in | few | — | 2026-09-29 | ⚠️ | 卡片要求 few-step 与 CFG LoRA **分开跑** |

> ⚠️ **Ref2VA 用蒸馏的注意事项**（Comfy 官方教程原话）：参考 token 每一步都参与，4 步时"参考可能 barely applied"，主体姿态/脸部角度会随片长漂移；**要跟参考贴合就保持 20 步（必要时 25 步）**。另外音频比画面收敛慢：8 步时人声音色最弱，**12 步以上才可用**。也就是说你如果以 Ref2VA + 对白为主，4 步蒸馏不一定是净赚。

### 3.4 运行时"跳算"加速（不改权重）

| 方案 | 框架 | 开关 | 实测收益 | 质量代价 | 首发/参考 | A100 |
|---|---|---|---|---|---|---|
| Cache-DiT（保守档） | SGLang `quality:"high"` | 请求字段 | 4×H200：75.10→53.70 s（**1.40×**） | SSIM 0.931 / PSNR 28.16 dB | cookbook | ❌ **锁 4×H200，非 H200 直接 fail** | https://lmsysorg.mintlify.app/cookbook/diffusion/MiniMax/MiniMax-H3.md |
| Cache-DiT（手动） | SGLang | `--enable-cache-dit` 或 `SGLANG_CACHE_DIT_{ENABLED,FN,BN,WARMUP,RDT,MC,TAYLORSEER,TS_ORDER}` | Ascend 8 NPU：55.07 s vs 4 NPU 103.57 s | 近似，需自测 | cookbook | ✅（不能与 FSDP 同用；BCG 优先于它） | 同上 |
| Cache-DiT | vLLM-Omni | `-F quality=high` 或 `--cache-backend cache_dit` | 4×H200：85.49→63.36 s（**1.35×**） | SSIM 0.9709 / PSNR 34.98 dB | recipe | ⚠️ 未见硬件锁，需实测 | https://github.com/vllm-project/vllm-omni/blob/main/recipes/MiniMaxAI/MiniMax-H3.md |
| TeaCache | vLLM-Omni | `--cache-backend tea_cache --cache-config '{"rel_l1_thresh":0.17}'` | 官方 107 帧 T2VA 标定 | 阈值越高越糊 | recipe | ✅ **仅 FL2VA** | 同上 |
| **Spectrum 跳步** | SGLang | `--enable-spectrum --spectrum-warmup-steps 11 --spectrum-window-size 5 --spectrum-flex-window 1.0` | 4090：1008.6→**285.3 s（3.53×）**；配 Sage→Sol 达 219.0 s（4.61×） | PSNR 27.4/25.3（FA 档） | cookbook | ✅ 但 **SP>1 时禁用**（用 TP2+Ulysses1） | 同上 |
| **AdaLN 在线重建（无损）** | SGLang | `--minimax-h3-adaln-online true`（+ `--minimax-h3-adaln-host-cache-gb`） | **每卡少 24.2 GiB 显存**，bit-exact | 无（新日程首请求几秒重算） | cookbook | ✅ | 同上 |
| AdaLN 离线 sidecar | SGLang | `python -m sglang.multimodal_gen.tools.build_minimax_h3_adaln_cache ...` + `--minimax-h3-adaln-cache-path` | 省 AdaLN 分支驻留 | 绑定 steps/shift/mode，仅未量化权重 | cookbook | ✅ | 同上 |
| AdaLN 运行时复用（默认开） | vLLM-Omni | 默认开；关：`--cache-config '{"minimax_h3_adaln_cache":false}'` | 省投影计算 | **不省显存**（权重仍全驻留） | recipe | ✅ | 同上 |
| 注意力后端 | SGLang | `--attention-backend sage_attn` / `sol_attn` / `--component-attention-backends text_encoder=torch_sdpa,transformer=sol_attn` | 4090 上 INT8+FA 1.34×、+sol 1.81×、+sage 2.32×、+hybrid 2.48×（20 步档） | PSNR 24.81→23.04 dB 递减 | cookbook | ✅ sage/sparge（sm80）；❌ subblock/VSA | 同上 |
| 注意力近似 | vLLM-Omni | `--diffusion-attention-config '{"default":{"backend":"TRTLLM_ATTN","quant":{...},"skip_softmax":{...}}}'` | 1.211×(SAGE) / 1.084×(Skip-Softmax) / 1.237×（组合） | LPIPS 0.3697 / 0.0917 / 0.3750 | 博客 | ❌ 依赖 TRTLLM_ATTN（Blackwell） | https://vllm.ai/blog/2026-09-01-minimax-h3-production-serving |
| 系统级无损（vLLM-Omni） | — | packed-seq 细化、fused DiT 算子、VAE tile+PP、GPU output prep、D2H/IPC | Diffusers→vLLM-Omni **1.445×**（-30.8%） | 非位级一致 | 博客 | ✅（不含 TRTLLM 部分） | 同上 |
| Fast Ulysses（对称内存 all-to-all） | vLLM-Omni | `--ulysses-a2a-permute` | 计入上面 1.445× | 无 | 博客 | ✅（同 NUMA/NVLink 收益大） | 同上 |
| latent 超分（**小图生成+放大**） | vLLM-Omni / ComfyUI | `--additional-config '{"latent_upscaler_path":"minimax_h3_latent_upscaler_3d_bf16.safetensors"}'`，请求 `-F 'extra_params={"latent_upscale":2.0}'` | 960×544 → 1920×1088 只解码一次 | 训练过的 3D 卷积，不出现双影/鬼影（bilinear 会） | 2026-08-17 | ✅ | https://huggingface.co/LBH-123-AI/Minimax_h3_latent_Upscaler |
| 多路输出复用 conditioning | SGLang | `"num_outputs_per_prompt":2` | 2×5090：5 步 2 输出 155.39 s vs 单输出 78.11 s（≈1.5×而非2×） | seed 展开确定性 | cookbook | ✅ | cookbook |
| ComfyUI 引擎本身 | ComfyUI（+SGLang `--comfyui-mode` 当 per-step DiT 后端） | 12 GB 官方路线：`pruned_int8_convrot` + `qwen3vl...nvfp4_awq`；`--use-ck-attention` | 与 SGLang Recipe B/A 同量级（SGLang 略优） | — | 2026-08 | ⚠️ Comfy Kitchen attention **不支持 int8-convrot checkpoint**（#15529，会对齐错误崩） | https://docs.comfy.org/tutorials/video/minimax/minimax-h3 |
| **vLLM-Omni `res_multistep` 二阶采样器**〔2026-11-06 新增〕 | vLLM-Omni | 请求 `extra_params={"sampler":"res_multistep"}`（视频+音频两条流同时生效） | **2.35×**（1×H100，672×384/124f：Euler-50 64.65 s → RES-20 27.50 s） | LPIPS 0.1190 / 音频 CLAP 0.9741 | PR **#8378，2026-10-04 合并** | ⚠️ **与所有固定蒸馏 sigma 的产物硬互斥**（"remain restricted to Euler"）→ 只用在不挂蒸馏的档位 | https://github.com/vllm-project/vllm-omni/blob/main/recipes/MiniMaxAI/MiniMax-H3.md |
| **LiteVAE 视频解码器**〔2026-11-06 新增〕 | vLLM-Omni | `--additional-config '{"lightvae_decoder_path":"/weights/lightvae-lite-h3-decoder.safetensors"}'` | 用小 Transformer 换掉 video **decoder**，降低解码延迟（官方拒绝把 E2E 与 VAE 时延混谈，需自测） | "Generated pixels can differ from the original decoder" | PR **#9245，2026-10-31**；权重 `lightx2v/LightVAE`（**Apache-2.0**，10-10） | ⚠️ video **encoder 与 audio VAE 不变**；与 bundled NVFP4 自动发现互斥；checkpoint 不兼容则**直接失败，不静默回退** | https://github.com/vllm-project/vllm-omni/blob/main/docs/user_guide/diffusion/light_vae.md |
| **Open-H3-Regenerate-2K（3 步 2K/2.5K 再生成）**〔2026-11-06 新增〕 | vLLM-Omni 独立部署 | `source_video` + `extra_params={"task":"t2va","regenerate":true}`，`latent_upscale` 默认 2560×1440；3 步（sigmas 0.909375, 6/7, 2/3）或 2 步 | 把"高分辨率"从 50 步全量生成变成**草稿 + 3 步** | 保留草稿音轨（H3 audio-VAE 往返）；对静音做条件 | 权重 **2026-10-26**；recipe PR **#9562，11-02** | ⚠️ **该服务器只接 regenerate 请求**，须与主生成服务分开部署；拒绝 `flow_shift`/`sampler`/`latent_refine`/per-request `lora` | https://huggingface.co/Efficient-Large-Model/Open-H3-Regenerate-2K |

### 3.5 控制/风格 LoRA、ControlNet 与生态（与加速正交）

| 名称 | 类型 | 首发 | 链接 |
|---|---|---|---|
| alibaba-pai/MiniMax-H3-Fun-Controlnet-Union（2.0） | ControlNet 联合（Canny/Depth/Pose…），int8 版 2.14 / 4.22 GiB | 2026-08-24 / 09-22 | https://huggingface.co/alibaba-pai/MiniMax-H3-Fun-Controlnet-Union-2.0 |
| fal/MiniMax-H3-Realism-People-LoRA | 真人写实风（触发词 `r34l1sm`，scale 0.7，仍 50 步） | 2026-08-10 | https://huggingface.co/fal/MiniMax-H3-Realism-People-LoRA |
| Jojocodex 三件套（spatial-physics / wushu-action / Camera-Motion=yunjing） | 空间物理 / 武打 / 运镜 | 2026-08-16（v7 FL2VA+Ref2VA 2026-08-30） | https://huggingface.co/Jojocodex/minimax-h3-spatial-physics-lora |
| akatz-ai/MiniMax-H3-Character-Swap-LoRA | 换角色（Ref2VA） | 2026-09-25 | https://huggingface.co/akatz-ai/MiniMax-H3-Character-Swap-LoRA |
| pablodawson/MiniMax-H3-360-Orbit-LoRA | 环绕运镜 | 2026-09-27 | https://huggingface.co/pablodawson/MiniMax-H3-360-Orbit-LoRA |
| Cseti/MiniMax-H3_Ref2VA-LoRA-CrossView-Warp_v1 | 新视角 | 2026-09-20 | https://huggingface.co/Cseti/MiniMax-H3_Ref2VA-LoRA-CrossView-Warp_v1 |
| Inner-Reflections/MiniMax-H3-Looping-Sketch-Anime；siraxe/3d_to_real_detail_slider_H3；prithivMLmods/MiniMax-H3-Facial-Realism-CloseUp；JOKER141/Combat-Base-V2；Hearmeman/minimax-h3-loras；Alissonerdx/Minimax-H3-ComfyUI | 风格/细节滑杆/特写/格斗/合集 | 2026-08-11～09-06 | https://huggingface.co/Alissonerdx/Minimax-H3-ComfyUI |
| ostris/minimax_h3_training_adapter + AI Toolkit | **自训 LoRA 路线**（8 个 adapter，0.2–0.4 GiB；toolkit 里有 NVFP4 量化选项） | 2026-08-06 | https://huggingface.co/ostris/minimax_h3_training_adapter |
| ModelTC/Minimax-H3-Turbo（GitHub，含推理脚本与 NFE/shift 表） | 蒸馏配套代码 | 2026-08-07 | https://github.com/ModelTC/Minimax-H3-Turbo |
| xmarre/ComfyUI-Spectrum-MiniMax-H3（Chebyshev 求解器免训练加速）；HELPMEEADICE/TE-Speed-MiniMaxH3-OSS；FreeVideo（"H3 in 8 GB VRAM"）；antirez/h3.c | 社区引擎/加速 | 2026-08-03 / 09-13 | https://github.com/MiniMax-AI/awesome-minimax-h3-integration |
| 官方集成清单 | — | — | https://github.com/MiniMax-AI/awesome-minimax-h3-integration |

**明确不存在的东西**（我查过、结论是"没有"）：
- 官方 **H3-Lite / H3-Turbo / H3-Small** 小模型：MiniMaxAI 名下 21 个仓库里只有 `MiniMax-H3` 一个 H3 条目，卡片也无任何量化/蒸馏版本描述。
- 官方 DiT 量化仓库（`MiniMax-H3-AWQ`/`-FP8`/`-GGUF`）：命中的都是社区仓库或 Qwen3-VL 编码器量化。
- 名为 `MiniMax-H3-Distill` 的仓库：搜 "H3 distill" 29 条全是无关的 MiniLM `H384` BERT 模型；蒸馏生态统一叫 Turbo / Acc / PDD / PDMD / few-step。

---

## 4. 两条框架路线的落地命令（A100-40G 版）

> 共同前提：`pip install comfy-kitchen`（W4A8/W4A4/INT8 在 A100 上靠它跑）；国内下载用 `HF_ENDPOINT=https://hf-mirror.com`，或 SGLang 直接用 ModelScope：`SGLANG_USE_MODELSCOPE=true` + `--model-path MiniMax/MiniMax-H3`。

### 4.1 方案 A（主推）：SGLang + Ref2VA + W4A8 + 8 步 PDD
> 〔2026-11-06〕本方案仍是"**DiT 与编码器都量化驻留**"的最佳模板；但**少步那一层现在有更省事的替代品**：`sglang serve --model-path Pika-Labs/Pika-H3-Flex --model-variant ref2va`（6 步，适配器自动加载并校验，无需下面第 1 步的离线融合）。二者取舍见 §10.2 与 §12.7；注意 Pika 的 FP32 未合并适配器与量化基座同用的组合**文档未标定**，上机先测峰值与同 seed PSNR。

**4×A100-40G：**
```bash
pip install comfy-kitchen   # W4A8 需要 comfy-kitchen>=0.2.27

# 1) 离线把 PDD 主干 LoRA 合进 Ref2VA transformer，再融合分区间输出头
BASE=/models/MiniMax-H3/Ref2VA/transformer
LORA=/models/h3-acc-loras/MiniMax-H3-Ref2VA-Acc-8Step.safetensors
PDD=/models/h3-ref2va-pdd
python3 -m sglang.multimodal_gen.tools.build_minimax_h3_pdd_weights "$BASE" "$LORA" "$PDD"
python3 -m sglang.multimodal_gen.tools.fuse_minimax_h3_pdd_heads "$PDD" --video-shift 12.0 --audio-shift 3.0

# 2) 起服务（TP2 × Ulysses2 是 4×H100 上实测最快拓扑；ConvRot 的 256-group 允许 TP1/2/4）
SGLANG_DIFFUSION_MINIMAX_H3_PDD_HEADS="$PDD/pdd_fused_heads.safetensors" \
sglang serve \
  --model-path MiniMaxAI/MiniMax-H3 \
  --model-variant ref2va \
  --transformer-weights-path "$PDD/transformer" \
  --component-weights-paths.text_encoder Winnougan/MiniMax-H3-INT4_Convrot_ComfyUI/qwen3vl_32b_minimax_h3-w4a8_convrot.safetensors \
  --num-gpus 4 --tp-size 2 --ulysses-degree 2 \
  --encoder-parallel auto --performance-mode memory \
  --attention-backend fa --enable-torch-compile false \
  --warmup-resolutions 1344x768 --warmup-num-frames 124 \
  --port 30011
```
请求必须与融合头一致：`"task":"ref2va"`、`"num_inference_steps":9`、`"flow_shift":12.0`、`"audio_flow_shift":3.0`、`"quality":"lossless"`（步数/shift 不匹配会被服务端拒绝）。

**2×A100-40G：** 把拓扑换成 `--num-gpus 2 --tp-size 2 --ulysses-degree 1`，并加显存保险：
`--layerwise-offload-components text_encoder`（或 `dit,text_encoder` + `--dit-layerwise-resident-layers 20 --dit-offload-prefetch-size 1`）。
> 想省掉第 1 步的离线融合，就把 `--transformer-weights-path` 换成现成文件：
> `--component-weights-paths.transformer PulpCut/MiniMax-H3-Ref2VA-Turbo-INT8-ConvRot/minimax_h3_ref2va_pruned_turbo_int8_convrot.safetensors`（4 步，请求 `num_inference_steps:5`），或 `Winnougan/.../MMH3-FLA-TurboV1.2-int8-convrot-simple.safetensors`。
> **想要 FL2VA+Ref2VA 一个服务全拿下**：`--model-variant hybrid` + Singularity v1.3 的 `Minimax-h3_Singularity_ref2va_Pruned_v1.3_int8.safetensors`（19.53 GiB）或 `_w4a8`（10.96 GiB）。

### 4.2 方案 B（无损优先）：SGLang + AdaLN 在线重建

```bash
sglang serve --model-path MiniMaxAI/MiniMax-H3 --model-variant ref2va \
  --minimax-h3-adaln-online true \
  --num-gpus 2 --tp-size 2 --ulysses-degree 1 \
  --performance-mode memory \
  --layerwise-offload-components text_encoder,vae \
  --attention-backend fa --enable-torch-compile false --port 30011
```
效果：DiT 61.73→**37.5 GiB**（每 TP rank ≈18.8 GiB），且**逐位一致**；编码器交给 layerwise offload。这是"不牺牲画质"的最省显存手段，比 FP8 更适合 A100。
再加一档无损：`--layerwise-resident-layers video_vae=36`（解码块驻留，fp16 存放，**解码从 60~209 s 降到 ~10 s 且逐位一致**）。

### 4.3 方案 C：vLLM-Omni（把 2×40GB 当成"大号 4090/5090"）

```bash
export VLLM_WORKER_MULTIPROC_METHOD=spawn
export VLLM_OMNI_VIDEO_SYNC_TIMEOUT=14400   # 关键：否则长请求撞 600 s 默认超时

CUDA_VISIBLE_DEVICES=0,1 vllm serve /models/MiniMax-H3/Ref2VA \
  --omni --trust-remote-code --host 0.0.0.0 --port 8000 \
  --task-type ref2va --served-model-name MiniMaxAI/MiniMax-H3 \
  --num-gpus 2 --tensor-parallel-size 2 --text-encoder-tp-size 2 \
  --usp 1 --ring 1 \
  --vae-patch-parallel-size 2 --vae-parallel-mode tile --vae-use-tiling \
  --enable-distributed-layerwise-offload --dlo-no-use-allgather \
  --dlo-resident-layers 20 \
  --enforce-eager --diffusion-attention-backend FLASH_ATTN
```
官方对照表：`rtx4090` = 2×24GB / 1024×576 / **12** 层驻留；`rtx5090` = 2×32GB / **1344×768** / **20** 层驻留。40GB 卡从 20 往上抬，逐档重测峰值。
4 卡：`--num-gpus 4 --tensor-parallel-size 2 --usp 2 --text-encoder-tp-size 4 --vae-patch-parallel-size 4`（实测 4 卡相对 2 卡 **≈1.6×**）。
Ref2VA 蒸馏（官方支持，无需离线融合）：
```bash
  --lora-backend peft --lora-path /models/turbo/minimax_h3_ref2v_turbo_8step_v1.0_768p_bf16.safetensors
  # 请求： -F num_inference_steps=9 -F flow_shift=6 -F 'extra_params={"task":"ref2va","duration":5,"audio_flow_shift":3.0}'
  #       -F 'lora={"name":"h3-turbo","path":"...","scale":1.0}'
```
坑：`--lora-path` 指整个 Turbo 仓库会被判"歧义"拒绝；`_comfyui_` 导出被按名字拒绝；**DLO + 标准 layerwise/module offload 与 LoRA 预融合互斥**（只支持 DLO）；`--dlo-resident-layers` 不降主机内存。

### 4.4 API 形状（两框架）

* SGLang：`POST /v1/videos`（异步 JSON）+ `GET /v1/videos/{id}` 轮询 + `GET /v1/videos/{id}/content?variant=N` 下载；`conditions[]` 用 `{"type":"image|video|audio","uri":"file:///data/minimax-h3/x.png","role":"reference"}`，`<Picture 1>`/`<Video 1>`/`<Audio 1>` 序号语义与数组顺序绑定；V2V 走 ref2va + `type:"video"`（`start_time_seconds` 可选）。
* vLLM-Omni：`POST /v1/videos/sync`（multipart），`-F 'input_reference=@/path/ref.jpg;type=image/jpeg'`，`-F 'audio_reference={"audio_url":"https://... 或 data: URL"}'`（裸本地路径会被拒）；`t2va` 必须显式 `-F 'aspect_ratio=16:9'`。Ref2VA 参考图校验：短边 ≥256、长边 ≤5760、宽高比 0.4~2.5。响应头 `x-inference-time-s` / `x-peak-memory-mb` 直接给测速与显存。

---

## 5. 显存账本与耗时预估

### 5.1 每卡权重驻留（TP2 = 2 卡，TP4 = 4 卡；不含激活/VAE）

| 组合 | 合计 | 2×40G（TP2） | 4×40G（TP4） |
|---|---|---|---|
| 官方 BF16（DiT 61.73 + TE 47.97 + VAE 5.4） | 115 GiB | 54 GiB/卡 ❌ | 26.9 GiB/卡 ⚠️（+激活≈23 GiB → 49.9 GiB，与 4×H100 实测一致 → ❌） |
| AdaLN 在线（无损，省 24.2） | 91 GiB | 43 GiB/卡 ❌→需 offload TE | 16.7 GiB/卡 ⚠️→ ✅ 可配 `text_encoder` offload |
| 剪枝 BF16（37.46+47.97+5.4） | 90.8 | 40.9 ❌ | 19.3 ⚠️ |
| 剪枝 INT8 ConvRot + 编码器 INT8（19.53+25.28+5.4） | 50.2 | 23.1 ✅ | 9.6 ✅ |
| **剪枝 W4A8 + 编码器 W4A8（11.68+14.62+5.4）** | **31.7** | **14.3 ✅** | 7.0 ✅ |
| 剪枝 GGUF Q4_K(10.64) + 编码器 GGUF Q4_K_M(16.97) | 33.0 | 14.9 ✅（不能用 LoRA/FSDP） | 7.4 ✅ |
| Ref2VA-Turbo-INT8(19.53) + AWQ 编码器(14.61) | 39.5 | 18.1 ✅ **且只有 4 步** | 9.0 ✅ |

**结论：2×40G 想要 768p 稳定，量化几乎是必须的**（或 DLO/offload 换主机内存）；4×40G 可以走"剪枝 BF16/INT8 + TP4 + Ulysses"，留 20+ GiB 给激活。
激活侧参考实测：1344×768 / 124 帧 / 50 步的无损驻留在 4×H100 上是 49.8~66.0 GiB/卡（其中权重只占 26.9）→ **激活+缓冲约 23~39 GiB**；1024×576 / 124 帧 + DLO 时 vLLM-Omni 实测只到 15.3 GiB/卡。

### 5.2 耗时锚点（实测，别混用口径）

| 硬件 | 框架/配置 | 负载 | 结果 |
|---|---|---|---|
| 2×RTX 4090 | vLLM-Omni TP2+DLO(12), eager | 1024×576 /124f/60 步 T2VA | **434.9 / 429.3 s**，峰值 15.3 GiB/卡 |
| 2×RTX 4090 | 同上 | Ref2VA 同形状 | **891.9 / 892.1 s**，14.6 GiB/卡 |
| 4×RTX 4090 | TP2×USP2 | T2VA / Ref2VA | **273.8 / 269.5 s**，**545.2 s**（≈1.6×） |
| 2×RTX 5090 | SGLang TP2, 20 层驻留, 无损 | 1344×768 /124f/50 步 | **559.67 s**（525 去噪 + 33.6 解码），26.3 GiB/卡 |
| 1×RTX 4090 | SGLang 流式 offload | 1344×768/107f/20 步 BF16+FA | 405.6 s；INT8+FA 303.3 s；INT8+Sage 174.9 s；INT8+Sage→Sol 223.9→163.8 s |
| 1×RTX 4090 | 50 步档 | kitchen_int8+Spectrum `11/5/1.0` | **285.3 s（3.53×）**；再叠 Sage→Sol 219.0 s（4.61×） |
| 12 GiB 卡 + 32 GiB 主机 | SGLang Recipe A | 864×480/124f/20 NFE | 16.8–18.7 s/it；整请求 ≈235 s（ComfyUI 276–302 s） |
| 16 GiB + 大主机 | SGLang Recipe B | 同上 | **6.01 s/it**（主机 pin 住权重后到算力墙） |
| 1×RTX 5090 + 60 GiB 主机 | SGLang（14 层驻留） | 864×480/124f/20 | 112.2 s（编码 4.2 / 去噪 5.14–5.17 s每步 / 解码 6.4）；ComfyUI 140.9–145.9 s |
| 4×H200 | SGLang 无损驻留 | 1344×768/124f/50 | 75.10 s（`high` 53.70 s） |
| 4×B300 | SGLang + FastH3 VSA 4 步 | 5 s 短片 | E2E **4.1 s**（RTF 0.79，实时）；峰值 95.7 GB/卡 |
| 8×B200 | vLLM-Omni + FastH3 Dense 4 步 | 10 s 片 | **8.68 s**（RTF 0.86，实时） |
| VDN-H3 | 1×/2×/4×/8× B200 | 1344×768/345f/8 步 | 7.45（bf16 单卡）→ 3.30 → 1.67 → **0.88 s/NFE** |
| **〔2026-11-06 新增，官方实测〕** | **vLLM-Omni 官方 A100 章节**（**2×A100-SXM4-80GB**，TP2，只 offload `text_encoder`，`FLASH_ATTN`，`quality="high"`，**25 步**） | Ref2VA 1344×768 / 10.0 s @24fps | **E2E 756.3 s**；quiescent **41.69 GiB/卡**、allocator peak **54.63**、`nvidia-smi` 峰值 **57.46**；再加 2 个参考视频 → 峰值 **67.92 GiB/卡** |
| **〔2026-11-06 新增，官方实测〕** | **Pika H3 Flex 6 步**（1×H200，默认内存策略，5 s） | 1344×768 | t2va **37 s** / fl2va 42 s(cold) / **ref2va（2 图 + 1 带音频视频）260 s**；官方注明 ref2va 的时间"mostly goes to its long packed sequence" |
| **〔2026-11-06 新增，官方实测〕** | **FastH3-Omni 8 步（Ref2VA）** | 480p/768p，124 帧 | 2×H200 驻留 **39.0 s** / 三件套 CPU offload 43.8 s；4×B200 10.3 / 15.3 s；480p 单图 26.9 s、768p 单图 46.6 s、768p 参考视频 37.1 s |
| **〔2026-11-06 新增，官方实测〕** | **vLLM-Omni `res_multistep`**（1×H100） | T2VA 672×384 / 124 帧 | Euler-50 **64.65 s** → RES-20 **27.50 s（2.35×）**，LPIPS 0.1190 / CLAP 0.9741 |

**A100-40G 的推算（明确标注：推算，非实测）**
A100-40G 稠密 BF16 张量吞吐 ≈ 312 TFLOPS，RTX 4090 ≈ 165、RTX 5090 ≈ 210+，即单卡算力约等于 1.5~1.9× 4090；带宽 1.555 TB/s > 4090 的 1.008 TB/s。
〔2026-11-06 校准〕现在多了一条**官方同架构实测**可以约束推算区间：2×A100-**80G**、TP2、**仅 offload 编码器**、Ref2VA 1344×768 / **10.0 s 片** / **25 步** / `quality=high` = **E2E 756.3 s**（峰值 54.63–67.92 GiB/卡）。也就是**约 30 s/每步**（243 帧 + 两张 2726×1536 参考图的 packed 序列远大于 124 帧的 t2va；Sol Engine 那条 4.35 s/步是 124 帧 t2va，不能直接类比）。据此：
- **多参考 Ref2VA 在 768p 上是"分钟级/条"的任务，即使在 80GB 卡上**。你的 5 s 档（124 帧）大约能砍到该值的 40~55%，再按 8 步折算：**2×A100-40G（量化驻留）≈ 90~220 s/条**，4 卡 ≈ 60~140 s。**这比下表原先的乐观推算更保守，请以这组为准。**
- **2×A100-40G，W4A8 + Ref2VA 8 步**：以 2×4090 的 892 s（60 步 Ref2VA）为锚，步数 60→8 是 7.5×，算力 1.9×，量化再省传输 → 乐观 **60~120 s** 一条 1024×576/5 s 片；1344×768 约 1.5~2× 该值（与上一条区间相容）。
- **2×A100-40G，50 步无损（方案 B）**：落在 2×5090 的 560 s 与 2×4090 的 DLO 值之间，估 **300~450 s**（t2va 类；Ref2VA 多参考请按 2~3× 计）。
- **4×A100-40G**：并行效率参考 vLLM-Omni 4090 的 1.6×（2→4 卡）与 SGLang B200 的 86~91%；若是 NVLink SXM，Ulysses 侧收益会明显高于 PCIe 消费卡。
- **2×A100-40G，W4A8 + Ref2VA 8 步**：以 2×4090 的 892 s（60 步 Ref2VA）为锚，步数 60→8 是 7.5×，算力 1.9×，量化再省传输 → 乐观 **60~120 s** 一条 1024×576/5 s 片；1344×768 约 1.5~2× 该值。
- **2×A100-40G，50 步无损（方案 B）**：落在 2×5090 的 560 s 与 2×4090 的 DLO 值之间，估 **300~450 s**。
- **4×A100-40G**：并行效率参考 vLLM-Omni 4090 的 1.6×（2→4 卡）与 SGLang B200 的 86~91%；若是 NVLink SXM，Ulysses 侧收益会明显高于 PCIe 消费卡。
- ⚠️ **40GB 与 80GB 不是一条曲线的两个点**：官方那套 TP2 需要每卡 30 GiB DiT + 25.75 GiB 编码器（合计 55.75 GiB）才谈得上"只 offload 编码器"，40GB 卡必须先量化（W4A8 组合 ≈13 GiB/卡）才能复刻同样的拓扑，否则只能退回"多 offload + 更慢"（见 §12.4 与 #6492 的 DLO 对比）。
> 注意别外推"实时"类数字：B300/H100 的 4~9 s 实时结果依赖 FP8/MXFP8/VSA/TRTLLM，A100 一个都用不上；Pika 官方自己的 **ref2va 6 步 = 260 s（1×H200）** 也说明 Ref2VA 的墙钟主要花在 packed 序列而不是步数。

---

## 6. 风险、已知 Bug 与验证清单

**A100 上会踩的坑（按严重度）**

1. **A100 长期不在官方验证列表里；〔2026-11-06 更新〕vLLM-Omni 已补上 A100 章节，但那是 80GB。** SGLang 的 `supportedHardware` 仍含 3090/3060 与 h100/h200/b200/b300 而**没有 a100**；vLLM-Omni recipe 现在有 "**Two 80 GB GPUs (A100): TP2 with text-encoder layerwise offload**"，但按 **A100-SXM4-80GB** 验证（40GB 仍无配方；社区 PR #6492 做过 A100-SXM4-**40GB** 配方，**2026-09-28 被关闭且未合并**）。文档态度仍是 "Ampere and Ada are enabled but not benchmarked"。→ **把它当作"能跑但官方不给 40GB 配方"，逐项自测峰值。**
2. **`quality:"high"` 在 SGLang 上是 fail-closed 的**，非 4×H200 直接拒绝（issue #33720，2026-08-05 开、2026-10-06 关）。→ A100 请用手动 `SGLANG_CACHE_DIT_*`。
3. **INT8 ConvRot 曾有静默正确性 Bug**：#40127（2026-09-18 开，**2026-10-05 关**）——INT8 ConvRot checkpoint 跳过 head-interleaved QKV 重排，**输出被悄悄破坏**。→ 必须用 10-05 之后的构建，并做一次与 BF16 同 seed 的 PSNR 对比。
4. **主机内存才是真正的门栏**：vLLM-Omni DLO 要求 ≥200 GiB 可用/推荐 384 GiB；SGLang 驻留模式曾每 rank 过 61.7 GiB（2 rank 114.3 GiB → 被 SIGKILL/exit 137，#34902，2026-08-15 开，**仍未关**）；4×RTX 3090 + 64 GiB 主机（#38605，2026-09-09 开、09-10 关）表现为**画面乱码**而不是 OOM。→ 先看 `free -g`，起服务后核对日志行 `Layerwise offload: host memory available: N GiB` 与 `leaving N GiB of weights on the checkpoint mapping`。
   - 近邻证据：4×L40S（48 GB，layerwise offload）跑 Ref2VA 的案例 #34110（2026-08-08 开、08-09 关）——**根因不是框架，而是权重分片下载损坏**；重新下载 `Ref2VA/transformer/` 并逐片 SHA256 校验后画面正常。这条对 40GB 卡最实用：**先校验权重完整性，再怀疑配置**。
5. **磁盘**：流式卸载时每步重读 ≈(50 − 驻留层 − 主机已 pin 层)×1.23 GiB；32 GiB 主机下 24GB 卡约 38 GiB/步 → **PCIe 4.0 NVMe 是硬性要求，SATA SSD 直接不可用**。Windows 侧还要把 checkpoint 放 ext4（WSL2 内），别放 `/mnt/c`。
6. **`--text-encoder-tp-size` 曾被静默丢弃**（vllm-omni #7564，2026-09-15 开、09-21 关）；`--dlo-resident-layers` 在旧构建里是"unrecognized arguments"（#5799，仍未关）；4×4090 DLO 的 `cudaHostRegister` 会**永久挂起**，workaround 是 `--dlo-host-registration-limit-gib=1`（#6726，2026-08-28 开、09-19 关）。
7. **`--attention-backend` 全局设置可能直接把服务打死**（非 DiT 组件缺该 kernel，#35743）→ 用 `--component-attention-backends text_encoder=torch_sdpa,transformer=...` 限定。
8. **FSDP 与量化/GGUF/mixed 格式互斥**；GGUF 也不能配 LoRA。ConvRot 的 H3 256-group DiT **不支持 TP8**。
9. **SageAttention 的 INT8 attention 在 H3 上有特定画质问题**（末层 block 的 K 信号集中在少数通道，行级共享 scale 会丢）→ 表现为片尾 morphing、字幕乱码；解法是换 **Comfy Kitchen attention（带 channel rotation）**，但**它又不支持 int8-convrot checkpoint**（#15529）。
10. **Ref2VA + 少步蒸馏**的画质风险（§3.3 原话）与 **Ref2VA 多参考视频的显存/耗时爆炸**：4×B300 上双参考视频 362 帧 1344×768 的 model-stage 均值是 **784 s**，而同机 FL2VA 209 帧 1248×768 只要 **87 s**。
11. 商用许可：MiniMax H3 Community License + 本地生成内容商用需 Comfy 代理的商业授权；HF 直连不通时用 hf-mirror/ModelScope 不改变许可义务。
12. **公开资料里没有 A100 一手实测**（截至 2026-10-08）。中文社区里"8G 显存可玩/一键整合包"的教程（知乎 2026-08-12、阿里开发者 2026-09-24、B 站、1Panel 评测 2026-08-23 用的是 GB10 128GB 统一内存 + NVFP4 混合量化）走的都是 **ComfyUI 整合包路线**（INT8/GGUF 权重 + 4B/8B ClipProj 小编码器 + Turbo LoRA，甚至 FreeVideo 这类独立引擎），而不是 SGLang/vLLM-Omni 服务化。所以本报告里 A100 的结论是"由 SM80 能力矩阵 + 相邻档位实测推导"，不是照抄他人 A100 数据。

**〔2026-11-06 新增风险〕**

13. **请求契约漂移**：SGLang 对 PDD 的 `num_inference_steps` 一个月内从 `9` 改成 `8`，而解释句没变。→ 任何"照抄旧命令/旧请求体"的做法都可能在升级框架后静默改变画质；**把产物、steps、shift、quality 四项一起 pin 进配置**。
14. **少步方案自带的硬约束**：Pika H3 Flex **只接受 6 步**、**不支持 `quality:"high"`**、**适配器不许 BF16 合并**（会削掉约 1/3 更新量）、`--lora-path` 不能替换自带适配器；FastH3-Omni / FastH3 V2 **拒绝** `--model-variant`、`ring>1`、`torch.compile`、BCG，且**在 SM80 上拿不到 VSA**。→ 这些不是调优建议，是**服务契约**，会限制你后续叠加（尤其与 Cache-DiT / Spectrum / Ulysses>1 的组合）。
15. **高分辨率服务互斥**：`Open-H3-Regenerate-2K` 的 recipe 明写 "every request on this server is a regenerate request; serve plain MiniMax-H3 from a separate server" → 4 卡机上**主生成与 2K 再生不能同卡共存**，要么分时、要么 2+2 拆分（拆分后 Ref2VA 侧退化为 TP2×U1）。
16. **官方仍未开源的两块**（README 11-06 现版复核）：H3 **原生稀疏注意力**仍是 "will be released in a future update"；**H3-Regenerate-2K 模块**仍未开源（社区/NVlabs 的 Open-H3-Regenerate-2K 已补位，但它不是官方实现）。所以"官方同画质 2K"这条只能靠 API 校验，不能靠本地复现。

**建议的落地验证顺序（每步都有明确判据）**
0. **先校验权重完整性**：`Ref2VA/transformer/` 的 13 个分片逐一比对 SHA256（#34110 的"雪花屏"就是分片损坏，不是配置问题）。用 hf-mirror/ModelScope 下载时尤其要做。
1. `nvidia-smi topo -m` + `free -g` + `nvme smart-log`/顺序读速 → 决定 offload 策略。
2. 起服务后立刻核对日志里的组件放置行（`Loaded video_vae: ... host mmap` vs `host pageable`）。
3. 用 `--warmup-resolutions <你要服务的尺寸> --warmup-num-frames <帧数>`（SGLang）预热，否则首个长请求多付 2~3 s 分配器增长；注意默认预热 1344×768×124 在消费机上吃掉 7.6 min 启动。
4. 显存口径统一用响应头 `x-peak-memory-mb` / `torch.cuda.set_per_process_memory_fraction` 逼出 OOM，**不要读 `nvidia-smi`**（那是 caching allocator 的 reserve，会高估）。
5. 画质回归：同 seed 跑 BF16 无损基线 vs 候选（量化/蒸馏/cache）各一次，量视频 PSNR/SSIM + **听音频**（文档的 SSIM/PSNR 只覆盖画面）；Comfy 教程给的判据：细节密集画面在低步数会出现三角网格伪影。
6. 通过标准建议：画面 PSNR ≥ 25 dB（vs lossless）、音频无 8 步级的人声劣化、`ffmpeg -v error -i out.mp4 -f null -` 通过。

---

## 7. 一页决策树

```
必须 Ref2VA？
├─ 是 → 少步数只能选：alibaba-pai PDD-Ref2VA(8步) / LightX2V ref2v Turbo(4|8步) / PulpCut Ref2VA-Turbo-INT8 / Singularity hybrid
│        ├─ 主机内存 ≥200 GiB → vLLM-Omni DLO（--dlo-resident-layers 20~28）+ Ref2VA Turbo（官方支持，最省事）
│        └─ 主机内存不足 → SGLang + W4A8/INT8 量化权重驻留 + TP2/TP4（不靠主机）
│        └─ 要极致画质 → 50/20 步 + 量化 + AdaLN 在线（无损省 24.2 GiB）+ 手动 Cache-DiT
└─ 否（可 FL2VA）→ 额外可用：TeaCache、VDN-H3(8步混合注意力，SM80 明确可跑)、Spectrum 跳步(需 SP=1)

追"实时"？ → 只有 4 步 + 大机器（B300/H100 级 + FP8/VSA）才做到；A100 上按分钟级规划
```

---

## 8. 参考链接（按用途）

**官方**
- 模型与部署：<https://github.com/MiniMax-AI/MiniMax-H3> · <https://huggingface.co/MiniMaxAI/MiniMax-H3> · <https://www.minimax.io/blog/minimax-h3>
- 发布与时点：<https://www.reuters.com/world/china/chinas-minimax-releases-h3-video-model-2026-07-31/>
- 官方集成清单：<https://github.com/MiniMax-AI/awesome-minimax-h3-integration>
- 官方权重剪枝/量化配套：<https://huggingface.co/Comfy-Org/MiniMax-H3>（diffusion_models / text_encoders / vae / loras / model_patches）

**SGLang**
- H3 cookbook：<https://lmsysorg.mintlify.app/cookbook/diffusion/MiniMax/MiniMax-H3.md>（Mintlify URL 加 `.md` 取原文）
- 量化：<https://lmsysorg.mintlify.app/docs/sglang-diffusion/quantization.md> · 注意力后端：<https://lmsysorg.mintlify.app/docs/sglang-diffusion/attention_backends.md>
- 关键 Issue：#33720 · #34110 · #34227 · #34902 · #35743 · #38605 · #40127（`https://github.com/sgl-project/sglang/issues/<n>`）

**vLLM-Omni**
- 主 recipe：<https://github.com/vllm-project/vllm-omni/blob/main/recipes/MiniMaxAI/MiniMax-H3.md> · 2×24GB：<https://github.com/vllm-project/vllm-omni/blob/main/recipes/MiniMaxAI/MiniMax-H3-4090.md> · 2×32GB：`MiniMax-H3-5090.md` · 分离编码器：`MiniMax-H3-Disaggregated.md`
- 生产级 serving 博客（2026-09-01）：<https://vllm.ai/blog/2026-09-01-minimax-h3-production-serving>
- FP8/W8A8 支持矩阵：<https://docs.vllm.ai/projects/vllm-omni/en/v0.28.0/user_guide/quantization/fp8/>
- 关键 Issue/PR：#5799 · #6726 · #7564 · #5751（输入矩阵）· #5910 #6162（FP8/SVDQuant）· #6279（DLO+AllGather）· #6476 #6550 #6714 #6909（Turbo/DLO/FastH3/VSA）· #6872 #6885（chunkwise 输出）

**ComfyUI / 生态**
- 官方教程：<https://docs.comfy.org/tutorials/video/minimax/minimax-h3> · R2V/T2V 模板：<https://github.com/Comfy-Org/workflow_templates/tree/main/templates>
- Kernel/后端能力来源（本次核校 SM80 依据）：`comfy-kitchen` 能力矩阵与量化 layout 硬件门限 <https://github.com/Comfy-Org/comfy-kitchen>（README，PyPI 最新 0.2.37）· Sol-Attn 上游支持表（`SM80 | A100 | Triton`）<https://github.com/NVlabs/Sana/tree/sol-engine/techniques/sparse_backends>
- 训练：AI Toolkit 支持 H3 LoRA（<https://huggingface.co/ostris/minimax_h3_training_adapter>）、Kohya `networks.lora_minimax_h3`、fal 教程 <https://fal.ai/learn/devs/how-to-train-a-lora-for-minimax-h3>
- 蒸馏配套：<https://github.com/ModelTC/Minimax-H3-Turbo> · PDD 论文 arXiv:2607.26004 · VDN <https://openvdn.github.io/> · FastVideo <https://github.com/hao-ai-lab/FastVideo>
- 国内下载：`https://hf-mirror.com`（本机 `huggingface.co` 直连不通）；ModelScope `MiniMax/MiniMax-H3`、`FlashGen/Minimax-H3-4step-lora-flashgen`
- 中文资料（ComfyUI 路线/评测，非 A100 一手）：<https://docs.comfy.org/zh/tutorials/video/minimax/minimax-h3> · <https://zhuanlan.zhihu.com/p/2067683792849048257>（架构+部署综述，2026-08-03）· <https://1panel.cn/blog/minimax-h3-video-generation-deployment.html>（GB10 私有化实测，2026-08-23）· <https://developer.aliyun.com/article/1766123>（8G 显存整合包，2026-09-24）
- 第三方服务/评测参考：<https://fal.ai/minimax-h3> · <https://www.runpod.io/blog/minimax-h3-the-open-weight-omni-modal-video-model-and-what-it-takes-to-run-it> · <https://recipes.vllm.ai/MiniMaxAI/MiniMax-H3>

---

### 附：本报告未做实测的声明
除明确标注"实测"的数字（均来自官方文档/博客给出的测量）外，A100-40G 上的耗时均为**依据 4090/5090/H100/H200 锚点的推算**，误差可达 ±40%；SM80 上 `sol_attn`、W4A16/Marlin、`cube_sparse_attn`、vLLM-Omni `quality=high`、`CUDNN_ATTN` 属于"文档未明确禁止但无证据"，需你在目标机上跑一次峰值与画质验证。

---

## 9. 分阶段叠加路线（按你的实际硬件：4×A100-40G SXM，NV12 全互联，384 GiB 主机）

### 9.0 拓扑判读

`nvidia-smi topo -m` 的图例：`X`=自身（对角线）、`NV#`= bonded 的 # 条 NVLink、`PHB`= 经过 PCIe Host Bridge（通常是 GPU↔网卡/CPU 的路径）、`PXB/PIX/NODE/SYS` 才是各种纯 PCIe 路径。你看到 **`NV12`** 意味着 GPU 之间是 **12 条 NVLink 绑定 = 600 GB/s 全互联**（A100 SXM 的满配），所以我上一版报告里"PCIe 上 Ulysses all-to-all 代价极大"的顾虑对你不成立——**并行策略应当往 Ulysses/sequence-parallel 倾斜**，而不是像消费卡那样只能 TP。

> 只有一种情况例外：如果矩阵里某两枚 GPU 相交的格子是 `PHB`/`NODE`/`SYS` 而不是 `NV12`，就把 Ulysses 分组限制在 NVLink 互联的那几枚内（`CUDA_VISIBLE_DEVICES` 显式指定）。

384 GiB 主机内存 = vLLM-Omni DLO 的"200 GiB 可用 / 384 GiB 推荐"正好达标，SGLang 侧也不会再撞 #34902（每 rank 过 61.7 GiB）与 #38605（64 GiB 主机导致画面乱码）这类内存墙。

### 9.1 先纠一件事：FastH3 / VDN-H3 **不能**当你的第一步

你要求 Ref2VA，而这两个都明确拒绝 ref2va 请求：

- FastH3（4 步 DMD2 与 8 步 V2）："Only the T2VA capability was distilled: requests must use `task: "t2va"`, and **`fl2va` / `ref2va` requests are rejected**"；8 步 V2 同样写着 "This release supports T2VA only … Additional LoRA adapters, **Ref2VA and FL2VA conditioning are unsupported**"。
- VDN-H3："It is the **FL2VA partition**, so it serves `t2va` and `fl2va` … **`ref2va` is rejected**"。

它们还各带一条 SM80 相关的坏消息：FastH3 的加速主要来自 `video_sparse_attn_h3` / `FASTVIDEO_VSA`，而 VSA 内核是 **SM90/SM100/SM103**（A100 用不了，只能用 dense 后端跑它的蒸馏权重，收益打折）。VDN-H3 的 `hybrid_window_attn_h3` **官方明写 SM80 可跑**（"on SM80 / SM86 / SM89 the same FA3 build runs its Sm80 mainloop at FA2-class speed"），但同一句后面是 "Ampere and Ada are enabled but **not benchmarked**"。

→ **FastH3 / VDN-H3 属于"旁路高吞吐 T2VA/FL2VA 服务"（值得另占 2 卡），不是主线。主线的第一刀必须落在 Ref2VA 可用的四条上：AdaLN 在线（无损）、量化（INT8/W4A8）、PDD 8 步、LightX2V Ref2VA Turbo。**

### 9.2 必须先选的岔路：**无损省显存** 与 **剪枝/量化省显存** 互斥

同一块 AdaLN 显存只能走一条路：

| 路线 | 机制 | 画质 | 约束 |
|---|---|---|---|
| **无损**：`--minimax-h3-adaln-online true` | 把全宽 `adaln_proj`（**24.2 GiB**）从 GPU 摘掉，按请求在线重建，"bit-exact with the resident-weight path" | **逐位一致** | 只对**未量化的官方权重**有效（文档："Cache mode supports the matching unquantized checkpoint only"，在线模式要求目录里有原生 `adaln_proj`）；每个新的 `(形状, steps, flow_shift)` 组合首请求多花几秒；会改 `adaln_proj` 的 LoRA 被直接拒绝 |
| **近似**：pruned 权重（61.73→37.46 GiB） | 用 curve basis（`adaln_t_table`，1025×8）替换全宽 AdaLN 与 time embedder | **近似**，明确不在无损基线内 | 换来 19.53 GiB(INT8) / 11.68 GiB(W4A8) 的量级；而**剪枝后就没有 `adaln_proj` 可供在线重建** |

所以 Stage 1 与 Stage 3 不是叠加关系，而是**二选一的显存策略**。4×40G=160 GiB：走无损路线要靠 offload/FSDP 兜；走量化路线可以不 offload。

### 9.3 推进顺序（每阶段只改一个变量，每阶段留一组可比产物）

| 阶段 | 动作（相对上一阶段只改这一项） | 为什么排在这 | 期望收益 | 画质 | 判据 / 注意点 |
|---|---|---|---|---|---|
| **0 基线** | `sglang serve --model-variant ref2va --num-gpus 4 --ulysses-degree 4 --performance-mode speed`，50 步、`flow_shift 12`、`audio_flow_shift 3` | 先证明链路正确。**先做 13 个分片的 SHA256 校验**：#34110 的"雪花屏"根因就是权重损坏，不是框架 | 基准 | 基准 | 40G 卡这一步大概率 OOM；OOM 就进 Stage 1 |
| **1 显存（无损）** | 加 `--minimax-h3-adaln-online true`；卸载只给编码器：`--layerwise-offload-components text_encoder,vae`，并 `--layerwise-resident-layers video_vae=36` | 唯一"零画质代价"的大额收益：每卡 **−24.2 GiB**；`video_vae=36` 把解码从 60~209 s 压到 **~10 s 且逐位一致**（解码权重本就以 fp16 计算） | 能跑起来 + 解码快几倍 | **无损** | 同 seed 出片必须与 Stage 0 逐位一致，否则说明在线重建没生效 |
| **2 拓扑（无损）** | 4 卡 `--tp-size 2 --ulysses-degree 2`；2 卡 `--tp-size 2 --ulysses-degree 1`；保留 `--encoder-parallel auto`；补 `--warmup-resolutions 1344x768 --warmup-num-frames 124` | NV12 让 all-to-all 便宜；TP2+U2 是 4×H100 上**实测最快**的无损拓扑（13.25 s / 66.04 GiB 每卡）。默认预热按 1344×768×124，消费机上曾耗 7.6 min 启动，按你要服务的真实尺寸设更省 | 4 卡相对 2 卡 ≈ **1.6×** | 无损 | 用 `/v1/videos` 的计时头对比 Stage 1 |
| **3 量化**（第一次让画质，收益可测） | `--component-weights-paths.transformer <pruned_int8_convrot 19.53 GiB>` + `--component-weights-paths.text_encoder <qwen3vl int8_convrot 25.28 GiB>`；仍紧就下 **W4A8**（DiT 11.68 + 编码器 14.62） | 这步**替换** Stage 1（剪枝/量化后在线重建不再适用），换来"不必 offload、768p 可驻留" | 锚点：4090 上 BF16→`convrot_int8` **1.34×**（PSNR 24.81 dB）；50 步档 `kitchen_int8` **1.40×** | 可测（目标 PSNR ≥ 25 dB） | 先 `pip install comfy-kitchen`；**SGLang 必须 ≥2026-10-05 构建**（#40127：INT8 ConvRot 跳过 head-interleaved QKV 重排、**静默坏图**，09-18 开 10-05 关）；ConvRot/GGUF 与 FSDP 互斥；GGUF 不能配 LoRA；H3 256-group DiT 允许 TP1/2/4（**不支持 TP8**） |
| **4 步数**（最大杠杆；**4a/4b/4c/4d 四选一**，别与 Stage 5 的 cache 同开）〔2026-11-06 更新：新增 4d，并更正 PDD 请求步数〕 | **4d（首选）** `Pika-Labs/Pika-H3-Flex` 的 **ref2va 适配器，6 步**（`--model-path Pika-Labs/Pika-H3-Flex --model-variant ref2va`；请求 `num_inference_steps: 6`、不要合并适配器、不支持 `quality:"high"`）或 `FastVideo-FastH3-Omni-8-Step-V1`（8 步，overlay 自动融合 32→8 个头，A100 需 `--component-attention-backends transformer=fa`）<br>**4a** `alibaba-pai/MiniMax-H3-Acc-LoRAs` 的 **Ref2VA 8 步 PDD**（SGLang 正式流程：`build_minimax_h3_pdd_weights` + `fuse_minimax_h3_pdd_heads`；**请求已改为 steps=8** / 12 / 3 / `quality:"lossless"`，参数不符会被服务端拒绝）<br>**4b** 免融合的现成单文件：`PulpCut/MiniMax-H3-Ref2VA-Turbo-INT8-ConvRot`（Ref2VA + **8 passes**（作者口径，见 §10.3-4）+ INT8，19.53 GiB，**一举替掉 Stage 3+4a**）；`WarmBloodAban/...Singularity_ref2va_Pruned_v1.3_int8` + 作者推荐的 Ref2V Turbo LoRA 亦可（`--model-variant hybrid` 还能同时服务 t2va/fl2va/ref2va）<br>**4c** 不蒸馏：手动 `SGLANG_CACHE_DIT_*`（1.40× 锚点，SSIM 0.931）或 `--enable-spectrum --spectrum-warmup-steps 11 --spectrum-window-size 5 --spectrum-flex-window 1.0`（3.53× 锚点，但 **要求 SP=1** → 与 Stage 2 的 Ulysses2 冲突） | 官方稠密基线里 49/50 次前向就是主成本，减步数是唯一"数量级"级别的手段 | 50→8 步理论 6.25×；实测锚点 2×5090 从 559.67 s(50步) → 78.11 s(5步) = **7.2×** | 中→高 | ⚠️ Comfy 官方教程原话：4 步时"参考可能 barely applied"，主体姿态/脸部角度会随片长漂移 → **要跟参考紧的镜头保 20 步（必要时 25）**；音频比画面收敛慢，**8 步时人声最弱，12 步以上才可用**。〔11-06〕但注意 Pika 官方 ref2va 在 1×H200 上 6 步仍要 **260 s**（瓶颈是 packed 序列而非步数）→ **对白多的 Ref2VA 停在 6–8 步档，且优先治理参考素材数量/尺寸** |
| **5 注意力**（最后动，可叠在 3/4 之上） | 基线保持 `fa`；提速用 `--component-attention-backends text_encoder=torch_sdpa,transformer=sol_attn`（或 `sage_attn`） | A100 有可用内核：**Sol-Attn 上游支持表逐行写 `SM80 = A100 = Triton`**（其余 SM89/90/100/120 用 CuTe DSL），要求 CUDA ≥12.8、Triton ≥3.6、BF16、head dim 128；SageAttention 扩展覆盖 SM80/86/89/90/120；SpargeAttn 覆盖 SM80~90 | 锚点（4090、20 步、INT8 之上）：+sol **1.81×**、+sage 2.32×、Sage→Sol 混合 **2.48×**（PSNR 24.81→23.04 dB） | 高（改了注意力算法） | 一定用 `--component-attention-backends` 而不是全局 `--attention-backend`（#35743：某组件缺该 kernel 时**直接把服务打死**）。⚠️ H3 末层 block 的注意力 K 信号集中在少数通道，INT8 attention 会造成**片尾 morphing / 字幕乱码**；❌ SM80 不可用：`subblock_sparse_attn`、VSA、`TRTLLM_ATTN`、Skip-Softmax（仅 Hopper SM90 与 Blackwell SM100/103/107）、NVFP4/MXFP8 |
| **6 分辨率策略**（正交，随时可插） | 低分辨率去噪 + latent 超分：`LBH-123-AI/Minimax_h3_latent_Upscaler`（691 MB；vLLM-Omni `--additional-config` 指定路径 + 请求 `"latent_upscale":2.0`；SGLang 走 `minimax_h3_t2v_sgld_upscaler.json` 的 "Low-res then 3D ×2"） | 去噪成本随 token（≈像素）数超线性下降；训练过的 3D 卷积 resize 不产生 bilinear 的鬼影/双图 | 960×544 → 1920×1088 只解码一次 | 结构保留，细节靠放大 | 与 Stage 4 同开时，先在 8 步下确认放大没有把蒸馏伪影一起放大 |
| **7 旁路 T2VA 服务**（t2va 流量大才做） | 4 卡拆成 2+2：2 卡跑 VDN-H3（8 步，SM80 可用，需 `--quantization bf16` + `--layerwise-offload-components`）或 FastH3（用 dense `fa`，不带 VSA 标志即可跑），另 2 卡跑 Ref2VA 主力 | 两者都是服务级"拒绝 ref2va"的形态，天然适合独立部署 | — | — | 拆分后 Ref2VA 侧退化为 2 卡拓扑（TP2×U1） |

### 9.4 叠加 / 互斥矩阵（这就是"再叠加"的边界）

| 组合 | 关系 | 依据 |
|---|---|---|
| 量化(INT8/W4A8/W4A4/GGUF) × 蒸馏(LoRA/PDD/合并文件) × 注意力后端 × latent 超分 × TP/Ulysses × layerwise offload | ✅ **正交，可自由叠加** | 分别作用于权重、采样日程、kernel、分辨率、并行、放置 |
| AdaLN 在线（无损） × 量化/剪枝 | ❌ **二选一**（同一块显存的两条路线） | §9.2 |
| 少步蒸馏 × `quality="high"`/Cache-DiT | ⚠️ SGLang 明确不建议（"avoid stacking a distilled adapter with `quality: high`: both alter denoising, and that combination has not been quality-validated"）；vLLM-Omni 则写 "Turbo is independent of this quality switch"（可叠加但无标定数据） | 两框架口径冲突 → A100 上以你自己的 PSNR 为准 |
| Spectrum × Cache-DiT / quality=high | ❌ 互斥 | "On H3 it cannot combine with Cache-DiT / `quality="high"`" |
| Spectrum × SP>1（Ulysses≥2） | ❌ 互斥 → 想要 Spectrum 就 TP2×U1 | 同上 |
| TeaCache × Cache-DiT | ❌ 互斥（"pick one cache backend per server"）；且 **TeaCache 只标定过 FL2VA**，Ref2VA-only 服务直接拒绝 | vLLM-Omni recipe |
| Cache-DiT × FSDP | ❌ 互斥 | SGLang |
| Cache 加速 × `--step-execution` | ❌ step 模式下不可用 | vLLM-Omni |
| **`sampler:"res_multistep"` × 任何固定蒸馏 sigma 的 LoRA/checkpoint** | ❌ **服务端硬拒**（RES 未对蒸馏日程验证） | vLLM-Omni PR #8378（2026-10-04 合并） |
| ConvRot/GGUF/mixed/quanto × FSDP；GGUF × LoRA | ❌ 互斥 | SGLang 量化文档 |
| INT8 ConvRot 权重 × `comfy kitchen attention`（ComfyUI 侧） | ❌ 崩（对齐错误，#15529）→ 用默认注意力或 bf16 权重 | Comfy 教程 |
| CFG 并行 × 任何 | ➖ 无意义（CFG-distilled 单分支，多 rank 只是重复算同一分支） | 官方卡片 + SGLang |
| `--max-num-seqs>1`（co-batch）× 吞吐 | ➖ 反而更慢（2×H100：174.8 s → 182.1 s；均值劣化是因为同批一起完成） | vLLM-Omni recipe |

### 9.5 预期耗时（**推算**，锚点外推，误差 ±50%）

负载取 **1344×768 / 124 帧 / 5 s / 单输出**。A100-40G SXM 单卡稠密 BF16 ≈312 TFLOPS、带宽 1.555 TB/s（对比 4090 的 165/1.008、5090 的 ~210/1.79）。

| 配置 | 2×A100-40G | 4×A100-40G | 依据 |
|---|---|---|---|
| 无损 BF16 + AdaLN 在线 + offload，50 步 | **250–400 s** | **160–250 s** | 2×5090 同负载 559.67 s（且 5090 还在 PCIe 上流式权重） |
| + INT8/W4A8 量化，50 步 | 180–280 s | 115–180 s | 量化锚点 1.34–1.40× |
| + **8 步**（PDD / ref2v Turbo 8step） | **35–70 s** | **22–45 s** | 50/8 = 6.25×，扣掉固定的编码/解码/mux |
| + **4 步**（PulpCut Ref2VA-Turbo-INT8） | 25–50 s | 18–32 s | 2×5090 的 5 步 78.11 s 作下界参照 |
| 再叠 `sol_attn`/`sage_attn` | −30~45% | 同 | 4090 上 1.81~2.48× |
| **地板**（非去噪开销） | **≈15–25 s** | ≈10–18 s | Qwen 编码 3–5 s + 视频/音频 VAE 解码 5–10 s（`video_vae=36` 驻留后 ~10 s）+ 传输/H.264/AAC 3–5 s |

**怎么读这张表**：地板 15–25 s 意味着 4 步路线在 2×A100 上已经贴着这台机器的实用下限，再往下压步数（PDMD 2 NFE 那类）收益会被固定开销吃掉，而 Ref2VA 的参考贴合度和人声质量会先崩。**如果目标是"稳定可用 + 画质可接受"，建议终点停在 Stage 3 + Stage 4a（量化 + PDD 8 步）**，把 Stage 5（注意力近似）和 Stage 6（放大）当作对时延有硬指标时才动用的备用杠杆。

### 9.6 两套终态配置（可直接抄）

**A. 4×A100-40G · Ref2VA 主力（SGLang，量化编码器 + PDD 8 步）**

```bash
pip install comfy-kitchen   # W4A8/INT8 在 A100 上全靠它（ConvRot JIT 只覆盖 CC 9.0/10.0/12.0/12.1）

BASE=/models/MiniMax-H3/Ref2VA/transformer
PDD=/models/h3-ref2va-pdd
hf download alibaba-pai/MiniMax-H3-Acc-LoRAs MiniMax-H3-Ref2VA-Acc-8Step.safetensors --local-dir /models/h3-acc-loras

python3 -m sglang.multimodal_gen.tools.build_minimax_h3_pdd_weights \
  "$BASE" /models/h3-acc-loras/MiniMax-H3-Ref2VA-Acc-8Step.safetensors "$PDD"
python3 -m sglang.multimodal_gen.tools.fuse_minimax_h3_pdd_heads "$PDD" --video-shift 12.0 --audio-shift 3.0

SGLANG_DIFFUSION_MINIMAX_H3_PDD_HEADS="$PDD/pdd_fused_heads.safetensors" \
sglang serve --model-path MiniMaxAI/MiniMax-H3 --model-variant ref2va \
  --transformer-weights-path "$PDD/transformer" \
  --component-weights-paths.text_encoder \
    Winnougan/MiniMax-H3-INT4_Convrot_ComfyUI/qwen3vl_32b_minimax_h3-w4a8_convrot.safetensors \
  --num-gpus 4 --tp-size 2 --ulysses-degree 2 --encoder-parallel auto \
  --performance-mode memory --attention-backend fa --enable-torch-compile false \
  --warmup-resolutions 1344x768 --warmup-num-frames 124 --port 30011
```

请求：`"task":"ref2va"`、`"num_inference_steps":9`、`"flow_shift":12.0`、`"audio_flow_shift":3.0`、`"quality":"lossless"`（`pdd_config.json` 要和 `pdd_fused_heads.safetensors` 放在一起，且**不能**放进 `transformer/` 目录）。

> 关键取舍：**PDD 的主干是 BF16 融合产物**，所以配置 A 里量化只用在编码器上（W4A8 省 ~33 GiB，这是 2 卡/4 卡的真正瓶颈项）。若要把 DiT 也量化，就走 4b 的现成文件（`PulpCut/...turbo_int8_convrot.safetensors` 或 `Winnougan/...ref2va_pruned-w4a8...`），**4a/4b 二选一，不要同时**。

**B. 2×A100-40G · Ref2VA（vLLM-Omni，把 384 GiB 内存用满）**

```bash
export VLLM_WORKER_MULTIPROC_METHOD=spawn
export VLLM_OMNI_VIDEO_SYNC_TIMEOUT=14400

hf download lightx2v/Minimax-h3-Turbo \
  minimax_h3_ref2v_turbo_8step_v1.0_768p_bf16.safetensors --local-dir /models/turbo

CUDA_VISIBLE_DEVICES=0,1 vllm serve /models/MiniMax-H3/Ref2VA \
  --omni --trust-remote-code --host 0.0.0.0 --port 8000 \
  --task-type ref2va --served-model-name MiniMaxAI/MiniMax-H3 \
  --num-gpus 2 --tensor-parallel-size 2 --text-encoder-tp-size 2 --usp 1 --ring 1 \
  --vae-patch-parallel-size 2 --vae-parallel-mode tile --vae-use-tiling \
  --enable-distributed-layerwise-offload --dlo-no-use-allgather --dlo-resident-layers 24 \
  --enforce-eager --diffusion-attention-backend FLASH_ATTN \
  --lora-backend peft --lora-path /models/turbo/minimax_h3_ref2v_turbo_8step_v1.0_768p_bf16.safetensors
```

请求：`-F num_inference_steps=9 -F flow_shift=6`，`-F 'extra_params={"task":"ref2va","duration":5,"audio_flow_shift":3.0}'`，并在 `-F 'lora={...}'` 里带上同一个 `path`（文件名即契约：`8step_v1.0_768p` → steps 9 / shift 6 / α 8；写错会被拒）。

> 与 A 的分工：B 的价值在于**官方支持的 Ref2VA Turbo（请求级切换、不用离线融合）**+ DLO 成熟；A 的价值在于量化格式生态 + PDD。`--dlo-resident-layers` 从 4090 档的 12、5090 档的 20 往上抬到 24–28，逐档记 `x-peak-memory-mb`。若 `cudaHostRegister` 卡死（vllm-omni#6726，09-19 已修），临时加 `--dlo-host-registration-limit-gib=1`。

**C. 如果只允许做一件事**：先上 **Stage 1（AdaLN 在线 + video_vae=36）**——它无损、免费、且是 40G 卡能否装下 768p 的先决条件；然后再决定是否进量化。

---

## 10. 少步数蒸馏 / 加速 checkpoint 横评（含我上一版漏掉的 SoL-Refiner）

### 10.0 先补正：`Sol-H3` = NVlabs **SoL-Refiner**（不是 H3 的蒸馏版）

你说的那个是 **SoL-Refiner: Speed-of-Light One-Step Refinement for High-Resolution Video**，来自 **NVIDIA NVlabs（Sana 组）**，项目页 <https://nvlabs.github.io/Sana/Sol-Refiner/>；**MiniMax-H3 专用权重**由 Efficient-Large-Model 发布：
`Efficient-Large-Model/SoL-Refiner-LTX-2.5-for-MiniMax-H3`（**2026-09-28**，diffusers `SoLRefinerH3Pipeline`，diffusers 0.41.0.dev0）。

它跟"少步蒸馏"是**两个不同的轴**，不要混为一谈：

| 维度 | SoL-Refiner（H3 版） | 少步蒸馏（Turbo/PDD/FastH3…） |
|---|---|---|
| 干什么 | 把 H3 的**低分辨率草稿**一步精修成高分辨率（官方口径 **4K**） | 把 H3 自己的 50 步去噪压到 4–8 步 |
| 底座 | **LTX-2.5 22B**（`LTX2VideoTransformer3DModel` + Gemma 4 12B 编码器 + LTX-2.5 x2 latent upsampler + NVlabs 改过的 diffusion decoder），**不是 H3 的 33B DiT** | 就是 H3 的 DiT |
| 步数 | **1 步**（re-noise 到 `sigma=0.909375`，一步去噪，**无 CFG**） | 4–8 次 DiT 前向 |
| 官方实测（GB200） | 单卡直出高分辨率 H3 = **152.3 s**；两阶段（Stage1 896×512 = 4.06 s + 一步精修 = 1.56 s）= **5.64 s，27.03×** | 8×B300：base 50 步 25.8/26.4 s → FastH3 4 步 **11.7/11.8 s**（去噪 6.9×，但端到端只 2.2×） |
| 体积 | bf16 全套 ≈ **65.9 GiB**（transformer 35.37 + Gemma4-12B 22.28 + connectors 5.91 + 上采样器 0.93 + diffusion decoder 0.78 + VAE 0.59）；**int8-convrot 改版 ≈ 38.5 GiB**（transformer 21.90 + 编码器 14.32 + VAE/decoder 1.37 + 上采样器 0.93） | LoRA 0.7–2.6 GiB；合并版单文件 19.5–31.7 GiB |
| **A100-40G** | ⚠️ int8-convrot 版体积够小（≈38.5 GiB，transformer 里 1344 个 block Linear 走 int8 ConvRot g256 per-row，connectors/gate/adaLN/嵌入保持 bf16），但**量化内核是 image-server 自己的 `image_server_kernels.int8_linear`**，且 **SGLang / vLLM-Omni 文档都没有集成 SoL-Refiner**（我 grep 过两份文档：0 命中）→ 只能作为 diffusers `SoLRefinerH3Pipeline` 或 ComfyUI/image-server 的**独立二级阶段**跑，不能塞进 agent 服务里 | 见 §10.2 |
| 许可 | ⚠️ **双许可**：LTX-2 Community License（Lightricks）叠加 MiniMax H3 Community License | MiniMax H3 Community License 为主（LightX2V/PMDM 的 LoRA 标 apache-2.0，但派生仍受底座约束） |
| 关键限制 | **输出只有画面、没有音频** → 精修后要把 H3 自己那条 32 kHz 立体声轨重新 mux 回去；`frame_rate` 取输入 fps（H3=24） | 见下 |

**为什么它对你重要**：官方 `H3-Regenerate-2K` 没有开源（只有 API），所以"低分辨率草稿 → 一步精修到 1080p/4K"曾是唯一开放的高分辨率廉价路径，而且它**与所有少步方案正交可叠加**（它跑在 H3 之后、是另一个模型）。代价是新增 38.5–65.9 GiB 权重 + 一条独立 pipeline。
> 〔2026-11-06 重要更新〕这条"唯一"已被打破：**`Efficient-Large-Model/Open-H3-Regenerate-2K`（2026-10-26）用 H3 本体 + 合并 LoRA 做 3 步 768p→2560×1440 再生成，只额外需要 ≈14 GB，保留草稿音轨，单一 MiniMax 许可，且 vLLM-Omni 已有官方 recipe**。对 Ref2VA 生产线它现在是**优先项**，SoL-Refiner 降为"追求 4K/更省一步"的备选。详见 §12.3。

### 10.1 少步蒸馏家族总表（按"Ref2VA 能不能用"分层）

图例：**任务**列 `R`=ref2va、`F`=fl2va、`T`=t2va。日期=HF `createdAt`。

**第一梯队：Ref2VA 可用（你的主线候选）** 〔2026-11-06 更新：新增行 0a / 0b，它们现已是"SGLang 一等支持"的 Ref2VA 少步首选，1–6 行保留〕

| # | 仓库 | 方法 | NFE | 任务 | 形态/体积 | 首发 | 加载方式 | A100 |
|---|---|---|---|---|---|---|---|---|
| **0a** | **[Pika-Labs/Pika-H3-Flex](https://huggingface.co/Pika-Labs/Pika-H3-Flex)**〔2026-11-06〕 | H3 后训练 + **固定 6 步 re-noising**（knots `1000/750/500/250/100/40`，shift 12/3） | **6** | **R + F（含 t2va/i2va/l2va）** | FP32 PEFT LoRA rank/α128，**各 2.58 GiB**（Comfy BF16 各 1.82 GiB），overlay 只下 ≈5.5 GB 并校验 sha256 | 2026-10-29 | **SGLang 一等支持**：`--model-path Pika-Labs/Pika-H3-Flex [--model-variant ref2va]`，请求**只接受 `num_inference_steps: 6`**；不许 `--lora-path` 替换、**不支持 `quality:"high"`**、**适配器保持未合并**（BF16 merge 会削掉约 1/3 更新量） | ✅（未验证与量化基座共存） |
| **0b** | **[FastVideo/FastVideo-FastH3-Omni-8-Step-V1](https://huggingface.co/FastVideo/FastVideo-FastH3-Omni-8-Step-V1)**〔2026-11-06〕 | **PDD**（Ref2VA 分区），8 次去噪 / 32 区间网格 | **8** | **仅 R** | overlay 自动把 32 个区间头**融合成 8 个逐步头**，并链接 pinned Ref2VA 的 TE/VAE | 2026-10-05 | `--model-path` 直 serve；默认 steps=8、clean references（cond-noise-aug 1.0） | ⚠️ **VSA-H3 内核只有 SM100/SM103(tcgen05) 与 SM90(Triton tile-64)，SM80 无** → A100 要 `--component-attention-backends transformer=fa`（4×H200 上 dense FA 比 VSA 慢约 25%） |
| 1 | [alibaba-pai/MiniMax-H3-Acc-LoRAs](https://huggingface.co/alibaba-pai/MiniMax-H3-Acc-LoRAs) | **PDD**（Parallel Decoding Distillation，arXiv:2607.26004） | **8** | **R + F + T** | LoRA `rank=64 / alpha=64` BF16，**1.28 GiB**，FL2VA 与 Ref2VA 各一个文件 | 2026-08-26 | SGLang **正式流程**：`build_minimax_h3_pdd_weights` 离线合主干 + `fuse_minimax_h3_pdd_heads` 融合 32 个分区输出头；或 VideoX-Fun `apply_pdd_lora`（diffusers ≥0.40） | ✅ |
| 2 | [lightx2v/Minimax-h3-Turbo](https://huggingface.co/lightx2v/Minimax-h3-Turbo) | Turbo（DMD 类），Apache-2.0 | **4 / 8** | **R + F + T** | LoRA rank128，1.29 GiB（+ `ref2v` 4step v0.1、8step v1.0 768p；另有 FL2VA 的 merged **fp8 31.69 GiB**） | 2026-08-07 | vLLM-Omni **官方支持表**（`--lora-backend peft --lora-path <文件>`，请求级切换，**不需离线融合**）；SGLang 有 LoRA 流程但 Ref2VA 文件"尚未成为 pinned 配方" | ✅ |
| 3 | [drbaph/MiniMax-H3-Turbo-Lora-ComfyUI](https://huggingface.co/drbaph/MiniMax-H3-Turbo-Lora-ComfyUI) 内的 **HyperFlow 8-step** | HyperFlow | **8** | **R + F + T**（**这是仓库自述**，README："designed for the MiniMax-H3 T2VA, FL2VA and Ref2VA workflows"；**框架侧无标定、社区无 A100 记录**） | 全量 bf16 + **rank-20 resized** + **pruned/curve 版**各一套（上游用固定 8 步 sigma 日程，转换后给了手工 sigma 序列；`pruned` 文件只能配 pruned 基座） | 2026-08-06（HyperFlow 段为其后更新） | ComfyUI LoRA；DeepBeepMeep 也有 `minimax_h3_hyperflow_8step_v1.0.safetensors`（2.60 GiB） | ✅（rank 越小越省显存、越掉细节） |
| 4 | [PulpCut/MiniMax-H3-Ref2VA-Turbo-INT8-ConvRot](https://huggingface.co/PulpCut/MiniMax-H3-Ref2VA-Turbo-INT8-ConvRot) | **作者自己把步数蒸馏做到 Ref2VA 权重上**（原话："Every published turbo LoRA for MiniMax H3 targets the **FL2VA** transformer"）+ pruned + **INT8 ConvRot** 合并成单文件 | **8**（作者："Recommended settings: **8 denoising passes**, euler sampling, all 50 blocks"；并说明 **不用 4 步** 的原因见 §10.3-4） | **R** | **单文件 19.53 GiB**（drop-in 替换 `minimax_h3_ref2va_pruned_int8_convrot`）；README 还提到一个按下载量默认的 overlay，"the same file supports both FL2VA variants" | 2026-08-15 | SGLang `--component-weights-paths.transformer OWNER/REPO/FILE.safetensors`；⚠️ 别拿 `*_input_major.safetensors`（H3ddle/macOS 专用，"not compatible with runtimes that assume the original output-major Comfy layout"） | ✅ comfy-kitchen（Turing+）。作者实测 A/B：regular Ref2VA INT8 **20 passes = 49.0 min** vs Turbo Ref2VA INT8 **8 passes = 20.2 min**（**2.43×**） |
| 5 | [MATLOWAI/minimax-h3-fused-turbo-int8-convrot](https://huggingface.co/MATLOWAI/minimax-h3-fused-turbo-int8-convrot) | **一个文件干两件事**：pruned `fl2va` + `(ref2va−fl2va)` 权重差的 **rank-1024 SVD** 融合 + lightx2v turbo-8(rank-24 resize) + Mystic 风格 @0.7，**merge 后一次 INT8 ConvRot** | **4** | **R + F + T** | 单文件 ≈19.5 GiB（README 写 "21 GB"，十进制） | 2026-08-29 | ComfyUI `diffusion_models/`；实测锚点：**1152×640 × 243 帧（10 s）4 步 = 76 s**（1×RTX PRO 6000 96 GB，SLA 稀疏注意力） | ✅ INT8；⚠️ 那个 76 s 锚点里含 **SLA 稀疏注意力**——SGLang 侧 `sla`/`sage_sl2` 依赖 SpargeAttn（"CUDA SM80/86/87/89/90"，A100 在范围内），但 Comfy 侧的 SLA 实现是另一套，别把这条时延直接搬到 A100+SGLang |
| 6 | [WarmBloodAban/Minimax-h3_Singularity](https://huggingface.co/WarmBloodAban/Minimax-h3_Singularity) v1.3 | FL/Ref **融合微调**（不是蒸馏），作者另推荐 Ref2V Turbo LoRA 搭配 | 50（或配 Turbo） | **R + F + T 一套管线** | pruned_int8 **19.53** / int8 31.67 / pruned_**w4a8** 10.96 GiB | 2026-09-05（v1.3 更新 09-18） | SGLang `--model-variant hybrid` + `--component-weights-paths.transformer`；W4A8 走 SM80+ 路径 | ✅ |

**第二梯队：只有 T2VA / FL2VA（`ref2va` 被拒），做旁路高吞吐服务**

| 仓库 | 方法 | NFE | 任务 | 关键点 | 首发 | A100 |
|---|---|---|---|---|---|---|
| [FastVideo/FastVideo-FastH3-4-step-Preview-v1-VSA-DataFree](https://huggingface.co/FastVideo/FastVideo-FastH3-4-step-Preview-v1-VSA-DataFree) | **DMD2**（NVIDIA FastGen 团队提供框架）**data-free** + VSA-H3 **90% 稀疏**，step-1300 | **4**（SGLang 写 5 个 sigma 点 / vLLM-Omni 写 4） | **仅 T** | 官方自己标注 preview："Difficult motion, fine detail, and some audio may remain below…" | 2026-08-27 | ⚠️ 权重可跑 dense `fa`；**VSA 内核是 SM90/100/103，A100 用不到它的主要加速来源** |
| [FastVideo/FastVideo-FastH3-8-Step-V2](https://huggingface.co/FastVideo/FastVideo-FastH3-8-Step-V2) | DMD2 data-free + VSA-H3 **80% 稀疏**，全量 Diffusers transformer（含学习到的压缩门控） | **8**（steps=8，日程不位移 `[0.999…0]`） | **仅 T** | ⚠️ **video shift 10 而非 12**、guidance 1、`audio_flow_shift=3`；"requires FastVideo's VSA-H3 attention backend" | 2026-09-04 | ❌ 同上，且更强绑定 VSA |
| [OpenVDN/vdn-minimax-h3](https://huggingface.co/OpenVDN/vdn-minimax-h3) | **混合注意力**（滑窗 softmax + Video DeltaNet 线性分支，arXiv:2609.20744）**+ 8 步 DMD2 LoRA** | **8**（steps=9） | **T + F**，另有 **Ref2VA-like**（2026-09-17 起，见下行） | 加 4.3 GB 线性分支，`stage-dmd-step-250` 共 5.1 GB；训练+推理代码全开源；官方 **8×B200：14.4 s 片段端到端 ~9.0 s（去噪 6.9 s）**；24 GB 卡可 `--offload_dit`（345 帧峰值 22 GB / fp8 20 GB） | 2026-09-02 | ✅ **SGLang 文档明写 SM80 可跑**（FA3 的 Sm80 mainloop，FA2 级速度），但 "Ampere … not benchmarked"；MXFP8 在 SM80 退 bf16。**⚠️ Ref2VA-like ≠ Ref2VA**：上游原话 "Generation still uses the **FL2VA weights** rather than MiniMax-H3's separate Ref2VA transformer, which is why we describe this mode as Ref2VA-like rather than Ref2VA proper"（参考图以 `<Picture i>` 进入 FL2VA 的条件行）；而 **SGLang 的 VDN 服务契约仍拒绝 `task:"ref2va"`**，所以这条只在自建推理栈里成立，不能进你的 agent 服务 |
| [larryvrh/MiniMax-H3-Turbo-Lora](https://huggingface.co/larryvrh/MiniMax-H3-Turbo-Lora) | Turbo LoRA（DMD 类） | **4–8**（推荐 6–8） | **T + F** | 0.73 GiB，`W_eff=W+B@A`，alpha=rank；**画质说明最诚实的一份**：v4-600 在 4 步快动作下会 motion-smear/拖影（v1-850 更适合"4 步+大幅运动"），**超过 8 步会过锐、无收益**；strength 保持 1.0；`--offload-adaln` 用 CPU 内存换 ~13 GB 显存；音频与剧烈运动仍在改进 | 2026-08-05 | ✅ |
| [pdmd2026/pdmd_2NFE_lora](https://huggingface.co/pdmd2026/pdmd_2NFE_lora) / [pdmd_4NFE_lora](https://huggingface.co/pdmd2026/pdmd_4NFE_lora) | **PDMD**（Projected Distribution Matching Distillation，arXiv:2609.35768）：把 DMD 更新投影到与 student–critic endpoint residual 正交的子空间，"一行改动，无辅助损失/额外网络/额外前向" | **2** / 4 | **T**（FL2VA 分区） | rank128/alpha128，312 对 LoRA，bf16 1.38 GB（另有 fp32 2.77 GB）；**2-NFE 推荐 audio time shift 6**（论文指标用 3），**4-NFE 用基模发布的 12/3**；另有全量版 `pdmd2026/pdmd_4NFE_full`；需自己按脚本 fuse 进 base transformer（`W += scale·B@A`，scale=α/rank=1.0） | 2026-09-23 / 09-29 | ✅（但 2 步画质风险最高，且社区无 A100 记录） |
| [Efficient-Large-Model/LongLive-Plug-MiniMax-H3-few-step](https://huggingface.co/Efficient-Large-Model/LongLive-Plug-MiniMax-H3-few-step) | few-step plug-in（LongLive 系） | few | T/F | 卡片明确要求 **few-step LoRA 与 CFG LoRA 分开跑**，不要叠 | 2026-09-29 | ⚠️ 无框架侧记录 |
| [mvp-lab/MiniMax-H3-RAVEN-Streaming-LoRA](https://huggingface.co/mvp-lab/MiniMax-H3-RAVEN-Streaming-LoRA) | **因果流式**蒸馏（arXiv:2605.15190） | 4 | 长视频流式 | 5.1 GB；宣称 24 GiB 跑 192×1376×768 | 2026-08-18 | ❌ SGLang 明确："causal-streaming adapters such as RAVEN also require their matching … pipeline; **they are not standard H3 LoRA overlays in SGLang**" |
| [FlashGen/Minimax-H3-4step-lora-flashgen](https://modelscope.cn/models/FlashGen/Minimax-H3-4step-lora-flashgen)（**ModelScope**） | FlashGen 原生布局，**sigma 日程写在 safetensors metadata**（`base_schedule=1.0,0.7,0.4,0.15,0.0`） | **4**（此处 steps=4 就是 4 次前向，**不是** 5 个 sigma 点） | **仅 T**（"This path rejects Ref2VA"） | rank **64** over 259 个目标模块；打包 `qkv_proj`/`fc1` 复用整输入 A 张量 → **驻留显存大于磁盘体积**，需实测 | — | ✅ vLLM-Omni 官方路径（`--lora-backend peft`），DLO 在 request 模式下支持 |

### 10.2 五个推荐（针对 4×A100-40G + 必须 Ref2VA）

| 排序 | 选谁 | 为什么 | 上手指法 | 主要风险 |
|---|---|---|---|---|
| **① 主力**〔2026-11-06 改推荐〕 | **首选 Pika H3 Flex 的 `ref2va` 适配器（6 步）**；次选 **FastH3-Omni-8-Step-V1**（8 步）；再退到 **alibaba-pai PDD 8-step（Ref2VA 文件）** | 前两者已是 **SGLang 一等支持**且**不需要手工离线融合**（PDD 要跑 `build_minimax_h3_pdd_weights` + `fuse_minimax_h3_pdd_heads`；FastH3-Omni 的 32→8 头融合由 overlay 自动完成）。PDD 那侧仍有一张好牌：README 给了 **baseline vs 4-step turbo vs Acc-8Step 的三列对照视频**（FL2VA 与 Ref2VA 都有），可以目测 | Pika：`sglang serve --model-path Pika-Labs/Pika-H3-Flex --model-variant ref2va`，请求 `num_inference_steps: 6`（其它值拒绝）、省略 shift 保持 12/3、`--lora-merge-mode dynamic`（不要合并）。FastH3-Omni：`--model-path FastVideo/FastVideo-FastH3-Omni-8-Step-V1 --num-gpus 2 --ulysses-degree 2`，A100 上再加 `--component-attention-backends transformer=fa` | ⚠️ Pika 官方 1×H200 的 **ref2va（2 图+1 带音频视频）= 260 s**，且明确"Most of the ref2va time goes to its long packed sequence" → **6 步没把 Ref2VA 变成实时任务**，杠杆在参考素材治理。Pika **不支持 `quality:"high"`**、适配器不许 BF16 合并（会削掉约 1/3 更新量）；FastH3-Omni 在 A100 上拿不到 VSA 收益 |
| **② 免融合替代** | **LightX2V ref2v Turbo（8step v1.0 768p 优先）** | vLLM-Omni **官方支持的两行 Ref2VA 蒸馏**，请求级切换、零预处理；Apache-2.0；LightX2V Studio 线上用的就是 8step v1.0 768p（说明官方也认为 8 步比 4 步稳） | §9.6 配置 B；`8step_v1.0_768p` → steps=9 / **flow_shift=6** / α=8 | ⚠️ **必须用 Diffusers 布局文件**，`_comfyui_` 导出被按名字拒绝；目录里塞多个文件会被判"歧义"拒绝；SGLang 侧该文件未被 pin |
| **③ 显存杀手** | **PulpCut Ref2VA-Turbo-INT8-ConvRot**（或 MATLOWAI 融合版） | 一个 19.53 GiB 文件同时解决"量化+蒸馏+Ref2VA"，2×A100 也能让 DiT **驻留不 offload**；SGLang 有明确加载行 | `--component-weights-paths.transformer PulpCut/…/minimax_h3_ref2va_pruned_turbo_int8_convrot.safetensors`，按作者口径 **8 次去噪**（SGLang 请求写 `num_inference_steps: 9`；SGLang 文档明确"存储格式检测不会推断采样行为"，**NFE/日程要自己 pin 并实测**） | 步数口径**没有框架侧标定**（作者给的是 Comfy 口径 8 passes）；INT8 ConvRot 的 **QKV 重排 bug 到 2026-10-05 才修**，必须新构建 + 同 seed PSNR 回归；`input_major` 变体不能用；**它是 pruned 基座 → 不能再叠 AdaLN 在线** |
| **④ 高分辨率杠杆**〔2026-11-06 换成首选 Open-H3-Regenerate-2K〕 | **首选 `Efficient-Large-Model/Open-H3-Regenerate-2K`（3 步，768p 草稿 → 2560×1440）**；SoL-Refiner 退为"要 4K / 要单步"时的备选 | Regen-2K 用 **H3 本体 + 合并 LoRA**（Open-H3 refiner + LightX2V FL2VA Turbo + LMS Sharp），只额外 **≈14 GB**、**保留草稿音轨**、单一 MiniMax 许可，且 **vLLM-Omni 已能作为独立部署服务它**（PR #9562，11-02） | vLLM-Omni：请求带 `source_video` + `extra_params={"task":"t2va","regenerate":true}`，`latent_upscale` 默认 `{2560,1440,align:32}`；可 2 步（sigmas 0.7/0.494）；**拒绝** `flow_shift`/`sampler`/`latent_refine`/per-request `lora` | **它是独立服务**："every request on this server is a regenerate request" → 4 卡机器上主生成与 2K 再生**不能同卡共存**；release 的 `sharp_curve_branches` up 因子全 0（不贡献）；SoL 那条仍是双许可 + 输出无音频 |
| **⑤ 旁路（若 t2va/fl2va 量大）** | **VDN-H3**（不是 FastH3） | 同样 8 步，但**架构级**提速（线性分支替代长程稠密注意力）且**官方文档确认 SM80 可跑**；FastH3 的收益绑在 VSA（SM90+）上，A100 拿不到 | `--model-path OpenVDN/vdn-minimax-h3 --attention-backend hybrid_window_attn_h3 --quantization bf16 --layerwise-offload-components text_encoder` | **SGLang 侧拒绝 `ref2va` 请求**（上游 2026-09-17 的 "Ref2VA-like" 是自建推理栈里用 FL2VA 权重零样本吃参考图，**不等于 Ref2VA 分区**）；首启要 fuse（写 62 GiB，需 90 GiB+ 空闲缓存目录）；A100 无 benchmark；与 `quality=high`/ring>1/torch.compile 互斥 |

**不推荐在你机器上作为主线**：FastH3（仅 t2va + VSA 依赖 SM90+）、RAVEN（需要配套流式管线）、PDMD 2-NFE（步数激进 + 需自写 fuse，且没有 A100 记录）、NVFP4/MXFP8 化的蒸馏文件（`LoboForge`、`pottokao` 那些 FastH3-NVFP4 转换，SM100+ 才能算）。

### 10.2b 交叉核对后新增的少步 / 采样器资产（已核实，非转述）

| 资产 | 类型 | 核实结果 | 对你的意义 |
|---|---|---|---|
| **DMAD** — 代码 `Yzmblog/DMAD`（**Apache-2.0**，created 2026-09-29，pushed 2026-10-08，114★）；**权重 `ZhengmingYu/DMAD`（created 2026-10-02，81 likes）** | 分布匹配=对抗蒸馏，50 步 teacher → **4 步** student，**rank128 / α128，312 个模块**；产物：`dmad_minimax_h3_4step_lora_critic.safetensors`（论文版，critic 冻结在 LoRA 下，EMA@iter800，1.4 GB）与 `..._full_critic.safetensors`（critic 全训，@iter1600，AVGen-Bench 更高，1.4 GB），**另有两张官方 ComfyUI key-layout 精确转换（各 2.0 GB）**；人类偏好 **vs DMD2 79.1%、vs rCM 84.6%**；官方 **H200 37 s/video** | 仓库/许可/文件清单已由 GitHub + hf-mirror API 核实 | ⚠️ **不是 drop-in**：官方 4 步口径是 **time shift 12（视频）/ 2（音频）、无 CFG、124 帧**，且强调"the paper used (re-noise step rule)"——**Diffusers 管道走 Euler 规则，产出与论文不同**。⚠️ **"支持 REF2VA" 只出现在第三方 rank-39 重排版的说明里**（`Kijai/MiniMax-H3-experimental` → `minimax_h3_DMAD_4step_full_lora_avg_rank_39_bf16.safetensors`，0.34 GiB，文件已核实存在）；上游 README 只说 "Rank-128 LoRAs on **the H3 transformer**"（即 FL2VA 分区）→ **Ref2VA 用途按"未验证"处理**。它的价值更像"比 DMD2/rCM 更被认可的蒸馏目标函数"，可作为后续自训/评测基准 |
| **VEDA / `veda-sparse/Miowtion`** | 训练无关块稀疏（275M predictor 给 query/key tile 打分）+ 8NFE 预览 | 按其描述核实；**关键更正：7.1× 是注意力单项，端到端 2.9×**；SM8x 路径"A100 能否吃到属待实测" | ⚠️ **已发布 predictor 只有 T2VA，Ref2VA 官方 benchmark 明确 out-of-scope** → 现在不能算你的可用方案；但它那句"**下一个瓶颈是 H2D 拷贝与 VAE 解码，不是注意力**"应当写进你的诊断流程 |
| **vLLM-Omni `res_multistep` 采样器** | 二阶多步（视频+音频两条流，per-request） | **PR #8378 已合并（2026-10-04）**；1×H100、672×384、124 帧：Euler-50 **64.65 s** → RES-20 **27.50 s = 2.35×**，LPIPS **0.1190** / CLAP **0.9741** | ⚠️ **与所有固定蒸馏 sigma 的产物硬互斥**（原文："…with a fixed distilled sigma schedule **remain restricted to Euler** because RES has not been validated with those schedules"，服务端会报错）。定位：**不挂蒸馏时的 2.35× 档**，别为它放弃蒸馏 |

### 10.3 四个会咬人的口径陷阱

1. **"steps" 的含义按产物不同，且 10-08→11-06 之间变过一次**〔2026-11-06 更正〕。旧规则"SGLang 写 sigma 点数（8 步写 9）"**已不适用**：SGLang 现版对 PDD 的请求值从 `num_inference_steps: 9` 改成 `8`，而解释句"nine sigma grid points give eight denoiser evaluations"原样保留 → 说明这是**逐产物**的契约，不能靠通用规则推。现版实测口径（照抄前先核对）：

   | 产物 | SGLang 请求 | vLLM-Omni 请求 |
   |---|---|---|
   | PDD 8 步 | **8** | — |
   | FastH3 8-Step V2 | **8** | **8**（shift 10/3，guidance 1） |
   | FastH3-Omni 8 步（Ref2VA） | **8**（默认） | — |
   | **Pika H3 Flex** | **6**（且只接受 6） | **不支持**（recipe 0 次提及） |
   | VDN-H3 | **9** | 8（`--lora-path` 路径） |
   | LightX2V ref2v Turbo 8step v1.0 768p | 旧文档写 9（新文档未 pin） | **9**，`flow_shift=6` |
   | DMAD 4 步 | — | 5（=4 次评估） |
   | FlashGen 4 步 | — | **4**（metadata `base_schedule` 有 5 个 knots） |

   → 落地纪律：**每个 checkpoint 的 steps/shift/quality 都从它自己的一手文档抄，并把请求体与产物一起 pin**；改框架等于改数字。
2. **蒸馏基座与 pruned/full 必须配对**：Comfy 官方教程原话——在 full 基座上训的 LoRA 带了 pruned 基座里没有的 adaln 张量，"ComfyUI reports a shape mismatch for them and does not merge them, so that part of the LoRA is skipped"（**静默丢掉一部分 LoRA**）。drbaph 因此给每个 LoRA 都发了 `pruned` 与 full 两套。选文件时对齐基座类型。
3. **flow shift 是蒸馏契约的一部分**：LightX2V FL2VA 4step v1.0/v1.1 用 shift **6**，v0.1 与 8step_v1.0(544p) 用 **12**；FastH3-8-Step-V2 用 **10**；PDD 必须 **12/3**；PDMD 2-NFE 建议把 **audio shift 从 3 改成 6**（4-NFE 仍用 12/3）；DMAD 用 **12/2**。写错 shift 不会报错，会**悄悄出坏片**（vLLM-Omni 只对 FastH3 做了"请求覆盖 shift 就拒绝"的保护）。
4. **绝大多数少步产物是"FL2VA 基座"，而且 pruned 转换会丢 AdaLN 因子 → 4 步最先坏的就是它**。PulpCut 作者原话："Every published turbo LoRA for MiniMax H3 targets the **FL2VA** transformer"，并给出机制解释："The pruned ComfyUI conversion of the turbo LoRA **drops all 51 AdaLN adapter** [tensors] … **four-step distillation behaviour may therefore be degraded. We use 8 passes rather than 4 for that reason**"（并链到 ModelTC/Minimax-H3-Turbo#7）。这与 Comfy 官方教程的告警同源：full 基座训出的 LoRA 挂到 pruned 基座上，adaln 部分会**因 shape 不匹配被静默跳过**。
   → 三条实操结论：**(a)** 要 Ref2VA 少步，优先选"明确做在 Ref2VA 权重上"的产物（PDD Ref2VA 文件、LightX2V `ref2v_*`、PulpCut）而不是把 FL2VA LoRA 硬挂上去；**(b)** 选文件时同时锁定 **基座类型（full/pruned）× 分区（FL/Ref）× 步数**，三者任一不对齐都可能悄悄降级；**(c)** 在 Ref2VA 上 **8 步比 4 步稳**（再叠加"参考 token 每步都参与、4 步时 barely applied"的社区观测）。

---

## 11. 与《MiniMax-H3 加速与量化最新调研 2026-10》的交叉核对

> 被核对文件：`D:\WorkBuddy-Workspace\Video-Generation\MiniMax-H3_加速与量化最新调研_2026-10.md`（自称第三份调研，路线约束为**不用 ComfyUI、只做 vLLM-Omni 云端服务**，并给出用户自测基线 **5s/768p/50 步 ≈ 820 s、峰值 39 GB、已卸载部分层 ≈ 16.4 s/步**，基线日期 2026-09-14）。
> 本节所有"已核实"都是我这一轮**直接查 API/原文**得到的，不是转述。

### 11.1 它抓到、我上一版漏掉的（采纳，已核实）

| 项 | 核实方式与结果 | 影响 |
|---|---|---|
| **vLLM-Omni `res_multistep` 采样器** | PR **#8378 已合并**（`merged_at=2026-10-04T07:26:19Z`）。原文照录："**Checkpoint or adapter configurations with a fixed distilled sigma schedule remain restricted to Euler because RES has not been validated with those schedules.**"；实测 1×H100、672×384、124 帧、T2VA：Euler-50 **64.65 s** → RES-20 **27.50 s = 2.35×**，视频 **LPIPS 0.1190**、音频 **CLAP 0.9741** | ✅ **我 §9.4 的叠加矩阵缺了这一整根轴**，必须补：`sampler=res_multistep` ↔ 任何固定蒸馏 sigma 的 LoRA/checkpoint = **硬互斥（服务端会报错）**，不是"建议不要" |
| **DMAD**（Distribution Matching as Adversarial Distillation） | 仓库 `Yzmblog/DMAD` 真实：**Apache-2.0**，created **2026-09-29**，pushed **2026-10-08**（114★）。Kijai 的低秩重排转换存在：`Kijai/MiniMax-H3-experimental` → `loras/minimax_h3_DMAD_4step_full_lora_avg_rank_39_bf16.safetensors`，**0.34 GiB** | ✅ 补进 §10 少步家族表（我上一版完全没有 DMAD 这条线） |
| **VEDA / Miowtion**（训练无关块稀疏） | 仓库与 `Veda-Sparse/...T2VA-Veda-8NFE...` predictor 按其描述存在；其"7.1× 是注意力单项、端到端 2.9×"的自我更正方法论正确；**已发布 predictor 只覆盖 T2VA，Ref2VA 明确 out-of-scope** | ✅ 采纳"先测注意力占比再决定投不投"的判断法 |
| **"下一个瓶颈是 H2D 拷贝与 VAE 解码"** | 与我在 SGLang 文档里独立读到的证据一致：`video_vae=36` 驻留可把解码从 **60 s（流式）/209 s（忙主机）压到 ~10 s 且逐位一致**；RTX PRO 6000 单卡 8 步档 decode 占 20.6 s/160 s | ✅ 采纳，且给出**比它更可执行的解法**（见 11.3） |
| **帧数网格 17n+5** | 独立佐证两处：SGLang warmup 用 345(=17×20+5)、Sol Engine 的 `H3_DURATION_SECONDS=5.166667` 配 124(=17×7+5)、larryvrh README "snaps to the model's 17·k+5 grid (124 ≈ 5 s)" | ✅ 采纳（排时长时避免被静默吸附） |
| **A100 在 vLLM-Omni 官方认证表里缺位** | 真实且比它的表述更强：**PR #6492 `[Recipe] MiniMax-H3 on A100-SXM4-40GB (TP4 + CPU offload / DLO)` 已被关闭且未合并**（`created 2026-08-22`，`closed_at 2026-09-28`，`merged:false`） | ✅ 采纳"官方无 A100-40G recipe、要走就得自己认证"，并把它 PR 里的**实测数**拿来当锚点（见 11.2） |
| Kijai **int8 Video VAE**（解码 ~1.5×，ComfyUI 需 0.31+ 否则全黑）、**Viggle-Animate**（ref2va 全量微调 + rank128/302 三层前向蒸馏；**LoRA 只能挂在自己的微调后 transformer 上，挂 stock `transformer_ref` 会出垃圾**；并佐证"33.1B 里 **13.0B 在 `adaln_proj`，线性量化器不碰它**"）、**RefMods**（1–1.6 MB 条件适配器，最多 8 槽） | 与我独立抓到的 `DeepBeepMeep/MiniMax-H3` 文件清单（`Viggle-Animate-pruned_rank8_*`、`minimax_h3_video_vae_int8_convrot.safetensors` 2.62 GiB）互不矛盾 | ✅ 补进资产清单 |

### 11.2 它的结论里有错的 / 会把人带偏的（逐条给证据）

**① 最严重：它把"消除卸载 = 免费 3.77×"当第一优先，但那个对照数字不是 40GB 卡跑出来的。**

- 它的对照是 Sol Engine 官方 **4×A100 dense 基线 217.32 s / 4.35 s每步 / 每卡峰值 49,126 MiB**（1344×768、124 帧、50 步、无卸载）。
- **49,126 MiB ≈ 48 GiB > 40 GiB**，它自己在 §5.1 也已认定"这条必然是 A100 **80GB**"——但随后又把 4.35 s/步 当作 40GB 的目标去排优先级，**自相矛盾**。
- 更硬的相反证据就是它引用的那条 PR #6492 的**实测表**（同一 shape 之外的小 shape，4×A100-**40G**）：

| 路径（#6492 实测，480×256 / 96 帧 / 50 步） | 每卡 HBM（去噪期 / 全程最坏） | 端到端 |
|---|---|---|
| **TP4 + `--enable-cpu-offload`** | 22.8 GiB / **33.0 GiB**（可复现） | **364.9 s** |
| DLO AllGather | 13.5 GiB / 34.0 GiB | 1069.3 s |
| DLO rank-local（TP1+DP4，shared-mmap） | 12.4 GiB / 33.3 GiB | **1844.6 s** |

→ **在 40GB 卡上，DLO 比"TP4 + 模型级 CPU offload"慢 2.9×～5.1×。** 它的"阶段 1 第 3 步改用 DLO 就能把 16.4 s/步拉回 4.35 s/步"是**方向性错误**：DLO 每步要把非驻留 block 从主机重放，40GB 下驻留层数被压得很低，于是 H2D 就是节拍器。
→ 另一个可复用的细节：**`--cpu-offload-gb`、`--offload-group-size` 这类 vLLM-core 卸载参数对扩散任务是 no-op**（PR 正文写明，A/B 显存行为一致）；`--enable-cpu-offload` 才是有效开关。如果用户现在的 820 s 配置里挂着 vLLM-core 那组参数，那是无效项。
→ 同时注意"**峰值发生在去噪环之外**"：33.0 GiB 峰值只留 5–7 GiB 余量，所以**要按峰值而不是去噪水位做预算**。

**② 把 SGLang 的画质数字安到了 vLLM-Omni 头上，并据此说"零风险先开"。**
它写"Cache-DiT `quality=high`（vLLM-Omni 请求级）→ SSIM 0.931，零风险先开，可与蒸馏 LoRA 叠加"。核实：
- **SSIM 0.931 / PSNR 28.16 dB / 1.40×** 是 **SGLang** 在 4×H200 上审计的数（且 SGLang 的 `quality=high` **硬锁 4×H200**，A100 直接 fail）。
- **vLLM-Omni** 自己的请求级 `high` 实测是 **85.49 s → 63.36 s = 1.35×，SSIM 0.9709 / PSNR 34.98 dB**（4×H200）。
- "可与蒸馏叠加"只有一半依据：vLLM-Omni 文档写 "Turbo is independent of this quality switch"（说的是**机制**独立），但**没有做过 蒸馏 × cache 的标定**；SGLang 则明确 "**avoid stacking a distilled adapter with `quality:"high"` … not been quality-validated**"。
→ 正确表述：**可试、需自测、两套数字别混引**。

**③ "larryvrh Turbo v4 ✅ 覆盖 Ref2V" 缺证据。**
larryvrh 卡片 base_model 是 `Comfy-Org/MiniMax-H3`、`pipeline_tag: text-to-video`，正文只说 "both text-to-video and image-to-video work"，且文件是 `minimax_h3_turbo_*`（FL2VA 口径）；SGLang 的 pinned 配方明确"**trained for the FL2VA partition and apply to `t2va` or `fl2va`**；Ref2VA 要另选文件，且那些 Ref2VA 文件尚未成为本页的 pin 配方"。
→ 应降为 **⚠️ FL2VA/T2VA**；它把它列进"Ref2VA 专项可用"会让用户拿 FL2VA 文件去配 ref2va 服务。

**④ "GGUF 不支持 LoRA → 走 GGUF 等于放弃步数蒸馏" 过头了。**
GGUF 的限制是**运行时不能叠 LoRA、不能 FSDP**；但社区已有**把 turbo 蒸馏合并进权重的 GGUF**（`ChrisColeTech/minimax-h3-turbo-GGUF`，含 qwen3vl-4b/8b 小编码器）。少步能力在权重里，不需要运行时 LoRA。
→ 正确结论：**GGUF 放弃的是"你自己的风格/角色 LoRA 与 FSDP"，不是"少步"。**

**⑤ Sol Engine 的启动命令与仓库实际布局不符。**
它写 `python scripts/launch_candidate.py candidates/minimax_h3_a100_fullopt_exact.toml --mode sbatch --confirm-submit`。实测 `NVlabs/Sana@sol-engine` 分支：QUICKSTART 明确"**launched with `python3 scripts/run.py config/<model>/<arm>.toml`**"，配置在 `config/minimax_h3/` 下，文件名是 **`a100_dense.toml` / `a100_quality.toml` / `a100_balanced.toml` / `a100_aggressive.toml`**（另有 `minimax_h3_a100_fullopt.toml`），没有 `candidates/` 目录。
→ 照抄它会直接失败。另外一个重要性质它没说清：**Sol Engine 的 A100 臂本身是包在 SGLang 外面的**——`a100_dense.toml` 的 description 原文 "**Official SGLang MiniMax-H3 BF16 dense control on 4x A100 with FSDP and Ulysses-4**"，pin 了 `revision=bfc8ed0353f5…` 与镜像 `lmsysorg/sglang:nightly-dev-cu13-20260803-12eadf86`，走 pyxis/SLURM。优化臂是 "conservative **EasyCache** + **Triton Sol-Attn**"。
→ 也就是说它不是"第三个独立引擎"，而是 **SGLang 之上的 kernel/cache 配方**（这反而对用户是好消息：不必换框架）。

**⑥ 单位混用会让预算算错 7%。**
它的清单是**十进制 GB**（DiT bf16 66.28、pruned INT8 20.97、Qwen 51.51、合计 123.6），我的表是 **GiB**（61.73 / 19.53 / 47.97 / ≈115）。同一批文件、两种单位。它据此得出"4×A100 TP4 BF16 摊到 30.9 GB/卡、余 9.1 GB，理论上放得下"——但 4×H100 官方实测 **TP4+Ulysses1 峰值 49.80 GiB/卡**，说明**激活与缓冲约 23 GiB**，40GB 卡在 1344×768 上**BF16 全驻留是放不下**的（#6492 也在 480×256 这种小 shape 上才拿到 33 GiB 峰值，并明确 "TP8 fully resident does not fit on 40 GiB"）。
→ 正确表述：**BF16 无损 + 40GB + 768p 必须有取舍**（要么削 AdaLN，要么编码器外置，要么降 shape）。

### 11.3 两份报告合并后的最优解（它没有、我也没写全的那一步）

它的头号诉求是"**消除卸载**"，但它给的解法（TP4 BF16 裸摊 or DLO）在 40GB 上要么 OOM 要么 3× 变慢。**正确的工具是 SGLang 的 AdaLN 在线重建**：

```
DiT 61.73 GiB − adaln_proj 24.2 GiB（在线重建，文档称 bit-exact）= 37.5 GiB
+ Qwen3-VL 47.97 GiB 交给 --component-residency text_encoder=layerwise-offload / 编码器 TP
+ VAE 5.4 GiB（video_vae=36 驻留，解码 ~10 s）
→ 4×A100-40G 上"去噪环内不再有 61.7 GiB 权重搬运"，同时画质不变
```
- 它与我上一版的取舍关系要说死：**AdaLN 在线 与 剪枝/量化互斥**（剪枝版根本没有原生 `adaln_proj`；量化权重做不到 bit-exact）。所以"无损去卸载"只有 AdaLN 在线这一条；一旦允许近似，就直接上 pruned INT8/W4A8（DiT 19.53/11.68 GiB），连 FSDP/offload 都不需要。
- vLLM-Omni 侧它说的"**编码器分离**（把 51.5 GB 的 Qwen3-VL 移进独立 vLLM 阶段）"是对的，而且**这是 vLLM-Omni 独有**的招：SGLang 只有 encoder-parallel auto/fold/replicate，没有跨阶段分离。若用户坚持 vLLM-Omni 单端口服务，"编码器分离 + TP4 + `--enable-cpu-offload` + 8 步蒸馏"是比 DLO 更合理的组合。
- **补一个它没提、对"只用一个框架"最关键的差别**：`PulpCut/MiniMax-H3-Ref2VA-Turbo-INT8-ConvRot`、`Winnougan/…ref2va_pruned-w4a8`、`Comfy-Org` 的 pruned INT8/FP8、GGUF、AutoRound W4A16 这类**预量化/剪枝单文件**，在 **SGLang 是被逐行列为受支持**（各自还标了 TP/offload/FSDP 约束）；而 **vLLM-Omni 的能力表里虽然有 GGUF（改为 OOT 插件 `vllm-gguf-plugin>=0.0.3`）与 AutoRound W4A16（GPTQ-Marlin），"已验证模型"一栏只有 Qwen-Image / Z-Image / FLUX.1-dev / FLUX.2-klein / Wan2.2，没有 MiniMax-H3**，且 H3 recipe 全文对 `gguf/convrot/kitchen` 是 **0 命中**。vLLM-Omni 的在线量化清单是 FP8 W8A8 / Int8 W8A8 / BitsAndBytes W4 / MXFP8 / MXFP4（另有注意力侧 quantized KV cache）。
→ 修正后的分叉结论：**"H3 预量化/剪枝权重开箱可用"目前只有 SGLang 有一等支持**；vLLM-Omni 侧要么自己验证 GGUF/AutoRound 能否挂到 H3 组件，要么就用**在线 int8/fp8（A100 上是 weight-only，只省显存）+ 卸载 / TP / 编码器分离**这套。所以：**要"量化驻留 + 一步到位少步"，选 SGLang；要"编码器分离 + 官方 Ref2VA Turbo + res_multistep"，选 vLLM-Omni。** 这条决定框架选择，比"已经选了 vLLM-Omni"的前提更值得先看一眼。

### 11.4 合并后的行动优先级（替换它的 §5.5，也替换我 §9.3 的顺序）

0. **量三段占比**（采纳它的阶段 0，判据也采纳）；同时把当前配置里的 `--cpu-offload-gb`/`--offload-group-size` 一类参数**移除或确认无效**（#6492 实测为 no-op）。
1. **选杠杆而不是选卸载方式**：先决定"无损（AdaLN 在线，SGLang）"还是"允许近似（pruned INT8/W4A8，SGLang；或 vLLM-Omni 的在线 int8 + 编码器分离）"。**不要在 40GB 上把 DLO 当主路径**——实测它比 TP4+CPU offload 慢 2.9~5.1×。
2. **步数**：vLLM-Omni 路线 → `minimax_h3_ref2v_turbo_8step_v1.0_768p`（steps=9 / shift 6 / α=8）；SGLang 路线 → PDD Ref2VA 8 步（steps=9 / 12 / 3 / lossless）。**与 `res_multistep` 二选一**（服务端会硬拒）。口播/人脸类保 8 步，别上 4 步。
3. **系统级/请求级**：vLLM-Omni 的 1.445× 栈（`--ulysses-a2a-permute` 等，NVLink 机型收益更足）；`quality=high` 可试但**按"未标定"对待**，并与蒸馏分开测。
4. **VAE 与时长网格**：解码是大头（`video_vae=36` / int8 VAE / VAE patch-parallel + tiling），时长按 **17n+5** 排。
5. **最后才动注意力**：`sol_attn`（A100 走 Triton，需 CUDA ≥12.8 / Triton ≥3.6）或 `sage_attn`；社区反复反馈**稀疏/INT8 注意力先伤音频**，音频必须单独把关。

---

## 12. 增量调研（2026-10-08 → 2026-11-06）：少步/后训练、高分辨率与框架更新

> 本节全部为**这一轮亲自复核**的一手材料：SGLang H3 cookbook 与 vLLM-Omni H3 recipe 的 **11-06 现版原文**（与 10-08 缓存逐节 diff）、hf-mirror API 的仓库时间戳/体积、MiniMax 官方 README 现版、各模型卡正文。日期一律写首发日。

### 12.1 一句话总览

一个月内真正改变决策的三件事：

1. **出现了两个"SGLang 一等支持 + Ref2VA + 少步"的方案**：**Pika H3 Flex**（6 步，10-29）与 **FastH3-Omni-8-Step-V1**（8 步 PDD，10-05，文档 11-06 版收录）。我 §10.2 里"PDD 是唯一进 SGLang 正式流程的 Ref2VA 蒸馏"这句**已过时**。
2. **开放版 2K 再生成来了**：`Efficient-Large-Model/Open-H3-Regenerate-2K`（10-26，已 62.7 万下载）——**3 步把 768p 草稿重绘到 2560×1440**，且它是 **H3 本体 + 合并 LoRA**，不是第二个模型家族；vLLM-Omni 已能作为独立部署服务它（PR #9562，11-02）。这直接替掉了我在 §10.0 推荐的 SoL-Refiner（LTX-2.5 底座、无音频、双许可）。
3. **vLLM-Omni 官方补上了 A100 章节和 LiteVAE 解码器**——但 A100 章节写的是 **A100-SXM4-80GB**，且它给出的 Ref2VA 实测恰好证明"多参考 Ref2VA 是最硬的场景"（2×80GB，E2E **756.3 s**，峰值 54.63–67.92 GiB/卡）。

### 12.2 少步 / 后训练新条目

| 资产 | 首发 | 方法 & 步数 | 任务 | 体积 | SGLang / vLLM-Omni | A100-40G 判断 |
|---|---|---|---|---|---|---|
| **[Pika-Labs/Pika-H3-Flex](https://huggingface.co/Pika-Labs/Pika-H3-Flex)**（Mellis, Inc.） | **2026-10-29** | H3 **后训练**，**固定 6 步**：knots `1000/750/500/250/100/40`，按模态 shift（视频 12 / 音频 3），**每步预测 x0 后再加噪**（re-noising）。官方与 SGLang 都强调 **"generic six-step Euler is not equivalent"** | **FL2VA（t2va/fl2va/i2va/l2va）+ Ref2VA** 两个适配器；Ref2VA 支持 9 图/3 视频/3 音频、共 12 个文件 | FP32 PEFT LoRA rank/alpha 128，**各 2.58 GiB**；Comfy BF16 版各 1.82 GiB；overlay 只下 ≈5.5 GB 并校验 sha256 | **SGLang 一等支持**（`sglang serve --model-path Pika-Labs/Pika-H3-Flex [--model-variant ref2va]`，请求 `num_inference_steps: 6`，其它值拒绝；省略 shift 保持 12/3）；**vLLM-Omni recipe 全文 0 次提到 Pika** | ⚠️ 可用但有硬约束：**适配器保持未合并**（`--lora-merge-mode dynamic`，"a BF16 merge rounds away about a third of its update"）、**`--lora-path` 不能替换自带适配器**、**不支持 `quality:"high"`**。官方时延（1×H200，5 s）：t2va **37 s** / fl2va 42 s / **ref2va（2 图 + 1 带音频视频）260 s** |
| **[FastVideo/FastVideo-FastH3-Omni-8-Step-V1](https://huggingface.co/FastVideo/FastVideo-FastH3-Omni-8-Step-V1)** | **2026-10-05** | **PDD** 学生（Ref2VA 分区）：**8 次去噪 / 32 区间网格**，VSA 0.9 稀疏、128-token (4,4,8) tile、每个参考视频只保留 0.1 的 tile | **仅 `task:"ref2va"`**（9 图/3 视频/3 音频，至少一个视觉参考） | overlay 自动把 32 个区间头**融合成 8 个逐步头**（等价于 `fuse_minimax_h3_pdd_heads` 的数学），并链接 pinned Ref2VA 的 TE/VAE | **SGLang 直接 `--model-path`**（示例 `--num-gpus 2 --ulysses-degree 2`）；请求默认 steps=8、clean references（cond-noise-aug 1.0） | ✅ 但**拿不到 VSA 的收益**：文档写 VSA-H3 内核是 "FastVideo's native tcgen05 forward on **SM100/SM103**, a Triton tile-64 kernel on **SM90**" → **SM80 不在列**，须显式 `--component-attention-backends transformer=fa`；参照 4×H200 上"dense FA 比 VSA-H3 慢约 25%（12.6 vs 10.0 s）"。显存：文档称"141 GB 与 180 GB 卡全驻留"；2×H200 实测 39.0 s（驻留）/ 43.8 s（三件套 `--dit-cpu-offload --text-encoder-cpu-offload --vae-cpu-offload`）；4×B200 10.3 / 15.3 s。480p 单图 26.9 s、768p 单图 46.6 s、768p 参考视频 37.1 s |
| **zjwfufu/SMD-MiniMax-H3-{T2VA,Ref2VA}-{4,8}step**（+ ComfyUI 版） | **2026-10-07** / Comfy 版 10-13 | **SMD** 蒸馏（代码 `github.com/zjwfufu/SMD`），4 步与 **8 步**两档，**Ref2VA 有独立 checkpoint** | t2va / **ref2va** | 标准 Comfy `Load LoRA`（**无需自定义节点**）；原版权重 + ComfyUI 转换各一套 | ⚠️ 框架侧未见收录；因为是普通 LoRA 布局，`--lora-path` 理论上可试（**未验证**） | ⚠️ 待实测；下载量 5.3k/3.7k（Ref2VA 8step/4step Comfy 版），社区热度中等 |
| **berryber09/MiniMax-H3-FastH3-VSA-4step-pruned-w4a8** | 2026-10-18 | FastH3 4 步蒸馏 + pruned + **W4A8 ConvRot** 合并 | FL2VA（`..._fl2va_pruned_w4a8.safetensors`，**15.27 GiB**） | 单文件 15.27 GiB | SGLang 的 `comfy-w4a8-convrot` 行按格式自动识别（**Requires SM80+**，依赖 `comfy-kitchen>=0.2.27`） | ✅ 这是**A100 上最省的 t2va 快车道**（15 GiB 驻留）；但仅 t2va/fl2va |
| **Spectrallic/MiniMax-H3-PDMD-4step-int8-convrot**（11-04）、**Asirus/MiniMax-H3-Ref2VA-PDMD-4NFE-1p0**（10-17）、**Asirus/…ref2va_pruned_int8_convrot_taomate_8_step**（10-05） | 10-17 → 11-04 | PDMD / TaoMate 的 int8 与 Ref2VA 化 | 含 **Ref2VA** 变体 | 未逐个核体积 | 属于"社区合并产物"，SGLang 走 `--component-weights-paths`；**正确性依赖 ≥2026-10-05 的 ConvRot 修复** | ⚠️ 逐个实测画质 |
| **ZhengmingYu/DMAD**（官方权重，10-02 建，**10-30 更新，107,725 下载**） | 2026-10-02 | 我 §10.2b 已收录；这一个月它成为下载量最高的蒸馏系权重之一 | 上游仍只声明 "the H3 transformer" | 1.4/2.0 GB | — | 结论不变 |
| Pika 生态外溢：**FastVideo/Pika-H3-Flex-NVFP4-QAD**（11-01）、**…-NVFP4-FP4Attn-QAD**（11-02）、`Pika-H3-Flex-GGUF`/`-MLX`/`-ROCmFPX`/`Turbo-LoRA` 合并若干 | 11-01~11-06 | QAD（量化感知蒸馏）与各种搬运 | — | — | NVFP4 系列 **SM100+ 才能算** | ❌ NVFP4；GGUF 版可试但**不能叠 LoRA/FSDP** |

### 12.3 高分辨率路径易主（对我 §10.0 的实质修正）

**`Efficient-Large-Model/Open-H3-Regenerate-2K`（2026-10-26；recipe 于 11-02 进 vLLM-Omni）**

| 维度 | Open-H3-Regenerate-2K | SoL-Refiner-LTX-2.5-for-MiniMax-H3（§10.0） |
|---|---|---|
| 底座 | **MiniMax-H3 FL2VA 本体 + 合并 LoRA**（Open-H3 refiner + LightX2V FL2VA Turbo + LMS Sharp）；参考实现落在 `NVlabs/Sana/models/Open-H3-Regenerate-2K` | LTX-2.5 22B（另一模型家族）+ Gemma 4 12B |
| 步数 | **3 步 Euler**（sigmas `0.909375, 6/7, 2/3`），可选 **2 步**（`0.7, 0.494`，release 的 shift-6 规则） | 1 步 |
| 输出 | **2560×1440**（`latent_upscale` 默认 `{width:2560,height:1440,align:32}`） | 官方口径可到 4K |
| 音频 | **保留草稿音轨**（refiner 以"编码后的静音"为条件，输出经 H3 audio-VAE 往返携带草稿声音；草稿无音则输出静音） | **输出无音频**，要自己 mux |
| 附加体积 | **≈14 GB**（只要 `lora/*` + `latent_upsampler/*`，基座复用 MiniMax-H3） | 38.5–65.9 GiB 全套 |
| 许可 | MiniMax H3 Community License（单一） | LTX-2 Community + H3 Community **双许可** |
| 框架 | **vLLM-Omni 有官方 recipe**（作为独立部署；`{"task":"t2va","regenerate":true}` + `source_video`；**拒绝** `flow_shift`/`sampler`/`latent_refine`/per-request `lora`） | 两框架都没有集成（diffusers / ComfyUI / image-server） |
| 诚实细节 | release 的 `lora/sharp_curve_branches.safetensors` **up 因子全为 0**，实际不贡献（loader 会校验这点） | — |

→ **修订结论**：对你的 Ref2VA 生产线，**优先 Open-H3-Regenerate-2K**（同底座、同音频 VAE 通路、单一许可、只多 14 GB、vLLM-Omni 可服务），把 SoL-Refiner 降为"追求 4K/更省一步时的备选"。代价与限制：它是**画布放大约 3.5× 的独立服务**（另一份 61.7 GiB 权重 + 各自显存），"every request on this server is a regenerate request; serve plain MiniMax-H3 from a separate server"——**在 4 卡 40GB 机器上你只能二选一部署**，不能与 Ref2VA 主服务同卡共存。

### 12.4 vLLM-Omni 这一个月的结构性更新（对你选框架有直接影响）

| 更新 | 时点 | 开关 / 事实 | 对你的意义 |
|---|---|---|---|
| **官方 A100 章节（80GB）** | recipe 现版 | `2×A100-SXM4-80GB`，TP2：DiT ≈**30 GiB/卡** + Qwen3-VL ≈**25.75 GiB/卡** 同时驻留"余量不足"，因此**只 offload text_encoder**：`--diffusion-offload-config '{"mode":"layer","components":["text_encoder"]}'`，配 `FLASH_ATTN`、`--usp 1`、`VLLM_OMNI_DLO_DP_WAVE_TIMEOUT=3600`、`PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True` | 这是官方第一个 A100 配方，但**是 80GB**。实测（Ref2VA，1344×768，10.0 s @24fps，**25 步**，`quality="high"`）：quiescent **41.69 GiB/卡**、allocator peak **54.63**、`nvidia-smi` 峰值 **57.46**，warm E2E **756.3 s**（2 张 2726×1536 参考图）；再加 2 个参考视频 → 峰值 **67.92 GiB/卡**。**移植到 40GB 的结论：这套拓扑在 40GB 上必须把 DiT 和 TE 都量化**（W4A8 组合 ≈13 GiB/卡），否则连 80GB 都只能靠 offload 编码器 |
| **LiteVAE 视频解码器**（PR #9245） | 2026-10-31 | `--additional-config '{"lightvae_decoder_path":"/weights/lightvae-lite-h3-decoder.safetensors"}'`；checkpoint 来自 **`lightx2v/LightVAE`（10-10，Apache-2.0）**；**只替换 video decoder**，video encoder 与 audio VAE 不变；"Generated pixels can differ from the original decoder"；与 bundled NVFP4 自动发现互斥；checkpoint 为空/不兼容则**直接失败，不静默回退** | 直击"VAE 是新瓶颈"（Miowtion 与 `video_vae=36` 都指向这里）。性能要看它自己的 guide，官方明确"别把 E2E 时延和 VAE 解码时延混谈" |
| **跨请求 latent-tail continuation**（PR #9342） | 2026-10-30 | `long_video_mode:"continuation"`、`continuation_window_frames:277`、`continuation_overlap_frames:22`、可给 `continuation_prompts` 数组；默认采样 7 个窗口产出 **1,807 帧**；Ref2VA 长视频请求**已默认走 latent continuation**；**拒绝** latent-mask 编辑（`video_noise_mask` 等）；算法沿用 `ttulttul/ComfyUI-Minimax-H3-Continuation` | 长片段/连续叙事的新能力，也是新的显存路径差异（full vs continuation 模式超时不同：300 s） |
| **`res_multistep` 正式文档化** | PR #8378 于 10-04 合并 | 请求 `extra_params={"sampler":"res_multistep"}`；`euler` 仍是默认 | 与 §11 结论一致：**与固定蒸馏 sigma 的产物互斥** |
| **VDN-H3 也能在 vLLM-Omni 服务** | recipe 现版 | `--lora-path OpenVDN/vdn-minimax-h3 --diffusion-attention-backend VDNH3_ATTN`，配 `--tensor-parallel-size 2 --text-encoder-tp-size 2 --vae-patch-parallel-size 2`；只下 `stage-dmd-step-250/`（≈5 GB）；两个 LoRA 在权重流入时融合、线性分支挂到 DiT block 上 | VDN 的框架可选性变宽（仍 **FL2VA/T2VA**，Ref2VA 只有 "Ref2VA-like"） |
| **配置化启动 + DLO 细粒度选项** | recipe 现版 | `vllm serve "$MODEL" --omni --config recipes/…/minimax-h3-ref2va-8-rank-resident.yaml`；`diffusion-offload-config` 支持 `layer_options`，例如 `{"dit":{"weight_transfer":"allgather"},"text_encoder":{"weight_transfer":"rank-local"}}`；该 yaml 的出处是 **8×Ascend 910B1（64 GiB/卡）Ref2VA 实验** | 现在可以把"DiT 走 AllGather、编码器走 rank-local"这类组合写死在配置里，便于交付与回滚 |
| 与 vLLM 0.33.0 对齐 | PR #9648，11-04 | — | 版本线又要动了，**锁 revision** 的建议继续有效 |

### 12.5 SGLang 侧的口径变化（有两条会让旧命令失效）

1. **PDD 的请求步数从 `9` 改成 `8`**：11-06 版原文 "Use the requests … with `num_inference_steps: 8`, `flow_shift: 12.0`, and `audio_flow_shift: 3.0`. **The nine sigma grid points give eight denoiser evaluations.**" 而 10-08 版同一句写的是 `num_inference_steps: 9`。解释句没变、请求值变了 → **"steps = sigma 点数"这条全局规则已经不是通用口径**。我的 §10.3 陷阱 #1 需要按下面这张表逐产物核对：

| 产物 | SGLang 请求（11-06 版） | vLLM-Omni 请求 |
|---|---|---|
| PDD 8 步 | **8** | — |
| FastH3 8-Step V2 | **8** | **8** |
| FastH3-Omni 8 步（Ref2VA） | **8**（默认） | — |
| **Pika H3 Flex** | **6**（且只接受 6） | 不支持 |
| VDN-H3 | **9** | 8（`--lora-path` 路径下请求 "8 steps"） |
| LightX2V ref2v Turbo 8step v1.0 768p | 9（旧口径，未在新文档 pin） | **9**，`flow_shift=6` |
| DMAD 4 步 | — | 5（=4 次评估） |
| FlashGen 4 步 | — | **4**（metadata `base_schedule` 有 5 个 knots） |

2. **FastH3 的主文档从"4-step preview"换成"FastH3: 8-step distilled"**，并新增 `FastH3 Omni: Ref2VA, 8-step PDD` 一节；`FastH3 on B300` 基准换成 **`FastH3 on GB300`**。
3. **`quality` 与 VAE 的关系写得更细**：FastH3 请求默认 `quality:"lossless"`，此时会 **fuse VAE decoder 的 per-head QK RMSNorm + RoPE 并走 cuDNN SDPA**，且每张 GPU **一次性解码其全部空间 tile**（base H3 是每调用最多 64 tile 批量），"changes GEMM shapes and so the output at rounding level"；`"exact"` 才逐 tile 解码。→ 做 A/B 回归时要连 `quality` 一起锁。
4. **不变的部分**（说明这些结论仍然可靠）：SM80 仍是 "runs the bf16 DiT (62 GB; budget for `--layerwise-offload-components`)，Ampere and Ada are enabled but not benchmarked"；ConvRot/W4A8/W4A4/GGUF/AutoRound 各行许可与 TP/offload/FSDP 约束未变；`quality="high"` 仍锁 4×H200；Spectrum 仍禁与 SP>1 同用。
5. **官方 README 现版仍未开源**：`sparse-attention implementation … will be released in a future update`、`H3-Regenerate-2K … this module is not yet open-sourced`。（2K 那条社区已经补位，见 §12.3。）

### 12.6 Prompt 侧的开放替代（影响画质而不是速度，但会减少返工）

`lightx2v/MiniMax-H3-Prompt-Rewriter-Qwen3.8-27B-Ref2VA`（**2026-10-29**，一周 49,859 下载）与 `…-Qwen3.5-9B-Ref2VA`：SFT 自 Qwen3.8-27B / Qwen3.5-9B，**用 vLLM 起服务**，接受 image/video/audio 参考并按数组顺序编号，对齐 H3 的 `<Picture i>/<Video i>/<Audio i>` 材质标签——即**未开源的 H3-Context-IR 的本地替代**。
代价：多一个 27B（或 9B）sidecar 的显存与运维（27B bf16 ≈ 51 GiB；int8 ≈ 26 GiB），在 4×40GB 上它只能与量化后的主服务抢卡，或者放 CPU/另机。

### 12.7 修订后的推荐（4×A100-40G，Ref2VA 必须）

1. **少步首选换成 Pika H3 Flex（`--model-variant ref2va`）**：SGLang 一等支持、6 步、只多 5.5 GB、FP32 适配器且不合并（画质更新量保留）。
   - 但**先看它自己的 ref2va 时延**：官方 1×H200 上 768p、2 图 + 1 带音频视频 = **260 s**，并解释"Most of the ref2va time goes to its long packed sequence"。→ **6 步并没有把 Ref2VA 变成实时任务**。
2. **真正的杠杆在参考序列长度**：官方 A100-80G 数据显示 2 图（2726×1536）→ 峰值 57.46 GiB / 756.3 s，再加 2 视频 → **67.92 GiB**。所以顺序应当是：**治理参考素材（数量、分辨率、时长）> 换 checkpoint > 换缓存策略**。可核实的硬约束来自 vLLM-Omni recipe：Ref2VA 参考图**短边 ≥256、长边 ≤5760、宽高比 0.4~2.5**；`duration` 与 `short_edge` 直接决定 packed 行数；VDN 文档也量化过"**每个关键帧约增加 2,000 dense rows**"。（另一份调研提到的 `ref_image_size: match→max` 提升身份保真但显著增时，我**未在一手文档中核实**，属 ComfyUI 侧字段，先按经验项对待。）
3. **高分辨率走 Open-H3-Regenerate-2K**（3 步、+14 GB、单许可、vLLM-Omni 官方 recipe），并把 SoL-Refiner 降为 4K 备选。**注意它是独立服务**：4 卡机器上"主生成服务"与"2K 再生服务"不能同卡共存。
4. **解码器**：vLLM-Omni 路线试 LiteVAE；SGLang 路线继续用 `--layerwise-resident-layers video_vae=36`（无损、~10 s）。
5. **40GB 的现实约束没变**：官方 A100 配方按 80GB 给（DiT 30 + TE 25.75 GiB/卡）。要在 40GB 复刻"全驻留 + 只 offload 编码器"，需要 **W4A8/pruned-INT8** 把 DiT+TE 压到 ~13 GiB/卡；而**量化基座 + FP32 未合并 LoRA** 这一组合（Pika）文档里没有标定 → 上机先测峰值与 PSNR，再决定是否退回 BF16 主权重 + `--dit-cpu-offload` 三件套（FastH3-Omni 文档给的就是这条路）。
6. **待验证清单（新增）**：SMD 的 LoRA 能否被 SGLang `--lora-path` 直读；Pika FP32 适配器与 ConvRot W4A8 基座共存时的显存与画质；FastH3-Omni 在 SM80 上用 dense `fa` 的实际相对损失（文档只给了 SM90/SM100 的 VSA 数字）。

### 12.8 本报告需要跟着改的旧结论（自检）

| 位置 | 旧说法 | 现纠正为 |
|---|---|---|
| §10.2 ① | "PDD 是唯一被写进 SGLang  cookbook 正式流程的 Ref2VA 蒸馏" | **不成立**：FastH3-Omni-8-Step-V1（Ref2VA 专用，自动 fuse 头）与 Pika H3 Flex（ref2va 适配器）都已进一等文档；PDD 变成"可选手工路线" |
| §10.2 ④ / §10.0 | "画质上限更高时用 SoL-Refiner" | **改为优先 Open-H3-Regenerate-2K**（同底座、保留草稿音轨、单许可、+14 GB、vLLM-Omni 官方 recipe）；SoL 降为 4K 备选 |
| §10.3 #1 | "SGLang 一律 steps = sigma 点数（8 步写 9）" | **按产物区分**：PDD/FastH3 V2/FastH3-Omni = 8，Pika = 6，VDN = 9，vLLM 侧 FlashGen/DMAD 又是另一套；以现版文档逐项核对 |
| §9.3 / §9.6 | "终点停在 Stage 3 + Stage 4a（量化 + PDD 8 步）" | **改为 Pika/FastH3-Omni 优先、量化按需**；且必须承认"Ref2VA 的墙钟主要花在 packed 序列与解码"，所以参考治理与解码器优化排在换 checkpoint 之前 |
| §2 能力矩阵 | `subblock_sparse_attn` / VSA 的 SM80 结论 | 不变；但新增一行：**VSA-H3 内核谱系（SM100/SM103 tcgen05、SM90 Triton tile-64）明确不含 SM80** → FastH3/FastH3-Omni 的收益在 A100 上打折 |
