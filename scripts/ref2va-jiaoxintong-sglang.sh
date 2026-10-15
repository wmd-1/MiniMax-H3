#!/usr/bin/env bash
set -euo pipefail

# =========================
# 日志：stdout/stderr 同步写入日志文件（可用 LOG_DIR / LOG_FILE 覆盖）
# =========================
LOG_DIR="${LOG_DIR:-logs}"
LOG_NAME="${LOG_NAME:-$(basename "$0" .sh)}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/${LOG_NAME}-$(date +%Y%m%d-%H%M%S).log}"
mkdir -p "$(dirname "${LOG_FILE}")"
exec > >(tee -a "${LOG_FILE}") 2> >(tee -a "${LOG_FILE}" >&2)
echo "[log] LOG_FILE : ${LOG_FILE}"
echo "[log] start    : $(date '+%F %T')"

command -v jq >/dev/null 2>&1 || {
  echo "需要 jq。请先安装： apt-get install -y jq  或  brew install jq"; exit 1
}

# =========================
# MiniMax-H3 sglang Ref2VA —— 交薪通员工端「快速上手与扫码入职」8 段分镜批量生成
#   （JSON body 异步；每段参考图不一致，段内 <Picture N> 顺序 == 该段参考图顺序）
# =========================
#
# 协议严格对齐官方调用示例（sglang 服务端，默认 :30010）：
#   POST /v1/videos (JSON body) -> 取 .id -> 轮询 GET /v1/videos/{id} -> 下载 GET /v1/videos/{id}/content
#
# 与 ref2va-story-sglang.sh 的关键区别：
#   story 版把同一批参考图发给每一段；本脚本**每段用各自独立的参考图**，
#   段内 conditions[] 的顺序严格对应 prompt 里的 <Picture 1>/<Picture 2>/… 。
#   参考图用 file://<绝对路径>（服务端读自己文件系统）；本地文件自动转换，http(s) 原样。
#
# 段 <-> 参考图 映射（取自分段 Prompt.md 的分段总览）：
#   段1  first_shot.png  image4.png  image5.png
#   段2  image6.png  image7.png
#   段3  image8.png  image9.png
#   段4  image9.png
#   段5  image133.png
#   段6  image134.png  image135.png  image1.png  image136.png
#   段7  image1.png  image2.png
#   段8  image3.png  image2.png
#
# 用法（默认每张图片都会拼到 IMAGE_PREFIX 这个 URL 前缀下）：
#   bash scripts/ref2va-jiaoxintong-sglang.sh
#   # 默认 IMAGE_PREFIX=http://53.192.28.254:8210/images/
#   # 换 URL：        IMAGE_PREFIX=https://my/cdn/imgs/  bash scripts/ref2va-jiaoxintong-sglang.sh
#   # 改用本地目录：  IMAGE_PREFIX=/abs/path/to/images    bash scripts/ref2va-jiaoxintong-sglang.sh
#   # 关闭前缀(相对当前目录解析 file://)：IMAGE_PREFIX=  bash scripts/ref2va-jiaoxintong-sglang.sh
#
# 默认：竖屏 9:16、每段 15s、段提示词 scripts/prompts/jiaoxintong/seg{1..8}.txt。
# 其它：DURATION(15) / SHORT_EDGE(768) / ASPECT_RATIO(9:16) / SEED(3101) / HOST / PORT(30010)
#   FLOW_SHIFT(12.0) / AUDIO_FLOW_SHIFT(3.0) / STEPS(50) / NUM_OUTPUTS(1) / MODEL(MiniMaxAI/MiniMax-H3)
#   OUTPUT_PREFIX(jiaoxintong_seg)  输出为 ${OUTPUT_PREFIX}{i}.mp4
#
# 覆盖段/图（高级）：
#   SEGMENT_FILES="a.txt b.txt"                    # 空格分隔的段提示词文件
#   SEGMENT_IMAGES_STR="p1.png p2.png|p3.png"      # 用 | 分隔每段、空格分隔段内图片（须与段数一致）

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-30010}"
BASE_URL="http://${HOST}:${PORT}"

MODEL="${MODEL:-MiniMaxAI/MiniMax-H3}"
DURATION="${DURATION:-15}"
SECONDS_INT="${DURATION%%.*}"
SHORT_EDGE="${SHORT_EDGE:-768}"
ASPECT_RATIO="${ASPECT_RATIO:-9:16}"
STEPS="${STEPS:-50}"
FLOW_SHIFT="${FLOW_SHIFT:-12.0}"
AUDIO_FLOW_SHIFT="${AUDIO_FLOW_SHIFT:-3.0}"
NUM_OUTPUTS="${NUM_OUTPUTS:-1}"
SEED="${SEED:-3101}"
OUTPUT_PREFIX="${OUTPUT_PREFIX:-jiaoxintong_seg}"
IMAGE_PREFIX="${IMAGE_PREFIX-http://53.192.28.254:8210/images/}"

# -------------------------
# 每段参考图（内置默认；顺序即 <Picture 1..N>；只写文件名，脚本自动拼到 IMAGE_PREFIX 下）
# -------------------------
SEG_IMG_1="first_shot.png image4.png image5.png"
SEG_IMG_2="image6.png image7.png"
SEG_IMG_3="image8.png image9.png"
SEG_IMG_4="image9.png"
SEG_IMG_5="image133.png"
SEG_IMG_6="image134.png image135.png image1.png image136.png"
SEG_IMG_7="image1.png image2.png"
SEG_IMG_8="image3.png image2.png"

if [ -z "${SEGMENT_IMAGES_STR:-}" ]; then
  SEG_IMG_LIST=( "$SEG_IMG_1" "$SEG_IMG_2" "$SEG_IMG_3" "$SEG_IMG_4" "$SEG_IMG_5" "$SEG_IMG_6" "$SEG_IMG_7" "$SEG_IMG_8" )
else
  # 用 | 分隔每段
  IFS='|' read -ra SEG_IMG_LIST <<< "${SEGMENT_IMAGES_STR}"
fi

# -------------------------
# 段提示词文件（内置默认 seg1..8）
# -------------------------
if [ -z "${SEGMENT_FILES:-}" ]; then
  SEGMENT_DIR="${SEGMENT_DIR:-scripts/prompts/jiaoxintong}"
  SEGMENT_FILES=()
  for i in 1 2 3 4 5 6 7 8; do SEGMENT_FILES+=("${SEGMENT_DIR}/seg${i}.txt"); done
fi
[ "${#SEGMENT_FILES[@]}" -eq 1 ] && read -ra SEGMENT_FILES <<< "${SEGMENT_FILES[0]}"

N_SEG=${#SEGMENT_FILES[@]}
N_IMG=${#SEG_IMG_LIST[@]}

if [ "$N_SEG" -ne "$N_IMG" ]; then
  echo "错误：段数(${N_SEG}) 与 参考图分组数(${N_IMG}) 不一致。"
  echo "      请检查 SEGMENT_FILES 与 SEGMENT_IMAGES_STR（用 | 分隔每段）是否对应。"
  exit 1
fi

for f in "${SEGMENT_FILES[@]}"; do
  [ -f "$f" ] || { echo "错误：段提示词文件不存在：$f"; exit 1; }
done

TMPD="$(mktemp -d)"
cleanup() { rm -rf "$TMPD"; }
trap cleanup EXIT

# 相对文件名（非 URL/绝对/file://）拼上 IMAGE_PREFIX；已含 http/file/绝对路径的项原样保留。
# IMAGE_PREFIX 置空则不拼前缀，交由 to_uri 按当前目录解析为 file://。
prefix_dir() {
  local u="$1"
  if [ -n "${IMAGE_PREFIX}" ] && [[ "$u" != http* ]] && [[ "$u" != file://* ]] && [[ "$u" != /* ]]; then
    printf '%s%s' "${IMAGE_PREFIX%/}/" "$u"
  else
    printf '%s' "$u"
  fi
}

# 本地文件 -> file://<绝对路径>；URL / file:// 原样
to_uri() {
  local u="$1"
  if [[ "$u" == http* || "$u" == file://* ]]; then
    printf '%s' "$u"
  else
    printf 'file://%s' "$(realpath -m "$u")"
  fi
}

# 校验某段参考图是否存在（URL/file:// 跳过本地校验）；$@ = 该段原始图片项
validate_images() {
  local u resolved
  for u in "$@"; do
    resolved="$(prefix_dir "$u")"
    [ -f "$resolved" ] || [[ "$resolved" == http* ]] || [[ "$resolved" == file://* ]] \
      || { echo "错误：参考图不存在（也不是 URL）：${resolved}"; exit 1; }
  done
}

# 为某段构建 conditions JSON 数组（顺序即 <Picture N>）；$@ = 该段图片项；stdout = json
build_conditions() {
  local json='[]' u uri
  for u in "$@"; do
    uri="$(to_uri "$(prefix_dir "$u")")"
    json=$(printf '%s' "$json" | jq --arg uri "$uri" '. + [{type:"image", uri:$uri, role:"reference"}]')
  done
  printf '%s' "$json"
}

build_body() {  # $1=prompt_file  $2=conditions_json  -> stdout = body.json
  jq -Rs --argjson cond "$2" \
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
      conditions: $cond,
      target: {short_edge: $short_edge, aspect_ratio: $aspect_ratio, duration_seconds: $duration},
      num_outputs_per_prompt: $num_outputs,
      num_inference_steps: $steps,
      flow_shift: $flow_shift,
      audio_flow_shift: $audio_flow_shift,
      seed: $seed
    }' \
    "$1"
}

echo "========================================"
echo "MiniMax-H3 sglang Ref2VA —— 交薪通 8 段分镜（每段独立参考图）"
echo "========================================"
echo "Server     : ${BASE_URL}"
echo "Model      : ${MODEL}"
echo "ImagePrefix: ${IMAGE_PREFIX:-<空/相对当前目录>}"
echo "Duration   : ${DURATION}s/段 (seconds=${SECONDS_INT})"
echo "Aspect     : ${ASPECT_RATIO}  ShortEdge: ${SHORT_EDGE}"
echo "Steps/Flow : ${STEPS}/${FLOW_SHIFT}/${AUDIO_FLOW_SHIFT}  Seed: ${SEED}  Out: ${OUTPUT_PREFIX}{i}.mp4"
echo "Log file   : ${LOG_FILE}"
echo "段数       : ${N_SEG}"
echo "----------------------------------------"
for ((s=0; s<N_SEG; s++)); do
  echo "  段$((s+1)) <- ${SEGMENT_FILES[s]}   参考图: ${SEG_IMG_LIST[s]:-<空>}"
done
echo "========================================"

# 先做一次全量参考图存在性校验，避免跑到中途才失败
for ((s=0; s<N_SEG; s++)); do
  read -ra _imgs <<< "${SEG_IMG_LIST[s]:-}"
  validate_images "${_imgs[@]}"
done

# =========================
# 韧性配置（可被环境变量覆盖）
#   服务端 sglang 最终会把视频生成到磁盘，但 scheduler/client 有约 100 分钟超时，
#   到时把任务标成 failed。策略：
#     - 状态报 failed/超时但服务端仍在线 → 不重提（重提会重复生成同一个视频），
#       而是继续等并检查视频是否已落盘（url/content），拿到即成功。
#     - 仅当服务端真的挂了（job 丢失，curl 拿不到状态）→ 才重提该段。
# =========================
MAX_RETRIES="${MAX_RETRIES:-5}"
POLL_INTERVAL="${POLL_INTERVAL:-5}"
POLL_TIMEOUT="${POLL_TIMEOUT:-14400}"
SERVER_WAIT_RETRIES="${SERVER_WAIT_RETRIES:-90}"
SERVER_WAIT_INTERVAL="${SERVER_WAIT_INTERVAL:-10}"
DOWNLOAD_TIMEOUT="${DOWNLOAD_TIMEOUT:-10800}"

echo "韧性配置   : 单段轮询上限 ${POLL_TIMEOUT}s / 下载上限 ${DOWNLOAD_TIMEOUT}s / 重提上限 ${MAX_RETRIES} 次"

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

echo "[0/${N_SEG}] 等待服务端就绪（最长约 $((SERVER_WAIT_RETRIES*SERVER_WAIT_INTERVAL/60))min）..."
if ! wait_for_server; then
  echo "  [warn] 启动检查：服务端在等待期内未就绪，仍会逐段重试。"
fi

download_video() {  # $1=vid $2=out
  local vid="$1" out="$2" url
  url=$(jq -r '.url // empty' "$TMPD/job_${vid}.json" 2>/dev/null || true)
  if [ -n "$url" ]; then
    echo "    下载 url: ${url}"
    if curl -sS -L --max-time "${DOWNLOAD_TIMEOUT}" "$url" -o "${out}" 2>/dev/null; then
      [ -s "${out}" ] && return 0
    fi
  fi
  echo "    下载 content 端点..."
  if curl -sS -X GET --max-time "${DOWNLOAD_TIMEOUT}" "${BASE_URL}/v1/videos/${vid}/content" -o "${out}" 2>/dev/null; then
    [ -s "${out}" ] && return 0
  fi
  return 1
}

# 单段生成（韧性版）。$1=prompt_file $2=conditions_json $3=output
gen_one() {
  local pf="$1" cond_json="$2" out="$3"
  local vid="" st="" elapsed=0 http_code="" resubmits=0

  while true; do
    if ! wait_for_server; then
      echo "    [fatal] 等待服务端超时，放弃段：${pf}"
      return 1
    fi

    if [ -z "$vid" ]; then
      build_body "$pf" "$cond_json" > "$TMPD/body.json"
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

    if ! curl -sS --max-time 30 "${BASE_URL}/v1/videos/${vid}" -o "$TMPD/job_${vid}.json" 2>/dev/null; then
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
        if download_video "$vid" "$out"; then
          echo "    ✓ 兜底拿到视频（尽管 status=${st}）：${out}"
          return 0
        fi
        echo "    [warn] status=${st} 但暂无可下载视频；服务端仍在，继续等待（不重提）..."
        sleep "$POLL_INTERVAL"; elapsed=$((elapsed + POLL_INTERVAL))
        if [ "$elapsed" -ge "$POLL_TIMEOUT" ]; then
          echo "    [fail] 等待 ${POLL_TIMEOUT}s 后仍为 ${st} 且无视频，放弃本段。"
          return 1
        fi
        ;;
      *)
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
  out="${OUTPUT_PREFIX}$((s+1)).mp4"
  read -ra _imgs <<< "${SEG_IMG_LIST[s]:-}"
  cond_json="$(build_conditions "${_imgs[@]}")"
  echo "[$((s+1))/${N_SEG}] 段$((s+1)) -> ${out}   (参考图 ${#_imgs[@]} 张: ${SEG_IMG_LIST[s]:-<空>}  开始 $(date '+%F %T'))"
  if gen_one "${SEGMENT_FILES[s]}" "${cond_json}" "${out}"; then
    ls -lh "${out}" 2>/dev/null || true
    echo "    完成时刻: $(date '+%F %T')"
  else
    echo "  !!! 段$((s+1)) 最终失败（$(date '+%F %T')），继续下一段..."
    FAILED+=("$((s+1))")
  fi
done

echo
echo "========================================"
if [ "${#FAILED[@]}" -eq 0 ]; then
  echo "All ${N_SEG} segments completed -> ${OUTPUT_PREFIX}1.mp4 ... ${OUTPUT_PREFIX}${N_SEG}.mp4"
  echo "如需拼接为整片（顺序拼接，全部同规格 9:16/768 短边）："
  echo "  ffmpeg -y -f concat -safe 0 -i <(for i in \$(seq 1 ${N_SEG}); do echo \"file '${OUTPUT_PREFIX}\$i.mp4'\"; done) -c copy ${OUTPUT_PREFIX}full.mp4"
else
  echo "完成，但以下段失败：${FAILED[*]}（可单独用 SEGMENT_FILES / SEGMENT_IMAGES_STR 重跑对应段）"
fi
echo "========================================"
echo "[log] end      : $(date '+%F %T')"
