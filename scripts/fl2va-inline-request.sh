#!/usr/bin/env bash
set -euo pipefail

# =========================
# MiniMax-H3 vLLM FL2VA —— 本地图片「内联上传」版
# =========================
#
# 与 fl2va-request.sh（JSON body + conditions[].uri=URL）不同，本脚本用
# vllm-omni 主推的 multipart 表单风格，把本地首帧图作为文件字段随请求
# 直接内联上传（无需把图片先托管成 URL）。
#
# 依据（recipes.vllm.ai MiniMax-H3 配方页 + 官方 curl 示例，2026-08）：
#   - 视频接口主流用法是 multipart `-F`。
#   - FL2VA 首帧图作为表单文件字段上传，字段名固定为 `input_reference`
#     （带 ;type=image/png）；有图时比例从首帧继承，可省 width/height。
#   - 模型特定参数放在 `extra_params` 这个 JSON 字符串里
#     （task / duration(秒,可为小数) / audio_flow_shift）。

HOST="${HOST:-54.2.2.1}"
PORT="${PORT:-8000}"
BASE_URL="http://${HOST}:${PORT}"

# 本地首帧图（必填，必须改成你自己的路径）
IMAGE_PATH="${IMAGE_PATH:-/path/to/your/first_frame.png}"

PROMPT="${PROMPT:-夜晚，一间安静的卧室里，主人正在熟睡。三只猫排成一列从门口走进来，第一只猫吹着金色小号，第二只猫吹着小型长号，第三只猫吹着铜管乐器，整齐滑稽地演奏。中景平稳跟随，随后三只猫同时停奏转身离开，主人始终未醒。声音含轻微脚步声、滑稽铜管声与安静夜间环境声。}"

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
echo "MiniMax-H3 vLLM FL2VA (inline upload)"
echo "========================================"
echo "Server      : ${BASE_URL}"
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
