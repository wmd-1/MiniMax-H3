#!/usr/bin/env bash
set -euo pipefail

# =========================
# MiniMax-H3 vLLM Ref2VA（参考图 -> 视频 + 音频）—— 长提示词「外置文件」版
# =========================
#
# 依据下方 curl 封装；与 t2va/fl2va 系列脚本风格一致，唯一区别是：
#   提示词从外部文本文件读取（适合多段长文本/中文/引号/换行，无需转义）。
#
# 用法：
#   PROMPT_FILE=scripts/prompts/ref2va-bank.txt REF_IMAGE=/path/ref.png \
#     bash scripts/ref2va-request-file.sh
#   PROMPT="临时文本" REF_IMAGE=/path/ref.png bash scripts/ref2va-request-file.sh   # PROMPT 优先
#
# 协议约束（依据原 curl）：
#   1. 端点 /v1/videos/sync，同步返回 MP4（无需轮询）。
#   2. 参考图字段名固定为 input_reference，内联上传用 ;type=image/png。
#   3. extra_params 字段名（不是 extra_args）；task="ref2va"；duration 用小数(如 8.0)；
#      audio_flow_shift 用小数(如 3.0)。
#   4. aspect_ratio=adaptive；short_edge=768（Ref2VA 自适应比例，不传 width/height）。
#   5. 服务端需以 --task-type ref2va 启动。

HOST="${HOST:-localhost}"
PORT="${PORT:-8000}"
BASE_URL="http://${HOST}:${PORT}"

# 提示词：默认读外置文件；设置了 PROMPT 环境变量则以它为准
PROMPT_FILE="${PROMPT_FILE:-scripts/prompts/ref2va-bank.txt}"
if [ -z "${PROMPT:-}" ]; then
  [ -f "${PROMPT_FILE}" ] || { echo "错误：PROMPT_FILE 不存在：${PROMPT_FILE}"; exit 1; }
  PROMPT="$(cat "$PROMPT_FILE")"
fi

# 参考图（必填）
REF_IMAGE="${REF_IMAGE:-}"
[ -n "${REF_IMAGE}" ] || { echo "错误：请设置 REF_IMAGE=/path/to/reference.png"; exit 1; }
[ -f "${REF_IMAGE}" ] || { echo "错误：REF_IMAGE 不存在：${REF_IMAGE}"; exit 1; }

ASPECT_RATIO="${ASPECT_RATIO:-adaptive}"
SHORT_EDGE="${SHORT_EDGE:-768}"
FPS="${FPS:-24}"
STEPS="${STEPS:-50}"
FLOW_SHIFT="${FLOW_SHIFT:-12}"
AUDIO_FLOW_SHIFT="${AUDIO_FLOW_SHIFT:-3}"
DURATION="${DURATION:-8}"            # extra_params.duration（小数也行，如 8.0 / 15.0）
SEED="${SEED:-3100}"
OUTPUT="${OUTPUT:-ref2va_image.mp4}"

# 根据扩展名推断图片 MIME（用于 ;type=）
img_ext="${REF_IMAGE##*.}"
case "${img_ext,,}" in
  png)        IMG_TYPE="image/png" ;;
  jpg|jpeg)   IMG_TYPE="image/jpeg" ;;
  webp)       IMG_TYPE="image/webp" ;;
  bmp)        IMG_TYPE="image/bmp" ;;
  gif)        IMG_TYPE="image/gif" ;;
  *)          IMG_TYPE="application/octet-stream" ;;
esac

echo "========================================"
echo "MiniMax-H3 vLLM Ref2VA (reference -> video+audio, prompt from file)"
echo "========================================"
echo "Server       : ${BASE_URL}"
echo "Prompt file  : ${PROMPT_FILE}"
echo "Ref image    : ${REF_IMAGE} (${IMG_TYPE})"
echo "Aspect Ratio : ${ASPECT_RATIO}"
echo "Short Edge   : ${SHORT_EDGE}"
echo "FPS          : ${FPS}"
echo "Steps        : ${STEPS}"
echo "Flow Shift   : ${FLOW_SHIFT}"
echo "Audio Shift  : ${AUDIO_FLOW_SHIFT}"
echo "Duration     : ${DURATION}s"
echo "Seed         : ${SEED}"
echo "Output       : ${OUTPUT}"
echo "========================================"

# 1. 健康检查
echo "[1/2] Checking server..."
curl -sS "${BASE_URL}/health" > /dev/null
echo "Server is healthy."

# 2. Ref2VA 生成（multipart 内联上传参考图，sync 同步返回 MP4）
echo "[2/2] Generating Ref2VA video..."
cmd=(curl -f -sS -X POST "${BASE_URL}/v1/videos/sync"
  -F "prompt=${PROMPT}"
  -F "aspect_ratio=${ASPECT_RATIO}"
  -F "short_edge=${SHORT_EDGE}"
  -F "fps=${FPS}"
  -F "num_inference_steps=${STEPS}"
  -F "flow_shift=${FLOW_SHIFT}"
  -F "seed=${SEED}"
  -F "extra_params={\"task\":\"ref2va\",\"duration\":${DURATION},\"audio_flow_shift\":${AUDIO_FLOW_SHIFT}}"
  -F "input_reference=@${REF_IMAGE};type=${IMG_TYPE}"
  -o "${OUTPUT}")
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
