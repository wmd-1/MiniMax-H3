#!/usr/bin/env bash
set -euo pipefail

# 前置依赖：jq（仓库自带示例脚本同样依赖）
command -v jq >/dev/null 2>&1 || {
  echo "需要 jq 来构造/解析 JSON。请先安装："
  echo "  apt-get install -y jq    # Debian/Ubuntu"
  echo "  brew install jq          # macOS"
  exit 1
}

# =========================
# MiniMax-H3 vLLM FL2VA (首帧图 -> 视频 + 音频) —— 长提示词「外置文件」版
# =========================
#
# 与 fl2va-request.sh 的唯一区别：提示词从外部文本文件读取，而非写死在脚本里。
# 适合多段长文本（含中文/引号/<d>/换行），配合 jq --arg 安全构造 JSON，无需转义。
#
# 用法：
#   PROMPT_FILE=scripts/prompts/fl2va-bank.txt IMAGE_URI=http://.../frame.png \
#     bash scripts/fl2va-request-file.sh
#   PROMPT="临时覆盖文本" bash scripts/fl2va-request-file.sh   # PROMPT 优先级最高
#
# 协议说明同 fl2va-request.sh：
#   - JSON body；conditions[0] 传首帧图 URL（role:keyframe）。
#   - FL2VA 的 target.aspect_ratio="auto" 合法（比例从首帧图继承）。
#   - 服务端需以 --task-type fl2va 启动。

HOST="${HOST:-54.2.2.1}"
PORT="${PORT:-8000}"
BASE_URL="http://${HOST}:${PORT}"

# 提示词：默认读外置文件；若设置了 PROMPT 环境变量则以它为准
PROMPT_FILE="${PROMPT_FILE:-scripts/prompts/fl2va-bank.txt}"
if [ -z "${PROMPT:-}" ]; then
  [ -f "${PROMPT_FILE}" ] || { echo "错误：PROMPT_FILE 不存在：${PROMPT_FILE}"; exit 1; }
  PROMPT="$(cat "$PROMPT_FILE")"
fi

# 首帧图（必须是服务端能访问到的 URL）
IMAGE_URI="${IMAGE_URI:-https://cdn.hailuoai.com/prod/hailuo_demo/testsets/H3_AA_I2VA/gallery/sr_v17_variants_seed42_43_20260724/inputs/4a3a90bf9100_KDmcbkhzYo5sjjxr9FqcVmWVnzb.png}"

SHORT_EDGE="${SHORT_EDGE:-768}"      # 短边分辨率；首帧 1344x768 的短边就是 768
ASPECT_RATIO="${ASPECT_RATIO:-auto}"  # FL2VA 跟首帧图，用 auto
DURATION="${DURATION:-5}"            # duration_seconds（4-15）
SEED="${SEED:-0}"
OUTPUT="${OUTPUT:-minimax-h3-fl2va.mp4}"

echo "========================================"
echo "MiniMax-H3 vLLM FL2VA (first frame -> video+audio, prompt from file)"
echo "========================================"
echo "Server      : ${BASE_URL}"
echo "Prompt file : ${PROMPT_FILE}"
echo "Image URI   : ${IMAGE_URI}"
echo "Short Edge  : ${SHORT_EDGE}"
echo "Aspect Ratio: ${ASPECT_RATIO}"
echo "Duration    : ${DURATION}s"
echo "Seed        : ${SEED}"
echo "Output      : ${OUTPUT}"
echo "========================================"

# 1. 健康检查
echo "[1/3] Checking server..."
curl -sS "${BASE_URL}/health" > /dev/null
echo "Server is healthy."

# 2. 提交 FL2VA 任务（异步：返回 video id）
# 用 jq 安全构造 JSON，避免中文/引号/换行破坏 body
echo "[2/3] Submitting FL2VA job..."
response=$(
  jq -n \
    --arg prompt "$PROMPT" \
    --arg uri "$IMAGE_URI" \
    --argjson short_edge "$SHORT_EDGE" \
    --arg aspect_ratio "$ASPECT_RATIO" \
    --argjson duration "$DURATION" \
    --argjson seed "$SEED" \
    '{
      task: "fl2va",
      prompt: $prompt,
      conditions: [
        { type: "image", uri: $uri, role: "keyframe", frame_index: 0 }
      ],
      target: {
        short_edge: $short_edge,
        aspect_ratio: $aspect_ratio,
        duration_seconds: $duration
      },
      seed: $seed
    }' |
  curl -f -sS \
    --request POST \
    --url "${BASE_URL}/v1/videos" \
    --header 'Content-Type: application/json' \
    --data-binary @-
)
video_id=$(printf '%s\n' "$response" | jq -er '.id')
echo "Job id: ${video_id}"

# 3. 轮询状态并下载
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

curl -f -sS \
  --request GET \
  --url "${BASE_URL}/v1/videos/${video_id}/content" \
  --output "${OUTPUT}"

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
