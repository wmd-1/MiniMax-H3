#!/usr/bin/env bash
set -euo pipefail

command -v jq >/dev/null 2>&1 || {
  echo "需要 jq。请先安装： apt-get install -y jq  或  brew install jq"; exit 1
}

# =========================
# MiniMax-H3 sglang Ref2VA —— 4 段分镜 + 3 张参考图（按 subject）批量生成（JSON body 异步）
# =========================
#
# 协议严格对齐官方调用示例（sglang :30010）。每段发送全部 3 张参考图
# （dxb/hxr/logo 对应 <Subject 1/2/3>，每段都引用它们）。
# 参考图用 file://<绝对路径>（服务端读自己文件系统）；本地文件自动转换，http(s) 原样。
#
# 用法：
#   SEGMENT_FILES="seg1.txt seg2.txt seg3.txt seg4.txt" \
#   REF_IMAGE_URIS="dxb.png hxr.png logo.png" \
#   bash scripts/ref2va-story-sglang.sh
#
# 不传参默认：段 scripts/prompts/story/seg{1..4}.txt；参考图 dxb.png/hxr.png/logo.png（当前目录）。
# 其它：DURATION(15) / SHORT_EDGE(768) / ASPECT_RATIO(auto) / SEED(3101) / HOST / PORT(30010)
#   FLOW_SHIFT(12.0) / AUDIO_FLOW_SHIFT(3.0) / STEPS(50) / NUM_OUTPUTS(1) / MODEL(MiniMaxAI/MiniMax-H3)

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-30010}"
BASE_URL="http://${HOST}:${PORT}"

MODEL="${MODEL:-MiniMaxAI/MiniMax-H3}"
DURATION="${DURATION:-15}"
SECONDS_INT="${DURATION%%.*}"
SHORT_EDGE="${SHORT_EDGE:-768}"
ASPECT_RATIO="${ASPECT_RATIO:-auto}"
STEPS="${STEPS:-50}"
FLOW_SHIFT="${FLOW_SHIFT:-12.0}"
AUDIO_FLOW_SHIFT="${AUDIO_FLOW_SHIFT:-3.0}"
NUM_OUTPUTS="${NUM_OUTPUTS:-1}"
SEED="${SEED:-3101}"

if [ -z "${SEGMENT_FILES:-}" ]; then
  SEGMENT_DIR="${SEGMENT_DIR:-scripts/prompts/story}"
  SEGMENT_FILES=()
  for i in 1 2 3 4; do SEGMENT_FILES+=("${SEGMENT_DIR}/seg${i}.txt"); done
fi
[ "${#SEGMENT_FILES[@]}" -eq 1 ] && read -ra SEGMENT_FILES <<< "${SEGMENT_FILES[0]}"

REF_IMAGE_URIS="${REF_IMAGE_URIS:-dxb.png hxr.png logo.png}"
read -ra REF_URIS <<< "${REF_IMAGE_URIS}"

N_SEG=${#SEGMENT_FILES[@]}
N_REF=${#REF_URIS[@]}

for f in "${SEGMENT_FILES[@]}"; do
  [ -f "$f" ] || { echo "错误：段提示词文件不存在：$f"; exit 1; }
done
for u in "${REF_URIS[@]}"; do
  [ -f "$u" ] || [[ "$u" == http* ]] || [[ "$u" == file://* ]] || { echo "错误：参考图不存在（也不是 URL）：：$u"; exit 1; }
done

TMPD="$(mktemp -d)"
cleanup() { rm -rf "$TMPD"; }
trap cleanup EXIT

to_uri() {
  local u="$1"
  if [[ "$u" == http* || "$u" == file://* ]]; then
    printf '%s' "$u"
  else
    printf 'file://%s' "$(realpath -m "$u")"
  fi
}

# 构建 conditions.json（本地文件 -> file:// 绝对路径）
# 注意：须生成真正的 JSON 数组 [ {...}, {...} ]，不能合并成单个对象。
conditions_json='[]'
for u in "${REF_URIS[@]}"; do
  uri="$(to_uri "$u")"
  conditions_json=$(printf '%s' "$conditions_json" | jq --arg uri "$uri" '. + [{type:"image", uri:$uri, role:"reference"}]')
done
printf '%s' "$conditions_json" > "$TMPD/conditions.json"

echo "========================================"
echo "MiniMax-H3 sglang Ref2VA —— 分镜批量生成"
echo "========================================"
echo "Server     : ${BASE_URL}"
echo "Model      : ${MODEL}"
echo "段数 / 图数: ${N_SEG} / ${N_REF}"
echo "Duration   : ${DURATION}s/段 (seconds=${SECONDS_INT})"
echo "Aspect     : ${ASPECT_RATIO}  ShortEdge: ${SHORT_EDGE}"
echo "----------------------------------------"
for ((s=0; s<N_SEG; s++)); do
  echo "  段$((s+1)) <- ${SEGMENT_FILES[s]}  (${N_REF} 张参考图: ${REF_IMAGE_URIS})"; done
echo "========================================"

# =========================
# 韧性配置（可被环境变量覆盖）
#   真实场景：服务端 sglang 最终会把视频生成到磁盘，但 scheduler/client 有
#   约 100 分钟的超时，到时把任务标成 failed、客户端停止。因此脚本策略是：
#     - 状态报 failed/超时但服务端仍在线 → 不重提（重提会重复生成同一个视频），
#       而是继续等并检查视频是否已落盘（url/file_path/content），拿到即成功。
#     - 仅当服务端真的挂了（job 丢失，curl 拿不到状态）→ 才重提该段。
# =========================
MAX_RETRIES="${MAX_RETRIES:-5}"                 # 仅用于「服务端崩溃/job 丢失」时最多重提次数
POLL_INTERVAL="${POLL_INTERVAL:-5}"             # 轮询间隔（秒）
POLL_TIMEOUT="${POLL_TIMEOUT:-14400}"           # 单段最长等待（秒，默认 4h），覆盖 100+min 生成；超时则放弃该段（不重提）
SERVER_WAIT_RETRIES="${SERVER_WAIT_RETRIES:-90}" # 等待服务端重启的最大次数
SERVER_WAIT_INTERVAL="${SERVER_WAIT_INTERVAL:-10}" # 每次等待间隔（秒）→ 最长约 15min 等模型重载

echo "[0/${N_SEG}] 等待服务端就绪（最长约 $((SERVER_WAIT_RETRIES*SERVER_WAIT_INTERVAL/60))min）..."
wait_for_server() {
  local i
  for ((i=1; i<=SERVER_WAIT_RETRIES; i++)); do
    if curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "${BASE_URL}/health" 2>/dev/null | grep -q 200; then
      return 0
    fi
    echo "    [wait] 服务端未就绪（${i}/${SERVER_WAIT_RETRIES}），${SERVER_WAIT_INTERVAL}s 后重试..."
    sleep "$SERVER_WAIT_INTERVAL"
  done
  return 1
}
if ! wait_for_server; then
  echo "  [warn] 启动检查：服务端在等待期内未就绪，仍会逐段重试。"
fi

# 下载视频：优先响应里的 url，再退 content 端点。返回 0=成功且文件非空
download_video() {  # $1=vid $2=out
  local vid="$1" out="$2"
  local url
  url=$(jq -r '.url // empty' "$TMPD/job_${vid}.json" 2>/dev/null || true)
  if [ -n "$url" ]; then
    echo "    下载 url: ${url}"
    if curl -sS -L --max-time 600 "$url" -o "${out}" 2>/dev/null; then
      [ -s "${out}" ] && return 0
    fi
  fi
  echo "    下载 content 端点..."
  if curl -sS -X GET --max-time 600 "${BASE_URL}/v1/videos/${vid}/content" -o "${out}" 2>/dev/null; then
    [ -s "${out}" ] && return 0
  fi
  return 1
}

build_body() {  # $1=prompt_file  -> $TMPD/body.json
  jq -Rs --slurpfile cond "$TMPD/conditions.json" \
    --arg model "$MODEL" \
    --argjson seconds "$SECONDS_INT" \
    --argjson short_edge "$SHORT_EDGE" \
    --arg aspect_ratio "$ASPECT_RATIO" \
    --argjson duration "$DURATION" \
    --argjson steps "$STEPS" \
    --argjson flow_shift "$FLOW_SHIFT" \
    --argjson audio_flow_shift "$AUDIO_FLOW_SHIFT" \
    --argjson num_outputs "$NUM_OUTPUTS" \
    --argjson seed "$SEED" \
    '{
      model: $model,
      prompt: .,
      seconds: $seconds,
      task: "ref2va",
      conditions: $cond[0],
      target: {short_edge: $short_edge, aspect_ratio: $aspect_ratio, duration_seconds: $duration},
      num_outputs_per_prompt: $num_outputs,
      num_inference_steps: $steps,
      flow_shift: $flow_shift,
      audio_flow_shift: $audio_flow_shift,
      seed: $seed
    }' \
    "$1" > "$TMPD/body.json"
}

# 单段生成（韧性版）。返回 0=成功, 1=最终失败（主循环不会因此中止整个脚本）
#   原则：
#     - 服务端若仍在跑，绝不重提（避免重复生成同一个视频）；
#       状态 failed/超时但视频可能已落盘 → 持续尝试下载，拿到即成功。
#     - 仅当服务端掉线（curl 拿不到状态、job 丢失）→ 才重提该段。
gen_one() {  # $1=prompt_file $2=output
  local pf="$1" out="$2"
  local vid st elapsed http_code resubmits=0

  while true; do
    # 1) 确保服务端在线
    if ! wait_for_server; then
      echo "    [fatal] 等待服务端超时，放弃段：${pf}"
      return 1
    fi

    # 2) 若无活动 job（首次，或上次 job 已丢失），提交
    if [ -z "$vid" ]; then
      build_body "$pf"
      http_code=$(curl -sS -o "$TMPD/resp_body.bin" -w '%{http_code}' --max-time 120 \
        -X POST "${BASE_URL}/v1/videos" \
        --header 'Content-Type: application/json' \
        --data-binary @"$TMPD/body.json" 2>/dev/null || echo "000")
      echo "    POST /v1/videos -> HTTP ${http_code}"
      if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        echo "    ---- 服务端返回体（错误原因）----"
        cat "$TMPD/resp_body.bin" 2>/dev/null; echo
        echo "    [fatal] 提交被拒（HTTP ${http_code}），放弃本段（真实请求错误不靠重试自愈）。"
        return 1
      fi
      vid=$(jq -er '.id' "$TMPD/resp_body.bin" 2>/dev/null || true)
      if [ -z "$vid" ]; then
        echo "    [warn] 响应缺少 id，稍后重试提交..."
        sleep 3
        continue
      fi
      echo "    job id: ${vid}"
      elapsed=0
    fi

    # 3) 轮询一次
    if ! curl -sS --max-time 30 "${BASE_URL}/v1/videos/${vid}" -o "$TMPD/job_${vid}.json" 2>/dev/null; then
      # 服务端掉线 → job 丢失，需重提（受 MAX_RETRIES 限制）
      if [ "$resubmits" -ge "$MAX_RETRIES" ]; then
        echo "    [fatal] 服务端反复掉线，重提已达 ${MAX_RETRIES} 次，放弃本段。"
        return 1
      fi
      resubmits=$((resubmits + 1))
      echo "    [warn] 轮询失败（服务端掉线），job 丢失，将重提（${resubmits}/${MAX_RETRIES}）..."
      vid=""
      sleep 5
      continue
    fi

    st=$(jq -r '.status // empty' "$TMPD/job_${vid}.json" 2>/dev/null || true)
    echo "    status: ${st}  (已等 ${elapsed}s)"

    case "$st" in
      completed)
        if download_video "$vid" "$out"; then
          echo "    ✓ 下载成功：${out}"
          return 0
        fi
        echo "    [warn] completed 但下载失败，继续尝试下载..."
        sleep "$POLL_INTERVAL"; elapsed=$((elapsed + POLL_INTERVAL))
        if [ "$elapsed" -ge "$POLL_TIMEOUT" ]; then
          echo "    [fail] 等待 ${POLL_TIMEOUT}s 后仍无法下载，放弃本段。"
          return 1
        fi
        ;;
      failed|error|cancelled)
        # 关键：scheduler/client 可能因 100min 超时标 failed，但服务端仍在渲染/已落盘。
        # 先尝试直接拿视频（url/file_path/content）；拿到即成功，绝不重提。
        if download_video "$vid" "$out"; then
          echo "    ✓ 兜底拿到视频（尽管 status=${st}）：${out}"
          return 0
        fi
        # 没拿到：服务端还活着、job 还在 → 继续等（可能是 scheduler 误报，视频稍后落盘）
        echo "    [warn] status=${st} 但暂无可下载视频；服务端仍在，继续等待（不重提）..."
        sleep "$POLL_INTERVAL"; elapsed=$((elapsed + POLL_INTERVAL))
        if [ "$elapsed" -ge "$POLL_TIMEOUT" ]; then
          echo "    [fail] 等待 ${POLL_TIMEOUT}s 后仍为 ${st} 且无视频，放弃本段。"
          return 1
        fi
        ;;
      *)  # queued / running / 未知：继续等
        sleep "$POLL_INTERVAL"; elapsed=$((elapsed + POLL_INTERVAL))
        if [ "$elapsed" -ge "$POLL_TIMEOUT" ]; then
          echo "    [fail] 轮询超时 ${POLL_TIMEOUT}s（状态仍为 ${st}），放弃本段。"
          return 1
        fi
        ;;
    esac
  done
}

# ===== 主循环：任一段失败也不中止整个脚本 =====
FAILED=()
for ((s=0; s<N_SEG; s++)); do
  out="story_seg$((s+1)).mp4"
  echo "[$((s+1))/${N_SEG}] 段$((s+1)) -> ${out}"
  if gen_one "${SEGMENT_FILES[s]}" "${out}"; then
    ls -lh "${out}" 2>/dev/null || true
  else
    echo "  !!! 段$((s+1)) 最终失败，继续下一段..."
    FAILED+=("$((s+1))")
  fi
done

echo
echo "========================================"
if [ "${#FAILED[@]}" -eq 0 ]; then
  echo "All segments completed"
else
  echo "完成，但以下段失败：${FAILED[*]}（可单独用 SEGMENT_FILES=... 重跑）"
fi
echo "========================================"
