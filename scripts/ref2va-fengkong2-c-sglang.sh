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
# MiniMax-H3 sglang Ref2VA —— 对公风控研判官（剧本定稿版）【C：段12–16 → :30012】
#   三脚本并行：A 段1–6 / B 段7–11 / C 段12–16，各打一个服务实例
# =========================
#
# 源文档：scripts/H3分镜_15s段_剧本定稿版_对公风控研判官.md
#   16 段共 205s（3'25"），段长 8–15s 各不相同；台词按剧本定稿 419 字未改。
#   本脚本跑 段12–16（67s）；A 跑 段1–6（77s）；B 跑 段7–11（61s）。
#   三者输出同为 fengkong2_segN.mp4，互不覆盖，跑完按 seg1..seg16 顺序拼接。
#
# ⚠ 三个脚本的 SEG_IMG_BY_IDX / SEG_DUR_BY_IDX 是同一份剧本的完整 16 段映射，
#   **改一个必须同步另两个**（冒烟测试里有逐字比对断言，改漏会立刻失败）。
#
# ── 段号 ↔ 时长 ↔ 上传图顺序（有图角色才占编号）────────────────────
#   段1  14s  xc
#   段2  10s  xc  ypg  xz
#   段3  11s  xz
#   段4  12s  ypg  xz  xl
#   段5  15s  xl  ypg
#   段6  15s  lz                                        ← 试生成推荐顺序：段7 → 段15 → 段6
#   段7   8s  lz                                        ← 红光彩蛋，全片成败点
#   段8  15s  lz
#   段9  13s  xc  ypg
#   段10 13s  xc  ypg
#   段11 12s  xc
#   段12 12s  xc                                        ← 销售负责人无图，已去编号用文字描述
#   段13 14s  xc  ypg
#   段14 11s  xc
#   段15 15s  xc  xz  lz  zxk  zbx                      ← 五人同框，风险最高
#   段16 15s  xc  xz  lz  zxk  zbx
#   ypg.png = 对公风控研判官（本版新增角色图）
#
# ── 编号规则 ──────────────────────────────────────────────────
# 服务端把 <Subject N> 按「本次调用的上传顺序」解释，所以只有有图角色占编号。
# 段12 原文把无图的销售负责人写成 <Subject 1>、小陈写成 <Subject 2>，会与
# 「第 1 张上传图」撞位；已在 md 与 prompts/fengkong2/seg12.txt 同步改为
# 小陈=<Subject 1>（唯一上传图 xc.png）、销售负责人用文字称呼不占编号。
# 配音标签 (Sx) 与 <Subject N> 互不影响，按段内先开口编号，勿改。
# 7 处 1 秒空白帧全在段内（段2/4/6/9/10/12/14），是剧本要求的转场，不是生成失败。
#
# ⚠ 画幅：源文档未写明比例，本脚本按内容默认 16:9；若改竖屏，A/B/C 三个必须一起改，
#   否则 16 段无法 concat。
#
# 参考图硬性约束（迁移服务器实测）：宽高比必须落在 1:4 ~ 4:1，否则服务端直接 400。
#
# 协议（sglang 服务端）：
#   POST /v1/videos (JSON body) -> 取 .id -> 轮询 GET /v1/videos/{id} -> 下载 GET /v1/videos/{id}/content
#
# 用法：
#   bash scripts/ref2va-fengkong2-a-sglang.sh &   # 段1–6  → :30010
#   bash scripts/ref2va-fengkong2-b-sglang.sh &   # 段7–11 → :30011
#   bash scripts/ref2va-fengkong2-c-sglang.sh &   # 段12–16→ :30012
#   # 换服务地址/端口：HOST=127.0.0.1 PORT=30021 bash scripts/ref2va-fengkong2-c-sglang.sh
#   # 只重跑其中几段：直接改下面「段提示词文件」处的 for i in ... 段号
#   # 角色图默认拼到 IMAGE_PREFIX=http://53.192.28.254:8210/images/ 下
#   #   本片需要：xc.png xz.png xl.png lz.png ypg.png zxk.png zbx.png 共 7 张
#
# 其它：DURATION(未设=按段取时长；显式设定=所有段统一)
#   SHORT_EDGE(768) / ASPECT_RATIO(16:9) / SEED(3101) / HOST(127.0.0.1) / PORT(30010)
#   FLOW_SHIFT(12.0) / AUDIO_FLOW_SHIFT(3.0) / STEPS(50) / NUM_OUTPUTS(1) / MODEL(MiniMaxAI/MiniMax-H3)
#   OUTPUT_PREFIX(fengkong2_)  输出名 = 前缀 + 段提示词文件名 stem，如 seg5.txt -> fengkong2_seg5.mp4
#
# 覆盖段/图/时长（高级，覆盖模式下按「位置」对应而非段号，须与段数一致）：
#   SEGMENT_FILES="a.txt b.txt"  SEGMENT_IMAGES_STR="xc.png|xc.png ypg.png"  SEGMENT_DURATIONS_STR="14|10"

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
OUTPUT_PREFIX="${OUTPUT_PREFIX:-fengkong2_}"
IMAGE_PREFIX="${IMAGE_PREFIX-http://53.192.28.254:8210/images/}"

# -------------------------
# 全部 16 段的角色图与时长：按「段号」索引（段号取自提示词文件名 stem）
#   图顺序即该段 <Subject 1..k>；只写有图角色，无图角色不占位。
#   ⚠ 必须与 ref2va-fengkong2-b-sglang.sh / -c-sglang.sh 中的同名表保持一致。
# -------------------------
declare -A SEG_IMG_BY_IDX=(
  [1]="xc.png"
  [2]="xc.png ypg.png xz.png"
  [3]="xz.png"
  [4]="ypg.png xz.png xl.png"
  [5]="xl.png ypg.png"
  [6]="lz.png"
  [7]="lz.png"
  [8]="lz.png"
  [9]="xc.png ypg.png"
  [10]="xc.png ypg.png"
  [11]="xc.png"
  [12]="xc.png"
  [13]="xc.png ypg.png"
  [14]="xc.png"
  [15]="xc.png xz.png lz.png zxk.png zbx.png"
  [16]="xc.png xz.png lz.png zxk.png zbx.png"
)
declare -A SEG_DUR_BY_IDX=(
  [1]=14 [2]=10 [3]=11 [4]=12 [5]=15 [6]=15 [7]=8 [8]=15
  [9]=13 [10]=13 [11]=12 [12]=12 [13]=14 [14]=11 [15]=15 [16]=15
)
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
# 段提示词文件 —— 本脚本负责 段12–16
# -------------------------
if [ -z "${SEGMENT_FILES:-}" ]; then
  SEGMENT_DIR="${SEGMENT_DIR:-scripts/prompts/fengkong2}"
  SEGMENT_FILES=()
  # 本脚本出片范围 段12–16；只重跑失败段时临时改这里的段号（图与时长按段号自动对上，输出名不变）。
  # 段1–6 用 -a 脚本，段7–11 用 -b 脚本；想一次跑完可改成 1..16。
  for i in 12 13 14 15 16; do SEGMENT_FILES+=("${SEGMENT_DIR}/seg${i}.txt"); done
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

# 为某段构建 conditions JSON 数组（顺序即 <Subject N>）
build_conditions() {
  local json='[]' u uri
  for u in "$@"; do
    uri="$(to_uri "$(prefix_dir "$u")")"
    json=$(printf '%s' "$json" | jq --arg uri "$uri" '. + [{type:"image", uri:$uri, role:"reference"}]')
  done
  printf '%s' "$json"
}

# 输出名由段提示词文件名推导（不用循环序号）：stem(seg5.txt)=seg5 -> ${OUTPUT_PREFIX}seg5.mp4
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

# 从段提示词文件名推段号：seg5.txt -> 5；取不到数字时回退为位置序号
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
echo "MiniMax-H3 sglang Ref2VA —— 对公风控研判官（定稿版）C（段12–16 → ${BASE_URL}）"
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
  echo "Duration   : 逐段取值（本脚本合计 ${TOTAL_DUR}s / ${N_SEG} 段；全片 16 段=205s）"
fi
echo "Aspect     : ${ASPECT_RATIO}  ShortEdge: ${SHORT_EDGE}"
echo "Steps/Flow : ${STEPS}/${FLOW_SHIFT}/${AUDIO_FLOW_SHIFT}  Seed: ${SEED}  Out: ${OUTPUT_PREFIX}<段名>.mp4"
echo "Log file   : ${LOG_FILE}"
echo "段数       : ${N_SEG}"
echo "----------------------------------------"
for ((s=0; s<N_SEG; s++)); do
  _imgs_i="$(seg_imgs "${SEGMENT_FILES[s]}" "$s")"
  read -ra _chk <<< "${_imgs_i}"
  printf '  段%-3s %3ss  %-26s <- %s  角色图 %s 张\n' \
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
  echo "C（段12–16）${N_SEG} 段完成："
  for o in "${OUT_FILES[@]}"; do echo "  ${o}"; done
  echo "  注：与 A（段1–6）、B（段7–11）的产物按 seg1..seg16 顺序合并后再 concat。"
else
  echo "完成，但以下段失败：${FAILED[*]}"
  echo "  可单独重跑对应段（输出名跟段提示词文件名走，不会错位）：SEGMENT_FILES=<该段.txt> bash $0"
  echo "  若出现 HTTP 400，优先查角色图宽高比是否在 1:4~4:1、URL 是否可被服务端取到。"
fi
echo "========================================"
echo "[log] end      : $(date '+%F %T')"
