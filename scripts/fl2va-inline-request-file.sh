#!/usr/bin/env bash
set -euo pipefail

# =========================
# MiniMax-H3 vLLM FL2VA —— 本地图片「内联上传」+ 长提示词「外置文件」版
# =========================
#
# 与 fl2va-inline-request.sh 的区别：
#   1. 提示词从外部文本文件读取（适合多段长文本，无需转义）；
#   2. 其余（multipart 内联上传首帧图、/v1/videos/sync 同步拿 MP4）不变。
#
# 用法：
#   PROMPT_FILE=scripts/prompts/fl2va-bank.txt IMAGE_PATH=/path/first_frame.png \
#     bash scripts/fl2va-inline-request-file.sh
#   PROMPT="临时覆盖文本" bash scripts/fl2va-inline-request-file.sh   # PROMPT 优先级最高
#
# 依据（recipes.vllm.ai MiniMax-H3, 2026-08-09 + 官方 curl 示例）：
# 视频接口主流用法是 multipart `-F`；FL2VA 首帧图作为表单文件字段上传，
# 字段名固定为 `input_reference`（带 ;type=image/png）；有图时比例从首帧继承、可省 width/height。

HOST="${HOST:-54.2.2.1}"
PORT="${PORT:-8000}"
BASE_URL="http://${HOST}:${PORT}"

# 提示词：默认读外置文件；若设置了 PROMPT 环境变量则以它为准
PROMPT_FILE="${PROMPT_FILE:-scripts/prompts/fl2va-bank.txt}"
if [ -z "${PROMPT:-}" ]; then
  [ -f "${PROMPT_FILE}" ] || { echo "错误：PROMPT_FILE 不存在：${PROMPT_FILE}"; exit 1; }
  PROMPT="$(cat "$PROMPT_FILE")"
fi

# 本地首帧图（必填，必须改成你自己的路径）
IMAGE_PATH="${IMAGE_PATH:-/path/to/your/first_frame.png}"

FPS="${FPS:-24}"
STEPS="${STEPS:-50}"
FLOW_SHIFT="${FLOW_SHIFT:-12}"
AUDIO_FLOW_SHIFT="${AUDIO_FLOW_SHIFT:-3}"
DURATION="${DURATION:-5}"            # extra_params.duration（秒；小数也行，如 5.0）
SEED="${SEED:-1101}"
OUTPUT="${OUTPUT:-minimax-h3-fl2va.mp4}"

# 可选：显式分辨率（有首帧图时通常可省略，比例从图继承）。需要时用 WIDTH/HEIGHT 传入。
WIDTH="${WIDTH:-}"
HEIGHT="${HEIGHT:-}"

echo "========================================"
echo "MiniMax-H3 vLLM FL2VA (inline upload, prompt from file)"
echo "========================================"
echo "Server      : ${BASE_URL}"
echo "Prompt file : ${PROMPT_FILE}"
echo "Image       : ${IMAGE_PATH}"
echo "FPS         : ${FPS}"
echo "Steps       : ${STEPS}"
echo "Duration    : ${DURATION}s"
echo "Seed        : ${SEED}"
echo "Output      : ${OUTPUT}"
echo "========================================"

[ -f "${IMAGE_PATH}" ] || { echo "错误：IMAGE_PATH 不存在：${IMAGE_PATH}"; exit 1; }

# 1. 健康检查
echo "[1/2] Checking server..."
curl -sS "${BASE_URL}/health" > /dev/null
echo "Server is healthy."

# 2. 内联上传首帧图并生成（同步返回 MP4）
echo "[2/2] Generating FL2VA video (inline upload)..."
cmd=(curl -f -sS -X POST "${BASE_URL}/v1/videos/sync"
  -F "prompt=${PROMPT}"
  -F "fps=${FPS}"
  -F "num_inference_steps=${STEPS}"
  -F "flow_shift=${FLOW_SHIFT}"
  -F "seed=${SEED}"
  -F "extra_params={\"task\":\"fl2va\",\"duration\":${DURATION},\"audio_flow_shift\":${AUDIO_FLOW_SHIFT}}"
  -F "input_reference=@${IMAGE_PATH};type=image/png"
  -o "${OUTPUT}")
# 可选分辨率（设置 WIDTH/HEIGHT 后追加）
if [ -n "${WIDTH}" ] && [ -n "${HEIGHT}" ]; then
  cmd+=(-F "width=${WIDTH}" -F "height=${HEIGHT}")
fi
"${cmd[@]}"

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
