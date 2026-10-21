# HANDOFF：长时长视频生成的超时上限（sglang 100min 硬编码 / vLLM 可配）与镜像重建清单

> 适用场景：MiniMax-H3 单段生成（如 15s / 9:16 / 768 短边、A100 40GB + layerwise offload）耗时逼近或超过 100 分钟。
> 本文给出问题定位、两侧（sglang / vLLM-Omni）超时机制差异，以及**重建镜像时必须落地的改动与验收步骤**。
> 结论均在旧镜像 `minimax-h3-sglang:latest`（base `lmsysorg/sglang:nightly-dev-20260803`）与 `minimax-h3-vllm:latest`（旧 base `vllm/vllm-omni`）内实测确认，非推测；镜像切版后请按 §6 复核。
>
> ⚠️ **2026-10-18 起 base 已固定版本，部分结论只对旧镜像成立：**
> - SGLang：`minimax-h3-sglang:v0.5.21` 已把硬编码的 `zmq.RCVTIMEO, 6000000` 换成可配的
>   `--scheduler-rpc-timeout <秒>`（默认 `None` = 不设 transport 层超时，上限 2147483s；
>   见 `multimodal_gen/runtime/server_args/server_args.py:2377`、`scheduler_client.py:76`）。
>   因此 §6 的 `SGLANG_DIFFUSION_SCHED_RCVTIMEO_MS` 源码 patch **在 v0.5.21 上不再需要**，
>   要设上限直接传 `--scheduler-rpc-timeout 10800`（根 base 与 deploy/ 三套 SGLang
>   compose 已经这么设了）。
> - vLLM：行为未变（`VLLM_OMNI_VIDEO_SYNC_TIMEOUT`，默认 600s），但 v0.31.0rc1 里位置是
>   `vllm_omni/entrypoints/openai/video/generation/helpers.py:100`。
> 下文行号取自旧 `:latest`，仅作历史参考。

---

## 1. 结论速览

| 项 | SGLang Diffusion | vLLM-Omni |
|---|---|---|
| 单次生成的服务端硬上限 | **100 分钟（6,000,000 ms），源码硬编码，无 env / 无 CLI 开关** | `/v1/videos/sync`：`VLLM_OMNI_VIDEO_SYNC_TIMEOUT`，**默认仅 600s**，env 可配；`/v1/videos`（异步 job）：**无服务端超时** |
| 超时后的行为 | `TimeoutError("Scheduler did not respond in time.")` → job 被写成 `status=failed` 且 `url/file_path/file_paths` 全部置 `None` | HTTP 504 `Video generation timed out after {N}s.` |
| 超时后磁盘上有没有 MP4 | **通常没有**（MP4 由 API 进程在 `forward()` 返回后才 `save_outputs()` 写盘） | sync 超时同样不落盘；async 不受该 env 约束 |
| 重建镜像时是否必须改代码 | **是**（唯一 3 小时方案的必经动作） | **否**，设 env 即可（但**必须设**，否则回落 600s） |
| 兜底下载能否救回 | 救不回这种 100min 超时（见 §3） | 不适用 |

---

## 2. SGLang 侧：确切位置与失败链路

文件（镜像内，editable 安装，源码树即生效模块）：

```
/sgl-workspace/sglang/python/sglang/multimodal_gen/runtime/scheduler_client.py
```

实测（`lmsysorg/sglang` 系列，`import sglang` 解析到 `/sgl-workspace/sglang/python/sglang`）：

```python
:77        # 100 minute timeout for generation
:78        self.scheduler_socket.setsockopt(zmq.RCVTIMEO, 6000000)   # 同步 SchedulerClient
...
:177       # 100 minute timeout
:178       socket.setsockopt(zmq.RCVTIMEO, 6000000)                  # 异步 AsyncSchedulerClient（/v1/videos 走这条）
...
:101/:192  raise TimeoutError("Scheduler did not respond in time.")
```

- `6000000 ms = 6000 s = 100 min`，两处字面量；全仓库 `grep -rn "6000000"` 仅这两处，`grep -rn "RCVTIMEO"` 除 ping 的 `2000` 外也只有这两处。
- **没有任何环境变量或 server arg 可以调它**（`multimodal_gen/utils/envs.py`、`configs/` 内无 timeout/watchdog 相关项）。
- 失败链路：`AsyncSchedulerClient.forward()` 抛 `TimeoutError` → `runtime/entrypoints/openai/video_api.py` 的 `_dispatch_job_async()` except 分支把 job 更新为
  `{"status":"failed","url":None,"file_path":None,"file_paths":None,"num_outputs":None}`。
- `/content` 端点（`openai/video_api.py` ≈L901-L921）要求 `job["file_path"]` 存在且文件在磁盘上，否则 404 → 字段已被清成 `None`，必然 404。
- MP4 是在 API 侧写的：`openai/utils.py:341 process_generation_batch()` → `forward()` 返回后才 `save_outputs()`。客户端 100 分钟处抛错＝不写盘。

### 关于 `docker-compose.yml` 里的 `--watchdog-timeout 3600`

该参数属于 `sglang/srt`（LLM 引擎）路径；`multimodal_gen` 下 **不读取** `watchdog_timeout`（`grep -rn watchdog multimodal_gen` 只命中 IPC-a2a 注释）。也就是说 diffusion 侧的 "Scheduler did not respond in time." 与它无关，**不要指望调它来延长生成时间**。

---

## 3. 现有脚本「兜底」的真实边界

代码位置：

- `scripts/ref2va-story-sglang.sh`：说明注释 ≈L106-L118、`download_video()` ≈L141-L157、`failed|error|cancelled` 兜底分支 ≈L253-L268
- `scripts/ref2va-jiaoxintong-sglang.sh`：注释 ≈L212-L227、`download_video()` ≈L247-L262、兜底分支 ≈L322-L335

能救回的场景：① 客户端自己先断开而服务端随后把 job 标 `completed`；② 开了云存储、`url` 已写入；③ `status=completed` 但下载瞬时失败 → 重试。

**救不回的场景（即本次遇到的）**：单段真的跑满 100 分钟 → 服务端把 `file_path` 清成 `None`，`url` 也是 `None`，`/content` 返回 404，脚本会一直轮询到 `POLL_TIMEOUT`（现 4h）才放弃。注释里那句「服务端最终会把视频生成到磁盘」在这一模式下不成立，建议在 patch 完服务端后顺手修正该注释。

---

## 4. 重建镜像时的改动清单

### 4.1 SGLang 镜像（base 已改为 `lmsysorg/sglang:v0.5.21`）

> 现状：`Dockerfile` 已从 `lmsysorg/sglang:dev` 切到 `v0.5.21`，**但下文的 `RCVTIMEO` 3h patch 尚未加入该文件（仍为待办）**。

当前 `Dockerfile`：`FROM lmsysorg/sglang:v0.5.21` + `pip install -e "python[diffusion]"`（editable，源码树即运行模块）。
→ patch 目标就是 `/sgl-workspace/sglang/python/sglang/multimodal_gen/runtime/scheduler_client.py`，**必须写在 `pip install -e` 之后的层**，避免被后续步骤覆盖。

**推荐做法：改成 env 可调（默认 3h）**，一次改对、后续无需重 build：

```python
# 文件顶部 import 区（若无 import os 则补）
import os

# Scheduler reply timeout (ms). 上游硬编码 6000000(100min)；H3 单段可 >100min，默认提到 3h。
SCHED_RCVTIMEO_MS = int(os.environ.get("SGLANG_DIFFUSION_SCHED_RCVTIMEO_MS", "10800000"))
```

然后把两处 `6000000` 换成 `SCHED_RCVTIMEO_MS`（`:78` 与 `:178`，别动 ping 的 `2000`）。

**最小改动做法（不想动结构时）**，Dockerfile 里加一层：

```dockerfile
RUN sed -i 's/zmq\.RCVTIMEO, 6000000/zmq.RCVTIMEO, 10800000/g' \
      /sgl-workspace/sglang/python/sglang/multimodal_gen/runtime/scheduler_client.py && \
    grep -n "RCVTIMEO" /sgl-workspace/sglang/python/sglang/multimodal_gen/runtime/scheduler_client.py
```

⚠️ 行号按 tag 漂移：`v0.5.21` 里位置可能与本文标注的 78/178 不同，**用正则/上下文定位，不要写死行号**。build 时那层 `grep` 输出就是第一道自检。

compose 侧（若采用 env 方案）：

```yaml
    environment:
      - SGLANG_DIFFUSION_SCHED_RCVTIMEO_MS=10800000   # 3h
```

### 4.2 vLLM 镜像（base 已改为 `vllm/vllm-omni:v0.31.0rc1`）

> 下文代码行号取自旧镜像 `minimax-h3-vllm:latest`（旧 base `vllm/vllm-omni:minimax-h3` + clone 的 vllm-omni `main`）。
> 新 base 已内置 vllm-omni，行号/默认值可能漂，重建后按 §6 重新 grep 核对。

实测代码：

```
/opt/vllm-omni/vllm_omni/entrypoints/openai/api_server.py:3041
    VIDEO_SYNC_TIMEOUT_S = float(os.environ.get("VLLM_OMNI_VIDEO_SYNC_TIMEOUT", 600.0))
:3545  await asyncio.wait_for(handler.generate_video_bytes(...), timeout=VIDEO_SYNC_TIMEOUT_S)
:3558  HTTPException(504, "Video generation timed out after {N}s.")
```

落地要点：

1. **无需改代码**，但 **env 一定要显式设置**：默认只有 `600s`，任何 >10min 的 sync 生成都会 504。官方 recipe 文档里常用 `1800`，本仓库现用 `14400`（4h）。
   - 现状已覆盖：`Dockerfile.vllm` CMD 内 `VLLM_OMNI_VIDEO_SYNC_TIMEOUT=14400`（L116）、`docker-compose.vllm.5090.yml` L86、`docker-compose.vllm.a100.yml` L117。
   - **该值在模块 import 时读取**，只能进程启动前设置，运行期改 env 无效。
   - 若重建后改用自定义 `command:`/`entrypoint:` 覆盖 CMD，务必把 env 放进 `environment:`，否则会静默回落 600s。
2. 基于 `vllm/vllm-omni:v0.31.0rc1` 重建时，vllm-omni 与 MiniMax-H3 handler 均由基础镜像内置，**不再 clone 源码 / 不再覆盖 `PYTHONPATH`**（现行 `Dockerfile.vllm` 已如此）。若日后改回以 `vllm/vllm-openai` 作 base，才需要重新 `git clone vllm-omni` + `ENV PYTHONPATH=/opt/vllm-omni:...`；严格可复现建议把 `FROM` 写成镜像 digest（rc 预发布 tag 可能被重新 push）。
3. `core/sched/omni_scheduler_mixin.py` 里还有一个 `VLLM_OMNI_INPUT_WAIT_TIMEOUT_S`（默认 600s，超时把请求标 `FINISHED_ERROR`）。**与 H3 无关**：它只作用于 `uses_full_payload_input_coordinator()` 白名单阶段（全是 Qwen/CosyVoice/TTS 等音频模型），H3 走 `vllm_omni/diffusion/` 引擎，不在该路径。重建后若换 vllm-omni 版本，可复查该白名单是否加入了 H3。
4. vLLM 侧不存在 sglang 那种「跨进程 REQ/REPLY 死等」硬编码；`diffusion/` 下的 timeout 都是 RPC join / 轮询粒度（`_ASYNC_OUTPUT_THREAD_JOIN_TIMEOUT_S=10`、`mq.dequeue(timeout=1.0)` 等），不会截断长生成。

---

## 5. 客户端脚本侧参数（已统一，重建镜像时不用动）

所有 `scripts/*.sh` 现在都把 stdout+stderr 同步写入日志，并把长耗时网络等待提到 3 小时：

| 变量 | 默认 | 作用范围 |
|---|---|---|
| `LOG_DIR` / `LOG_FILE` / `LOG_NAME` | `logs` / `logs/{脚本名}-{时间戳}.log` | 全部脚本；`logs/` 已加 `.gitignore` |
| `REQUEST_TIMEOUT` | `10800` | sync 端点 curl `--max-time`（fl2va/t2va/ref2va-request-file/ref2va-story 系列） |
| `POLL_TIMEOUT` | `10800`（fl2va-request-file、ref2va-request-sglang）；`14400`（story-sglang、jiaoxintong-sglang 单段） | 异步 job 轮询上限 |
| `POLL_INTERVAL` | `5` | 轮询间隔 |
| `DOWNLOAD_TIMEOUT` | `10800` | 批量 sglang 脚本的视频下载上限 |
| `SERVER_WAIT_RETRIES` × `SERVER_WAIT_INTERVAL` | `90 × 10` ≈ 15min | 等待服务端/模型重载 |

示例（一次 3 小时上限、日志固定名的长跑）：

```bash
LOG_FILE=logs/jiaoxintong.log REQUEST_TIMEOUT=10800 POLL_TIMEOUT=14400 \
  bash scripts/ref2va-jiaoxintong-sglang.sh
```

注意：这些只是**客户端肯等多久**，不会让 sglang 那 100 分钟变长；服务端 patch 后两侧才自洽。

---

## 6. 重建后的验收清单（按序执行，全绿才算完）

```bash
# 1) patch 是否落在「运行时真正 import 的那个文件」上
docker run --rm --entrypoint bash <sglang-img> -c \
  'python3 -c "import sglang,os;print(os.path.dirname(sglang.__file__))"; \
   grep -n "RCVTIMEO" /sgl-workspace/sglang/python/sglang/multimodal_gen/runtime/scheduler_client.py'
#    期望：不再有 6000000；ping 的 2000 保留

# 2) 行为级验证（比 1 更可信）：把上限压到 5s，发一段正常请求应在 ~5s 内失败而不是 100min
#    临时 sed 成 5000 起服务 → 提交 /v1/videos → 观察 job 变 failed 的耗时 ≈5s；验证完还原
docker compose exec -T minimax-h3-sglang bash -c \
  'grep -n "RCVTIMEO" /sgl-workspace/sglang/python/sglang/multimodal_gen/runtime/scheduler_client.py'

# 3) 真长跑：单段 >100min 的任务不再被标 failed（服务端日志无 "Scheduler did not respond in time."）
#    客户端日志（logs/*.log）应连续显示 status: running 直到 completed

# 4) vLLM：确认 env 已生效（默认 600 是个坑）
docker exec minimax-h3-vllm printenv | grep VLLM_OMNI_VIDEO_SYNC_TIMEOUT     # 期望 14400

# 5) 兜底链路回归：故意在 completed 前后各跑一次下载，确认 ✓ 兜底拿到视频 的路径仍工作
```

---

## 7. 未决 / 风险提示

- **>3h 的单段**仍然会被新上限截断；超出时优先分段生成再拼接（`ref2va-jiaoxintong-sglang.sh` 末尾给了 `ffmpeg concat` 提示）。
- sglang patch 属于**上游代码侵入**：换 `lmsysorg/sglang` 版本或上游把该常量提成配置后，应撤掉 sed/env 改用官方开关，并在本文更新结论。
- 若某段确实需要更久，也可考虑：把 `save_output` 交给 scheduler 侧写盘（需读上游实现确认能否拿到 `output_file_paths`），这样超时后仍有机会从磁盘捞回文件——目前不成立。
- 本轮只核了超时链路，未复核镜像内其它 H3 参数（`--dit-layerwise-resident-layers`、`DLO_RESIDENT_LAYERS`、attention backend 等）；重建时按 `docker-compose*.yml` 与 `Dockerfile.vllm` 注释逐项对齐。
