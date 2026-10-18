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
# MiniMax-H3 sglang Ref2VA —— 交薪通员工端演示 9 段分镜批量生成（第二版 Prompt）
#   （JSON body 异步；每段参考图与时长都不同，段内 <Picture N> 顺序 == 该段参考图顺序）
# =========================
#
# 源文档：scripts/交薪通-员工端演示-15s分段prompt.md（全片 1:44 / 104s，按时序 9 段）
#
# 协议严格对齐官方调用示例（sglang 服务端，默认 :30010）：
#   POST /v1/videos (JSON body) -> 取 .id -> 轮询 GET /v1/videos/{id} -> 下载 GET /v1/videos/{id}/content
#
# 段 <-> 时长 <-> 参考图 映射（取自第二版分段总览）：
#   段1   13s   first_shot.PNG  image4.png  image5.png
#   段2   15s   image6.png  image7.png
#   段3   12s   image8.png  image9.png
#   段4   10s   image9.png
#   段5   12s   image133.png
#   段6   15s   image134.png  image135.png  image1.png  image136.png
#   段7    8s   image1.png
#   段8   13s   image2.png  image3.png
#   段9    6s   image2.png
#   （注意段7/8/9 与第一版不同：段7 只用 image1，段8 顺序是 image2,image3，段9 只用 image2）
#   （first_shot 在 md 中写作大写扩展名 .PNG，服务端按 URL 取图时大小写敏感，故此处保持原样）
#
# 用法（默认每张图片都会拼到 IMAGE_PREFIX 这个 URL 前缀下）：
#   bash scripts/ref2va-jiaoxintong2-sglang.sh
#   # 默认 IMAGE_PREFIX=http://53.192.28.254:8210/images/
#   # 换 URL：        IMAGE_PREFIX=https://my/cdn/imgs/  bash scripts/ref2va-jiaoxintong2-sglang.sh
#   # 改用本地目录：  IMAGE_PREFIX=/abs/path/to/images    bash scripts/ref2va-jiaoxintong2-sglang.sh
#   # 关闭前缀(相对当前目录解析 file://)：IMAGE_PREFIX=  bash scripts/ref2va-jiaoxintong2-sglang.sh
#
# 默认：竖屏 9:16、短边 768、段提示词 scripts/prompts/jiaoxintong2/seg{1..9}.txt，逐段用 md 里的时长。
#   只重跑部分段：直接改下面「段提示词文件」处的 for i in ... 段号（无需传环境变量）。
# 其它：DURATION(未设=按段取时长；显式设定=所有段统一用该秒数)
#   SHORT_EDGE(768) / ASPECT_RATIO(9:16) / SEED(3101) / HOST / PORT(30010)
#   FLOW_SHIFT(12.0) / AUDIO_FLOW_SHIFT(3.0) / STEPS(50) / NUM_OUTPUTS(1) / MODEL(MiniMaxAI/MiniMax-H3)
#   OUTPUT_PREFIX(jiaoxintong2_)  输出名 = 前缀 + 段提示词文件名 stem，如 seg3.txt -> jiaoxintong2_seg3.mp4
#
# 覆盖段/图/时长（高级，均须与段数一致）：
#   SEGMENT_FILES="a.txt b.txt"                    # 空格分隔的段提示词文件
#   SEGMENT_IMAGES_STR="p1.png p2.png|p3.png"      # | 分隔每段，空格分隔段内图片
#   SEGMENT_DURATIONS_STR="13|15"                  # | 分隔每段秒数

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-30010}"
BASE_URL="http://${HOST}:${PORT}"

MODEL="${MODEL:-MiniMaxAI/MiniMax-H3}"
SHORT_EDGE="${SHORT_EDGE:-768}"
ASPECT_RATIO="${ASPECT_RATIO:-9:16}"
STEPS="${STEPS:-50}"
FLOW_SHIFT="${FLOW_SHIFT:-12.0}"
AUDIO_FLOW_SHIFT="${AUDIO_FLOW_SHIFT:-3.0}"
NUM_OUTPUTS="${NUM_OUTPUTS:-1}"
SEED="${SEED:-3101}"
OUTPUT_PREFIX="${OUTPUT_PREFIX:-jiaoxintong2_}"
IMAGE_PREFIX="${IMAGE_PREFIX-http://53.192.28.254:8210/images/}"

# -------------------------
# 每段参考图与时长：按「段号」索引（段号取自提示词文件名 stem，如 seg7.txt -> 7）
#   参考图顺序即 <Picture 1..N>；只写文件名，脚本自动拼到 IMAGE_PREFIX 下。
#   按段号取值的好处：只重跑其中一段时，参考图与时长依然对得上。
# -------------------------
declare -A SEG_IMG_BY_IDX=(
  [1]="first_shot.PNG image4.png image5.png"
  [2]="image6.png image7.png"
  [3]="image8.png image9.png"
  [4]="image9.png"
  [5]="image133.png"
  [6]="image134.png image135.png image1.png image136.png"
  [7]="image1.png"
  [8]="image2.png image3.png"
  [9]="image2.png"
)
declare -A SEG_DUR_BY_IDX=( [1]=13 [2]=15 [3]=12 [4]=10 [5]=12 [6]=15 [7]=8 [8]=13 [9]=6 )
DEFAULT_DURATION="${DEFAULT_DURATION:-15}"   # 段号不在表里时的兜底时长

# 显式覆盖（用 | 逐段给定，须与段数一致）；不覆盖则按段号查上面的表
if [ -n "${SEGMENT_IMAGES_STR:-}" ]; then
  IFS='|' read -ra SEG_IMG_LIST <<< "${SEGMENT_IMAGES_STR}"; IMG_OVERRIDE=1
else
  SEG_IMG_LIST=(); IMG_OVERRIDE=0
fi
if [ -n "${SEGMENT_DURATIONS_STR:-}" ]; then
  IFS='|' read -ra SEG_DUR_LIST <<< "${SEGMENT_DURATIONS_STR}"; DUR_OVERRIDE=1
else
  SEG_DUR_LIST=(); DUR_OVERRIDE=0
fi

# -------------------------
# 段提示词文件（内置默认 seg1..9）
# -------------------------
if [ -z "${SEGMENT_FILES:-}" ]; then
  SEGMENT_DIR="${SEGMENT_DIR:-scripts/prompts/jiaoxintong2}"
  SEGMENT_FILES=()
  # 全片为 1..9；只重跑失败段时临时改这里的段号（参考图与时长会按段号自动对上，输出名也不会变）。
  for i in 1 2 3 4 5 6 7 8 9; do SEGMENT_FILES+=("${SEGMENT_DIR}/seg${i}.txt"); done
else
  # 环境里传的是空格分隔字符串（bash 数组无法经环境传递），直接切分成数组。
  # 不要对这种标量用 ${#VAR[@]} 或 ${VAR[0]}：set -u 下会报 unbound variable。
  read -ra SEGMENT_FILES <<< "${SEGMENT_FILES}"
fi

N_SEG=${#SEGMENT_FILES[@]}

if [ "$IMG_OVERRIDE" -eq 1 ] && [ "$N_SEG" -ne "${#SEG_IMG_LIST[@]}" ]; then
  echo "错误：段数(${N_SEG}) 与 SEGMENT_IMAGES_STR 的分组数(${#SEG_IMG_LIST[@]}) 不一致（用 | 分隔每段）。"
  exit 1
fi
if [ "$DUR_OVERRIDE" -eq 1 ] && [ "$N_SEG" -ne "${#SEG_DUR_LIST[@]}" ]; then
  echo "错误：段数(${N_SEG}) 与 SEGMENT_DURATIONS_STR 的个数(${#SEG_DUR_LIST[@]}) 不一致（用 | 分隔每段）。"
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

# 输出名由段提示词文件名推导（不用循环序号）：stem(seg3.txt)=seg3 -> ${OUTPUT_PREFIX}seg3.mp4
# 这样单独重跑某一阶段（SEGMENT_FILES=.../seg3.txt）时，输出名不会变成 seg1 而错位/覆盖。
seg_out() {  # $1=prompt_file
  local stem; stem="$(basename "$1")"; stem="${stem%.*}"
  printf '%s%s.mp4' "${OUTPUT_PREFIX}" "${stem}"
}

# $1=prompt_file  $2=conditions_json  $3=duration  -> stdout = body.json
build_body() {
  local dur="$3" secs
  secs="${dur%%.*}"
  jq -Rs --argjson cond "$2" \
    --arg model "$MODEL" \
    --argjson seconds "$secs" \
    --argjson short_edge "$SHORT_EDGE" \
    --arg aspect_ratio "$ASPECT_RATIO" \
    --argjson duration "$dur" \
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

# 从段提示词文件名推段号：seg7.txt -> 7；取不到数字时回退为位置序号
seg_idx() {  # $1=prompt_file  $2=0-based position
  local stem num
  stem="$(basename "$1")"; stem="${stem%.*}"
  num="$(printf '%s' "$stem" | grep -oE '[0-9]+' | tail -1 || true)"
  if [ -n "$num" ]; then printf '%s' "$((10#$num))"; else printf '%s' "$(( $2 + 1 ))"; fi
}

# 取某段参考图（显式覆盖走位置序号，否则走段号查表）
seg_imgs() {  # $1=prompt_file  $2=0-based position
  if [ "$IMG_OVERRIDE" -eq 1 ]; then printf '%s' "${SEG_IMG_LIST[$2]}"; return; fi
  printf '%s' "${SEG_IMG_BY_IDX[$(seg_idx "$1" "$2")]:-}"
}

# 取某段时长：DURATION 全局 > SEGMENT_DURATIONS_STR 逐段 > 段号查表 > DEFAULT_DURATION
seg_dur() {  # $1=prompt_file  $2=0-based position
  local v
  if [ -n "${DURATION:-}" ]; then printf '%s' "${DURATION}"; return; fi
  if [ "$DUR_OVERRIDE" -eq 1 ]; then printf '%s' "${SEG_DUR_LIST[$2]}"; return; fi
  v="${SEG_DUR_BY_IDX[$(seg_idx "$1" "$2")]:-}"
  printf '%s' "${v:-$DEFAULT_DURATION}"
}

echo "========================================"
echo "MiniMax-H3 sglang Ref2VA —— 交薪通 9 段分镜（第二版：每段独立参考图 + 独立时长）"
echo "========================================"

# 先算逐段时长合计，供 banner 展示
TOTAL_DUR=0
for ((s=0; s<N_SEG; s++)); do
  _d="$(seg_dur "${SEGMENT_FILES[s]}" "$s")"; TOTAL_DUR=$((TOTAL_DUR + ${_d%%.*}))
done

echo "Server     : ${BASE_URL}"
echo "Model      : ${MODEL}"
echo "ImagePrefix: ${IMAGE_PREFIX:-<空/相对当前目录>}"
if [ -n "${DURATION:-}" ]; then
  echo "Duration   : ${DURATION}s/段（已由 DURATION 全局覆盖，合计 ${TOTAL_DUR}s）"
else
  echo "Duration   : 逐段取值（合计 ${TOTAL_DUR}s / ${N_SEG} 段）"
fi
echo "Aspect     : ${ASPECT_RATIO}  ShortEdge: ${SHORT_EDGE}"
echo "Steps/Flow : ${STEPS}/${FLOW_SHIFT}/${AUDIO_FLOW_SHIFT}  Seed: ${SEED}  Out: ${OUTPUT_PREFIX}<段名>.mp4"
echo "Log file   : ${LOG_FILE}"
echo "段数       : ${N_SEG}"
echo "----------------------------------------"
for ((s=0; s<N_SEG; s++)); do
  _imgs_i="$(seg_imgs "${SEGMENT_FILES[s]}" "$s")"
  read -ra _chk <<< "${_imgs_i}"
  printf '  段%-2s %3ss  %-28s <- %s  参考图 %s 张\n' \
    "$(seg_idx "${SEGMENT_FILES[s]}" "$s")" "$(seg_dur "${SEGMENT_FILES[s]}" "$s")" \
    "$(seg_out "${SEGMENT_FILES[s]}")" "${SEGMENT_FILES[s]}" "${#_chk[@]}"
done
echo "========================================"

# 先做一次全量参考图校验（缺图/查不到段号对应图则立即中止，避免跑到中途才失败）
for ((s=0; s<N_SEG; s++)); do
  _imgs_i="$(seg_imgs "${SEGMENT_FILES[s]}" "$s")"
  if [ -z "${_imgs_i// /}" ]; then
    echo "错误：${SEGMENT_FILES[s]} 未解析到参考图（段号 $(seg_idx "${SEGMENT_FILES[s]}" "$s") 不在内置表里）。"
    echo "      请用 SEGMENT_IMAGES_STR=\"图1 图2|图3\" 显式指定每段参考图。"
    exit 1
  fi
  read -ra _imgs <<< "${_imgs_i}"
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

# 单段生成（韧性版）。$1=prompt_file $2=conditions_json $3=output $4=duration
gen_one() {
  local pf="$1" cond_json="$2" out="$3" dur="$4"
  local vid="" st="" elapsed=0 http_code="" resubmits=0

  while true; do
    if ! wait_for_server; then
      echo "    [fatal] 等待服务端超时，放弃段：${pf}"
      return 1
    fi

    if [ -z "$vid" ]; then
      build_body "$pf" "$cond_json" "$dur" > "$TMPD/body.json"
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
OUT_FILES=()
for ((s=0; s<N_SEG; s++)); do
  out="$(seg_out "${SEGMENT_FILES[s]}")"
  dur="$(seg_dur "${SEGMENT_FILES[s]}" "$s")"
  imgs_i="$(seg_imgs "${SEGMENT_FILES[s]}" "$s")"
  read -ra _imgs <<< "${imgs_i}"
  cond_json="$(build_conditions "${_imgs[@]}")"
  echo "[$((s+1))/${N_SEG}] ${out} (${dur}s) <- ${SEGMENT_FILES[s]}   (参考图 ${#_imgs[@]} 张: ${imgs_i:-<空>}  开始 $(date '+%F %T'))"
  if gen_one "${SEGMENT_FILES[s]}" "${cond_json}" "${out}" "${dur}"; then
    ls -lh "${out}" 2>/dev/null || true
    echo "    完成时刻: $(date '+%F %T')"
    OUT_FILES+=("${out}")
  else
    echo "  !!! ${out} 最终失败（$(date '+%F %T')），继续下一段..."
    FAILED+=("${out}")
  fi
done

echo
echo "========================================"
if [ "${#FAILED[@]}" -eq 0 ]; then
  echo "All ${N_SEG} segments completed:"
  for o in "${OUT_FILES[@]}"; do echo "  ${o}"; done
  echo "如需拼接为整片（顺序拼接，全部同规格 9:16/768 短边）："
  echo "  ffmpeg -y -f concat -safe 0 -i <(printf \"file '%s'\\n\" ${OUT_FILES[*]}) -c copy ${OUTPUT_PREFIX}full.mp4"
else
  echo "完成，但以下段失败：${FAILED[*]}"
  echo "  可单独重跑对应段（输出名跟段提示词文件名走，不会错位）：SEGMENT_FILES=<该段.txt> bash $0"
fi
echo "========================================"
echo "[log] end      : $(date '+%F %T')"
