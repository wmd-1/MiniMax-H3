#!/usr/bin/env bash
set -euo pipefail

# =========================
# MiniMax-H3 vLLM T2VA —— 长提示词「外置文件」版
# =========================
#
# 与 t2va-request.sh 的唯一区别：提示词从外部文本文件读取，而非写死在脚本里。
# 适合嵌入多段长文本（含中文/引号/<d>/换行），无需任何转义。
#
# 用法：
#   PROMPT_FILE=scripts/prompts/t2va-bank.txt bash scripts/t2va-request-file.sh
#   PROMPT="临时覆盖文本" bash scripts/t2va-request-file.sh   # PROMPT 优先级最高
#
# 其他协议约束同 t2va-request.sh：
#   1. 字段名是 extra_params 不是 extra_args；2. aspect_ratio 是顶层字段；
#   3. seconds 只收整数秒；4. T2VA aspect_ratio ∈ {21:9,16:9,4:3,1:1,3:4,9:16}；
#   5. width/height 与 aspect_ratio 一致（16:9 → 1344x756）；6. 不带 task。

HOST="${HOST:-54.2.2.1}"
PORT="${PORT:-8000}"

# 提示词：默认读外置文件；若设置了 PROMPT 环境变量则以它为准
PROMPT_FILE="${PROMPT_FILE:-scripts/prompts/t2va-bank.txt}"
if [ -z "${PROMPT:-}" ]; then
  [ -f "${PROMPT_FILE}" ] || { echo "错误：PROMPT_FILE 不存在：${PROMPT_FILE}"; exit 1; }
  PROMPT="$(cat "$PROMPT_FILE")"
fi

# 16:9 分辨率，与下面的 aspect_ratio=16:9 保持一致
WIDTH="${WIDTH:-1344}"
HEIGHT="${HEIGHT:-756}"
ASPECT_RATIO="${ASPECT_RATIO:-16:9}"

FPS="${FPS:-24}"
STEPS="${STEPS:-50}"
FLOW_SHIFT="${FLOW_SHIFT:-12}"
AUDIO_FLOW_SHIFT="${AUDIO_FLOW_SHIFT:-3}"
DURATION="${DURATION:-5}"            # 整数秒（seconds 不接受小数）
SEED="${SEED:-1101}"

OUTPUT="${OUTPUT:-minimax-h3-t2va.mp4}"

BASE_URL="http://${HOST}:${PORT}"

echo "========================================"
echo "MiniMax-H3 vLLM T2VA (prompt from file)"
echo "========================================"
echo "Server       : ${BASE_URL}"
echo "Prompt file  : ${PROMPT_FILE}"
echo "Size         : ${WIDTH}x${HEIGHT}"
echo "Aspect Ratio : ${ASPECT_RATIO}"
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

# 2. T2VA 生成（multipart：prompt 直接作为表单字段，中文/换行由 curl 处理）
echo "[2/2] Generating T2VA video..."
curl -sS \
  -X POST "${BASE_URL}/v1/videos/sync" \
  -F "prompt=${PROMPT}" \
  -F "width=${WIDTH}" \
  -F "height=${HEIGHT}" \
  -F "fps=${FPS}" \
  -F "num_inference_steps=${STEPS}" \
  -F "flow_shift=${FLOW_SHIFT}" \
  -F "aspect_ratio=${ASPECT_RATIO}" \
  -F "seconds=${DURATION%%.*}" \
  -F "extra_params={\"audio_flow_shift\":${AUDIO_FLOW_SHIFT}}" \
  -F "seed=${SEED}" \
  -o "${OUTPUT}"

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
