#!/usr/bin/env bash
set -euo pipefail

# =========================
# MiniMax-H3 vLLM Ref2VA —— 4 段分镜 + 3 张参考图（按 subject 映射）批量生成
# =========================
#
# 读取 4 段分镜提示词 + 3 张参考图（dxb/hxr/logo，分别对应 <Subject 1/2/3>），
# 逐段调用 /v1/videos/sync 生成视频。每段一张 MP4：story_seg1.mp4 ... story_seg4.mp4。
#
# 重要：本提示词里 3 张参考图是按「角色 subject」锚定的，不是按段落锚定的——
# 每一段都同时引用 <Subject 1>(dxb) / <Subject 2>(hxr) / <Subject 3>(logo) 三个主体。
# 因此本脚本对【每一段】都发送【全部 3 张】参考图（multipart 重复字段 input_reference）。
#
# ⚠️ 兼容性提示：你给的 curl 示例只用了一张 input_reference。H3 Ref2VA 是否支持
# 「单次请求多张参考图」取决于服务端实现。若服务端只接受一张，请把 REF_IMAGES
# 设为单张图（如 REF_IMAGES="dxb.png"），或联系维护者确认多参考图字段约定。
# 多张时本脚本按如下顺序重复发送：
#   -F "input_reference=@dxb.png;type=image/png"
#   -F "input_reference=@hxr.png;type=image/png"
#   -F "input_reference=@logo.png;type=image/png"
#
# 用法（推荐显式传参）：
#   SEGMENT_FILES="seg1.txt seg2.txt seg3.txt seg4.txt" \
#   REF_IMAGES="dxb.png hxr.png logo.png" \
#   bash scripts/ref2va-story.sh
#
# 不传参时默认读取：
#   段提示词 : scripts/prompts/story/seg{1..4}.txt
#   参考图   : dxb.png / hxr.png / logo.png（当前目录；请放到可访问路径）
#
# 其它可调环境变量：DURATION(每段秒,默认15) / ASPECT_RATIO(默认adaptive) /
#   SHORT_EDGE(768) / FPS(24) / STEPS(50) / FLOW_SHIFT(12) /
#   AUDIO_FLOW_SHIFT(3) / SEED(3100) / HOST / PORT。
#
# 注：服务端需以 --task-type ref2va 启动。

HOST="${HOST:-localhost}"
PORT="${PORT:-8000}"
BASE_URL="http://${HOST}:${PORT}"

DURATION="${DURATION:-15}"            # 每段 15s（与「4段15s」对应）
ASPECT_RATIO="${ASPECT_RATIO:-adaptive}"
SHORT_EDGE="${SHORT_EDGE:-768}"
FPS="${FPS:-24}"
STEPS="${STEPS:-50}"
FLOW_SHIFT="${FLOW_SHIFT:-12}"
AUDIO_FLOW_SHIFT="${AUDIO_FLOW_SHIFT:-3}"
SEED="${SEED:-3100}"

# ---------- 段提示词文件 ----------
if [ -z "${SEGMENT_FILES:-}" ]; then
  SEGMENT_DIR="${SEGMENT_DIR:-scripts/prompts/story}"
  SEGMENT_FILES=()
  for i in 1 2 3 4; do
    SEGMENT_FILES+=("${SEGMENT_DIR}/seg${i}.txt")
  done
fi
# 支持空格分隔字符串或已展开的数组
if [ "${#SEGMENT_FILES[@]}" -eq 1 ]; then
  read -ra SEGMENT_FILES <<< "${SEGMENT_FILES[0]}"
fi

# ---------- 参考图（按 subject：默认 3 张） ----------
if [ -z "${REF_IMAGES:-}" ]; then
  REF_IMAGES=("dxb.png" "hxr.png" "logo.png")
fi
if [ "${#REF_IMAGES[@]}" -eq 1 ]; then
  read -ra REF_IMAGES <<< "${REF_IMAGES[0]}"
fi

N_SEG=${#SEGMENT_FILES[@]}
N_REF=${#REF_IMAGES[@]}

# 校验文件存在
for f in "${SEGMENT_FILES[@]}"; do
  [ -f "$f" ] || { echo "错误：段提示词文件不存在：$f"; exit 1; }
  [ -s "$f" ] || { echo "警告：段提示词文件为空：$f"; }
done
for ((r=0; r<N_REF; r++)); do
  [ -f "${REF_IMAGES[r]}" ] || { echo "错误：参考图不存在：${REF_IMAGES[r]}"; exit 1; }
done

echo "========================================"
echo "MiniMax-H3 vLLM Ref2VA —— 分镜批量生成"
echo "========================================"
echo "Server     : ${BASE_URL}"
echo "段数 / 图数: ${N_SEG} / ${N_REF}"
echo "Duration   : ${DURATION}s/段"
echo "Aspect     : ${ASPECT_RATIO}  ShortEdge: ${SHORT_EDGE}"
echo "----------------------------------------"
for ((s=0; s<N_SEG; s++)); do
  echo "  段$((s+1)) <- ${SEGMENT_FILES[s]}  (引用 ${N_REF} 张参考图: ${REF_IMAGES[*]})"
done
echo "========================================"

# ---------- 健康检查 ----------
echo "[0/$((N_SEG+1))] Checking server..."
curl -sS "${BASE_URL}/health" > /dev/null
echo "Server is healthy."

# ---------- 逐段生成 ----------
gen_one() {  # $1=prompt_file $2=output
  local pf="$1" out="$2"
  local prompt
  prompt="$(cat "$pf")"
  cmd=(curl -f -sS -X POST "${BASE_URL}/v1/videos/sync"
    -F "prompt=${prompt}"
    -F "aspect_ratio=${ASPECT_RATIO}"
    -F "short_edge=${SHORT_EDGE}"
    -F "fps=${FPS}"
    -F "num_inference_steps=${STEPS}"
    -F "flow_shift=${FLOW_SHIFT}"
    -F "seed=${SEED}"
    -F "extra_params={\"task\":\"ref2va\",\"duration\":${DURATION},\"audio_flow_shift\":${AUDIO_FLOW_SHIFT}}")
  # 每张参考图一个重复的 input_reference 字段
  for ((r=0; r<N_REF; r++)); do
    local ri="${REF_IMAGES[r]}" img_ext img_type
    img_ext="${ri##*.}"
    case "${img_ext,,}" in
      png)        img_type="image/png" ;;
      jpg|jpeg)   img_type="image/jpeg" ;;
      webp)       img_type="image/webp" ;;
      bmp)        img_type="image/bmp" ;;
      gif)        img_type="image/gif" ;;
      *)          img_type="application/octet-stream" ;;
    esac
    cmd+=(-F "input_reference=@${ri};type=${img_type}")
  done
  cmd+=(-o "${out}")
  "${cmd[@]}"
}

for ((s=0; s<N_SEG; s++)); do
  out="story_seg$((s+1)).mp4"
  echo "[$((s+1))/$((N_SEG+1))] 段$((s+1)) (${N_REF}张参考图) -> ${out}"
  gen_one "${SEGMENT_FILES[s]}" "${out}"
  ls -lh "${out}"
done

echo
echo "========================================"
echo "All segments completed"
echo "========================================"
