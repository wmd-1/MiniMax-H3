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
# MiniMax-H3 sglang Ref2VA ——《银行卡限额与管控的那些事儿》【C：段9–12 → :30012】
#   四脚本并行：A 段1–4 / B 段5–8 / C 段9–12 / D 段13–15，各打一个服务实例
# =========================
#
# 源文档：scripts/银行卡限额与管控_15段分镜_H3提示词.md
#   15 段共 188s（3'08"），段长 11–14s 逐段不同（15 秒只是上限，不要统一按 15s 出片，
#   否则总时长会回到 225s）；台词 645 字一字未动。
#   本脚本跑 段9–12（48s）；A 段1–4（50s）；B 段5–8（51s）；D 段13–15（39s）。
#   四者输出同为 yinhang_segN.mp4，互不覆盖，跑完按 seg1..seg15 顺序拼接。
#
# ⚠ 四个脚本的 SEG_IMG_BY_IDX / SEG_DUR_BY_IDX 是同一份剧本的完整 15 段映射，
#   **改一个必须同步另三个**（冒烟测试里有逐字比对断言，改漏会立刻失败）。
#
# ⚠⚠ 图片目录必须与风控那版隔开：本片 `xl.png` = **小刘**，而风控剧本里 `xl.png` = **小李**，
#   同名不同人，共用一个目录会互相覆盖、直接串角色。故默认前缀已写死为独立子目录 yhk/：
#     IMAGE_PREFIX 默认 = http://53.192.28.254:8210/images/yhk/
#   本片 4 张角色图请放到该目录下：lay.png（李阿姨）xl.png（小刘）wdg.png（王大哥）zns.png（张女士）
#   要换路径仍可用环境变量覆盖：IMAGE_PREFIX=http://其他/目录/  或  IMAGE_PREFIX=/abs/目录/
#
# ── 编号规则：剧本已是「每段从 1 起编」，抽取时未做任何改写 ──────────────
#   每段第 1 张上传图 = <Picture 1> = <Subject 1>，该人说话即 (S1)；三套编号段内对齐。
#   同一角色在不同段编号可不同（小刘在段8是 <Subject 2>、段9是 <Subject 1>），属正常。
#   段号 ↔ 时长 ↔ 上传顺序（已逐段与 subject_definitions 及段首「上传」行三方核对一致）：
#     段1  11s  lay  xl          段2  14s  xl  lay          段3  14s  xl  lay
#     段4  11s  xl  lay          段5  13s  wdg  xl          段6  13s  xl  wdg
#     段7  13s  xl  wdg          段8  12s  zns  xl          段9  12s  xl  zns
#     段10 11s  xl  zns          段11 13s  zns  xl          段12 12s  xl  zns
#     段13 14s  xl  zns          段14 14s  xl（单图）        段15 11s  lay  wdg  zns  xl
#   每段只传该段出场角色，不凑满张数（段14 传 1 张、段15 传 4 张、其余各 2 张）。
#
# ⚠ 画幅：源文档未写明比例，本脚本默认 16:9；若要改竖屏，A/B/C/D 四个必须一起改，
#   否则 15 段无法 concat。
#
# ⚠ 场景锚点全片固定（明亮营业厅、浅灰石材长柜台+低玻璃隔断、员工侧显示器与读卡器、
#   后墙叫号屏、入口冷白落地窗+顶灯暖光）；字幕/屏幕文字按剧本中文原文，勿翻译。
#
# 参考图硬性约束（迁移服务器实测）：宽高比必须落在 1:4 ~ 4:1，否则服务端直接 400。
#
# 协议（sglang 服务端）：
#   POST /v1/videos (JSON body) -> 取 .id -> 轮询 GET /v1/videos/{id} -> 下载 GET /v1/videos/{id}/content
#
# 用法：
#   bash scripts/ref2va-yinhang-a-sglang.sh &   # 段1–4   → :30010
#   bash scripts/ref2va-yinhang-b-sglang.sh &   # 段5–8   → :30011
#   bash scripts/ref2va-yinhang-c-sglang.sh &   # 段9–12  → :30012
#   bash scripts/ref2va-yinhang-d-sglang.sh &   # 段13–15 → :30013
#   # 换服务地址/端口：HOST=127.0.0.1 PORT=30021 bash scripts/ref2va-ref2va-yinhang-c-sglang.sh
#   # 只重跑其中几段：直接改下面「段提示词文件」处的 for i in ... 段号
#
# 其它：DURATION(未设=按段取时长；显式设定=所有段统一)
#   SHORT_EDGE(768) / ASPECT_RATIO(16:9) / SEED(3101) / HOST(127.0.0.1) / PORT(30012)
#   FLOW_SHIFT(12.0) / AUDIO_FLOW_SHIFT(3.0) / STEPS(50) / NUM_OUTPUTS(1) / MODEL(MiniMaxAI/MiniMax-H3)
#   OUTPUT_PREFIX(yinhang_)  输出名 = 前缀 + 段提示词文件名 stem，如 seg3.txt -> yinhang_seg3.mp4
#
# 覆盖段/图/时长（高级，覆盖模式下按「位置」对应而非段号，须与段数一致）：
#   SEGMENT_FILES="a.txt b.txt"  SEGMENT_IMAGES_STR="lay.png xl.png|xl.png lay.png"  SEGMENT_DURATIONS_STR="11|14"

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-30012}"
BASE_URL="http://${HOST}:${PORT}"

MODEL="${MODEL:-MiniMaxAI/MiniMax-H3}"
SHORT_EDGE="${SHORT_EDGE:-768}"
ASPECT_RATIO="${ASPECT_RATIO:-16:9}"
STEPS="${STEPS:-50}"
FLOW_SHIFT="${FLOW_SHIFT:-12.0}"
AUDIO_FLOW_SHIFT="${AUDIO_FLOW_SHIFT:-3.0}"
NUM_OUTPUTS="${NUM_OUTPUTS:-1}"
SEED="${SEED:-3101}"
OUTPUT_PREFIX="${OUTPUT_PREFIX:-yinhang_}"
IMAGE_PREFIX="${IMAGE_PREFIX-http://53.192.28.254:8210/images/yhk/}"

# -------------------------
# 全部 15 段的角色图与时长：按「段号」索引（段号取自提示词文件名 stem）
#   图顺序即该段 <Subject 1..k> / <Picture 1..k>；只写文件名，脚本自动拼到 IMAGE_PREFIX 下。
#   ⚠ 必须与 ref2va-yinhang-b/c/d-sglang.sh 中的同名表保持一致。
# -------------------------
declare -A SEG_IMG_BY_IDX=(
  [1]="lay.png xl.png"
  [2]="xl.png lay.png"
  [3]="xl.png lay.png"
  [4]="xl.png lay.png"
  [5]="wdg.png xl.png"
  [6]="xl.png wdg.png"
  [7]="xl.png wdg.png"
  [8]="zns.png xl.png"
  [9]="xl.png zns.png"
  [10]="xl.png zns.png"
  [11]="zns.png xl.png"
  [12]="xl.png zns.png"
  [13]="xl.png zns.png"
  [14]="xl.png"
  [15]="lay.png wdg.png zns.png xl.png"
)
declare -A SEG_DUR_BY_IDX=(
  [1]=11 [2]=14 [3]=14 [4]=11 [5]=13 [6]=13 [7]=13 [8]=12
  [9]=12 [10]=11 [11]=13 [12]=12 [13]=14 [14]=14 [15]=11
)
DEFAULT_DURATION="${DEFAULT_DURATION:-12}"   # 段号不在表里时的兜底时长

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
# 段提示词文件 —— 本脚本负责 段9–12
# -------------------------
if [ -z "${SEGMENT_FILES:-}" ]; then
  SEGMENT_DIR="${SEGMENT_DIR:-scripts/prompts/yinhang}"
  SEGMENT_FILES=()
  # 本脚本出片范围 段9–12；只重跑失败段时临时改这里的段号（图与时长按段号自动对上，输出名不变）。
  # 段1–4 用 -a，段5–8 用 -b，段13–15 用 -d；想一次跑完可改成 1..15。
  for i in 9 10 11 12; do SEGMENT_FILES+=("${SEGMENT_DIR}/seg${i}.txt"); done
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

# 校验某段参考图是否存在（URL/file:// 跳过本地校验）
validate_images() {
  local u resolved
  for u in "$@"; do
    resolved="$(prefix_dir "$u")"
    [ -f "$resolved" ] || [[ "$resolved" == http* ]] || [[ "$resolved" == file://* ]] \
      || { echo "错误：参考图不存在（也不是 URL）：${resolved}"; exit 1; }
  done
}

# 为某段构建 conditions JSON 数组（顺序即 <Subject N> / <Picture N>）
build_conditions() {
  local json='[]' u uri
  for u in "$@"; do
    uri="$(to_uri "$(prefix_dir "$u")")"
    json=$(printf '%s' "$json" | jq --arg uri "$uri" '. + [{type:"image", uri:$uri, role:"reference"}]')
  done
  printf '%s' "$json"
}

# 输出名由段提示词文件名推导（不用循环序号）：stem(seg3.txt)=seg3 -> ${OUTPUT_PREFIX}seg3.mp4
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

# 从段提示词文件名推段号：seg3.txt -> 3；取不到数字时回退为位置序号
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
echo "MiniMax-H3 sglang Ref2VA —— 银行卡限额与管控 C（段9–12 → ${BASE_URL}）"
echo "========================================"

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
  echo "Duration   : 逐段取值（本脚本合计 ${TOTAL_DUR}s / ${N_SEG} 段；全片 15 段=188s）"
fi
echo "Aspect     : ${ASPECT_RATIO}  ShortEdge: ${SHORT_EDGE}"
echo "Steps/Flow : ${STEPS}/${FLOW_SHIFT}/${AUDIO_FLOW_SHIFT}  Seed: ${SEED}  Out: ${OUTPUT_PREFIX}<段名>.mp4"
echo "Log file   : ${LOG_FILE}"
echo "段数       : ${N_SEG}"
echo "----------------------------------------"
for ((s=0; s<N_SEG; s++)); do
  _imgs_i="$(seg_imgs "${SEGMENT_FILES[s]}" "$s")"
  read -ra _chk <<< "${_imgs_i}"
  printf '  段%-3s %3ss  %-24s <- %s  角色图 %s 张\n' \
    "$(seg_idx "${SEGMENT_FILES[s]}" "$s")" "$(seg_dur "${SEGMENT_FILES[s]}" "$s")" \
    "$(seg_out "${SEGMENT_FILES[s]}")" "${SEGMENT_FILES[s]}" "${#_chk[@]}"
done
echo "========================================"

# 全量参考图校验（缺图/查不到段号对应图则立即中止）
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
#   服务端最终会把视频生成到磁盘，但 scheduler/client 有约 100 分钟超时，到时标 failed。
#     - 状态 failed/超时但服务端在线 → 不重提（会重复生成），继续等落盘（url/content）。
#     - 仅当服务端真挂了（job 丢失，拿不到状态）→ 才重提该段。
#   真实请求错误（如 400 参考图比例不合规）不靠重试自愈，直接放弃该段并打印返回体。
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
  echo "[$((s+1))/${N_SEG}] ${out} (${dur}s) <- ${SEGMENT_FILES[s]}   (角色图 ${#_imgs[@]} 张: ${imgs_i:-<空>}  开始 $(date '+%F %T'))"
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
  echo "C（段9–12）${N_SEG} 段完成："
  for o in "${OUT_FILES[@]}"; do echo "  ${o}"; done
  echo "  注：与 A（段1–4）、B（段5–8）、D（段13–15）的产物按 seg1..seg15 顺序合并后再 concat。"
else
  echo "完成，但以下段失败：${FAILED[*]}"
  echo "  可单独重跑对应段（输出名跟段提示词文件名走，不会错位）：SEGMENT_FILES=<该段.txt> bash $0"
  echo "  若出现 HTTP 400，优先查角色图宽高比是否在 1:4~4:1、URL 是否可被服务端取到。"
fi
echo "========================================"
echo "[log] end      : $(date '+%F %T')"
