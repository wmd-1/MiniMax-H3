#!/usr/bin/env bash
set -euo pipefail

# =========================
# MiniMax-H3 vLLM T2VA
# =========================
#
# 注意（vLLM-Omni /v1/videos[/sync] HTTP 协议约束，踩坑记录）：
#   1. 模型特定扩展参数字段名是 `extra_params`，不是 `extra_args`（后者会被静默丢弃）。
#   2. `aspect_ratio` 必须是「顶层字段」，塞进 extra_params 之外无效。
#   3. `seconds` 只接受正整数秒字符串（正则 ^[1-9]\d*$），不能写 5.0。
#   4. T2VA 的 aspect_ratio 只能是 21:9 / 16:9 / 4:3 / 1:1 / 3:4 / 9:16。
#   5. `width/height` 与 `aspect_ratio` 需保持一致（这里用 16:9 的 1344x756）。
#   6. `task` 不是请求字段，由服务端 --task-type 在启动时决定，请求里不要带。

HOST="${HOST:-54.2.2.1}"
PORT="${PORT:-8000}"

PROMPT="${PROMPT:-夜晚，一间安静的卧室里，主人正在熟睡。三只猫排成一列，从卧室门口缓慢走进来。第一只猫吹着金色的小号，第二只猫吹着小型长号，第三只猫吹着铜管乐器。三只猫一边行走一边演奏，动作整齐而滑稽。镜头采用中景，平稳地跟随三只猫移动。突然，三只猫同时停止演奏，迅速转身，依次排队离开卧室。主人始终没有醒来。声音包括轻微的脚步声、铜管乐器的滑稽演奏声，以及安静的夜间环境声。}"

# 16:9 分辨率，与下面的 aspect_ratio=16:9 保持一致
WIDTH="${WIDTH:-1344}"
HEIGHT="${HEIGHT:-756}"
ASPECT_RATIO="${ASPECT_RATIO:-16:9}"

FPS="${FPS:-24}"
STEPS="${STEPS:-50}"
FLOW_SHIFT="${FLOW_SHIFT:-12}"
AUDIO_FLOW_SHIFT="${AUDIO_FLOW_SHIFT:-3}"
# 整数秒（seconds 字段不接受小数，如 5.0）
DURATION="${DURATION:-5}"
SEED="${SEED:-1101}"

OUTPUT="${OUTPUT:-minimax-h3-t2va.mp4}"

BASE_URL="http://${HOST}:${PORT}"

echo "========================================"
echo "MiniMax-H3 vLLM T2VA"
echo "========================================"
echo "Server       : ${BASE_URL}"
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

curl -sS \
  "${BASE_URL}/health" \
  > /dev/null

echo "Server is healthy."

# 2. T2VA 生成
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

# 3. 视频检查
if command -v ffprobe >/dev/null 2>&1; then
    echo
    echo "Media info:"
    ffprobe -v error \
      -show_entries \
      stream=index,codec_name,width,height,r_frame_rate,sample_rate,channels \
      -of json \
      "${OUTPUT}"
fi
