#!/usr/bin/env bash
set -euo pipefail

# =========================
# MiniMax-H3 vLLM FL2VA (首帧图 -> 视频 + 音频)
# =========================
#
# 请求协议说明（对齐官方 curl 示例，已实测字段名）：
#   - 用 multipart 表单（-F），与官方一致，不依赖 jq。
#   - 首帧图字段名固定为 `input_reference`（带 ;type=image/png），
#     只接受本地文件，不接受 URL；故脚本先把 IMAGE_URI 下载到本地临时文件再上传。
#   - 模型特定参数放 `extra_params` JSON：task/duration(可为小数)/audio_flow_shift。
#   - 走 /v1/videos/sync 同步返回 MP4。
#   - 服务端需以 --task-type fl2va 启动。

HOST="${HOST:-54.2.2.1}"
PORT="${PORT:-8000}"
BASE_URL="http://${HOST}:${PORT}"

# 首帧图（必须是服务端能访问到的 URL）
IMAGE_URI="${IMAGE_URI:-https://cdn.hailuoai.com/prod/hailuo_demo/testsets/H3_AA_I2VA/gallery/sr_v17_variants_seed42_43_20260724/inputs/4a3a90bf9100_KDmcbkhzYo5sjjxr9FqcVmWVnzb.png}"

# FL2VA 提示词：建议用 H3-Context-IR 结构（integrated_multimodal_description / overall_soundscape / non_diegetic_music）
PROMPT="${PROMPT:-夜晚，一间安静的卧室里，主人正在熟睡。三只猫排成一列从门口走进来，第一只猫吹着金色小号，第二只猫吹着小型长号，第三只猫吹着铜管乐器，整齐滑稽地演奏。中景平稳跟随，随后三只猫同时停奏转身离开，主人始终未醒。声音含轻微脚步声、滑稽铜管声与安静夜间环境声。}"

FPS="${FPS:-24}"
STEPS="${STEPS:-50}"
FLOW_SHIFT="${FLOW_SHIFT:-12}"
AUDIO_FLOW_SHIFT="${AUDIO_FLOW_SHIFT:-3}"
DURATION="${DURATION:-5}"            # extra_params.duration（秒；小数也行，如 5.0）
SEED="${SEED:-1101}"
OUTPUT="${OUTPUT:-minimax-h3-fl2va.mp4}"

# 临时下载首帧图（multipart 的 input_reference 只接受本地文件，不接受 URL）
TMP_IMG="$(mktemp -t fl2va_frame.XXXXXX.png)"

echo "========================================"
echo "MiniMax-H3 vLLM FL2VA (first frame -> video+audio)"
echo "========================================"
echo "Server      : ${BASE_URL}"
echo "Image URI   : ${IMAGE_URI}"
echo "FPS         : ${FPS}"
echo "Steps       : ${STEPS}"
echo "Duration    : ${DURATION}s"
echo "Seed        : ${SEED}"
echo "Output      : ${OUTPUT}"
echo "========================================"

# 1. 健康检查
echo "[1/3] Checking server..."
curl -sS "${BASE_URL}/health" > /dev/null
echo "Server is healthy."

# 2. 下载首帧图到本地临时文件
echo "[2/3] Downloading first frame..."
curl -f -sS -L "${IMAGE_URI}" -o "${TMP_IMG}" || { echo "首帧图下载失败：${IMAGE_URI}"; exit 1; }

# 3. 提交 FL2VA 任务（multipart，与官方 curl 对齐：input_reference=@本地文件;type=image/png）
echo "Submitting FL2VA job (multipart)..."
http_body_file="$(mktemp -t fl2va_resp.XXXXXX)"
http_code=$(
  curl -sS -o "${http_body_file}" -w '%{http_code}' \
    -X POST "${BASE_URL}/v1/videos/sync" \
    -F "prompt=${PROMPT}" \
    -F "fps=${FPS}" \
    -F "num_inference_steps=${STEPS}" \
    -F "flow_shift=${FLOW_SHIFT}" \
    -F "seed=${SEED}" \
    -F "extra_params={\"task\":\"fl2va\",\"duration\":${DURATION},\"audio_flow_shift\":${AUDIO_FLOW_SHIFT}}" \
    -F "input_reference=@${TMP_IMG};type=image/png" \
    -o "${OUTPUT}"
)
echo "HTTP status: ${http_code}"
if [ "${http_code}" != "200" ]; then
  echo "请求失败，服务端响应："
  cat "${http_body_file}"
  rm -f "${TMP_IMG}" "${http_body_file}"
  exit 1
fi
rm -f "${http_body_file}" "${TMP_IMG}"

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
