#!/usr/bin/env bash
set -euo pipefail

command -v jq >/dev/null 2>&1 || {
  echo "需要 jq。请先安装： apt-get install -y jq  或  brew install jq"; exit 1
}

# =========================
# MiniMax-H3 sglang Ref2VA —— 长提示词「外置文件」+ 参考图 conditions（JSON body 异步）
# =========================
#
# 协议严格对齐官方调用示例（sglang 服务端，默认 :30010）：
#   POST /v1/videos (JSON body) -> 取 .id -> 轮询 GET /v1/videos/{id} -> 下载 GET /v1/videos/{id}/content
#
# 关键（官方示例）：
#   - 参考图/音频用 conditions[]，uri 用 **file:///绝对路径**（服务端读自己文件系统），不是 data URI / http。
#     本地文件会自动转成 file://<绝对路径>；传 http(s) URL 则原样保留。
#   - 必带顶层字段：model / seconds / task / num_outputs_per_prompt / num_inference_steps /
#     flow_shift / audio_flow_shift；target: {short_edge, aspect_ratio:"auto", duration_seconds}。
#
# 用法：
#   PROMPT_FILE=scripts/prompts/ref2va-bank.txt \
#   REF_IMAGE_URIS="dxb.png hxr.png logo.png" \
#   bash scripts/ref2va-request-sglang.sh
#
# 其它：DURATION(秒) / SHORT_EDGE(768) / ASPECT_RATIO(auto) / SEED(3101) / HOST / PORT(30010)
#   FLOW_SHIFT(12.0) / AUDIO_FLOW_SHIFT(3.0) / STEPS(50) / NUM_OUTPUTS(1) / MODEL(MiniMaxAI/MiniMax-H3)

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-30010}"
BASE_URL="http://${HOST}:${PORT}"

PROMPT_FILE="${PROMPT_FILE:-scripts/prompts/ref2va-bank.txt}"
if [ -z "${PROMPT:-}" ]; then
  [ -f "${PROMPT_FILE}" ] || { echo "错误：PROMPT_FILE 不存在：${PROMPT_FILE}"; exit 1; }
  PROMPT="$(cat "$PROMPT_FILE")"
fi

REF_IMAGE_URIS="${REF_IMAGE_URIS:-}"
[ -n "${REF_IMAGE_URIS}" ] || { echo "错误：请设置 REF_IMAGE_URIS（本地路径或 URL，空格分隔）"; exit 1; }
read -ra REF_URIS <<< "${REF_IMAGE_URIS}"

MODEL="${MODEL:-MiniMaxAI/MiniMax-H3}"
SHORT_EDGE="${SHORT_EDGE:-768}"
ASPECT_RATIO="${ASPECT_RATIO:-auto}"
DURATION="${DURATION:-8}"
SECONDS_INT="${DURATION%%.*}"         # 顶层 seconds 取整数（官方示例 seconds:5）
STEPS="${STEPS:-50}"
FLOW_SHIFT="${FLOW_SHIFT:-12.0}"
AUDIO_FLOW_SHIFT="${AUDIO_FLOW_SHIFT:-3.0}"
NUM_OUTPUTS="${NUM_OUTPUTS:-1}"
SEED="${SEED:-3101}"
OUTPUT="${OUTPUT:-ref2va_sglang.mp4}"

TMPD="$(mktemp -d)"
cleanup() { rm -rf "$TMPD"; }
trap cleanup EXIT

# 把引用解析成 condition；本地文件 -> file://<绝对路径>，URL 原样
to_uri() {
  local u="$1"
  if [[ "$u" == http* || "$u" == file://* ]]; then
    printf '%s' "$u"
  else
    printf 'file://%s' "$(realpath -m "$u")"
  fi
}

build_conditions() {
  local json='[]'
  for u in "$@"; do
    local uri; uri="$(to_uri "$u")"
    json=$(printf '%s' "$json" | jq --arg uri "$uri" '. + [{type:"image", uri:$uri, role:"reference"}]')
  done
  printf '%s' "$json"
}

echo "========================================"
echo "MiniMax-H3 sglang Ref2VA (JSON body, async, prompt from file)"
echo "========================================"
echo "Server        : ${BASE_URL}"
echo "Prompt file   : ${PROMPT_FILE}"
echo "Ref images    : ${REF_IMAGE_URIS}"
echo "Model         : ${MODEL}"
echo "Short Edge    : ${SHORT_EDGE}"
echo "Aspect Ratio  : ${ASPECT_RATIO}"
echo "Duration      : ${DURATION}s (seconds=${SECONDS_INT})"
echo "Steps/Flow/Aud: ${STEPS}/${FLOW_SHIFT}/${AUDIO_FLOW_SHIFT}"
echo "Seed          : ${SEED}"
echo "Output        : ${OUTPUT}"
echo "========================================"

# 1. 健康检查
echo "[1/3] Checking server..."
curl -sS "${BASE_URL}/health" > /dev/null
echo "Server is healthy."

# 2. 提交任务（大提示词从文件读，避免 argv 过长）
echo "[2/3] Submitting Ref2VA job (sglang)..."
conditions_json="$(build_conditions "${REF_URIS[@]}")"
jq -Rs --slurpfile cond <(printf '%s' "$conditions_json") \
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
  "$PROMPT_FILE" > "$TMPD/body.json"

status=$(curl -sS -o "$TMPD/resp_body.bin" -w '%{http_code}' \
  -X POST "${BASE_URL}/v1/videos" \
  --header 'Content-Type: application/json' \
  --data-binary @"$TMPD/body.json")
echo "POST /v1/videos -> HTTP ${status}"
if [ "$status" != "200" ] && [ "$status" != "201" ]; then
  echo "---- 服务端返回体（错误原因）----"
  cat "$TMPD/resp_body.bin"; echo
  echo "[bad request] 已中止。"
  exit 1
fi

video_id=$(jq -er '.id' "$TMPD/resp_body.bin")
echo "Job id: ${video_id}"

# 3. 轮询 + 下载
echo "[3/3] Waiting for completion..."
while true; do
  status=$(curl -sS "${BASE_URL}/v1/videos/${video_id}" | jq -r '.status')
  echo "  status: ${status}"
  case "$status" in
    completed) break ;;
    failed|error|cancelled) echo "Job ${status}."; exit 1 ;;
  esac
  sleep 5
done

curl -sS -X GET "${BASE_URL}/v1/videos/${video_id}/content" -o "${OUTPUT}"

echo
echo "========================================"
echo "Generation completed"
echo "========================================"
ls -lh "${OUTPUT}"

if command -v ffprobe >/dev/null 2>&1; then
  echo
  echo "Media info:"
  ffprobe -v error \
    -show_entries stream=index,codec_name,width,height,r_frame_rate,sample_rate,channels \
    -of json "${OUTPUT}"
fi
