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
里 pin 的 revision 从 HF 拉 base 的 video/audio VAE（t2va 走 FL2VA 分区，
具体子路径以 `provenance.json` 为准）到同一个 `HF_HOME=/model_nas/hf-cache`。

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