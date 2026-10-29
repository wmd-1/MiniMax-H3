#!/usr/bin/env bash
set -uo pipefail

# =============================================================================
# MiniMax-H3 分镜批量脚本冒烟测试
# =============================================================================
#
# 被测对象：scripts/ref2va-xyk-a/b-sglang.sh（信用卡逾期还款纠纷化解 A/B）/
#           scripts/ref2va-yinhang-a/b/c/d-sglang.sh（银行卡限额与管控，四服务并行）/
#           scripts/ref2va-fengkong2-a/b/c-sglang.sh（定稿版风控，三段区间并行三服务）/
#           scripts/ref2va-yingxiao-a-sglang.sh / ref2va-yingxiao-b-sglang.sh（对公营销情报官 A/B）/
#           ref2va-fengkong-a-sglang.sh / ref2va-fengkong-b-sglang.sh（对公风控研判官 A/B）/
#           ref2va-jiaoxintong4-sglang.sh / ref2va-jiaoxintong3-sglang.sh /
#           ref2va-jiaoxintong2-sglang.sh / ref2va-jiaoxintong-sglang.sh /
#           ref2va-story-sglang.sh / ref2va-story.sh
#
# 覆盖点：
#   1) 输出视频命名 = OUTPUT_PREFIX + 段提示词文件名 stem（不按循环序号）
#   2) 每段独立参考图，且 conditions[] 顺序 == <Picture N> 顺序
#   3) jiaoxintong2 逐段时长（13/15/12/10/12/15/8/13/6，合计 104s）、jiaoxintong3（15×6+落板10，100s）
#      与 jiaoxintong4（7×15s，105s，16:9）
#   4) 单段重跑时命名/参考图/时长依然对得上
#   5) IMAGE_PREFIX：默认 http 前缀 / 本地目录转 file:// / 绝对路径原样
#   6) 覆盖参数与段数不一致时报错退出
#   7) 回归：环境传入单元素 SEGMENT_FILES 不再触发 set -u unbound
#
# 依赖：bash + jq + curl + python3。服务端由 tests/mock_video_server.py 模拟，
#       不接触真实 GPU 推理服务，也不会真的生成视频。
#
# 用法（项目规则要求后端测试在既有 Docker 环境中执行，推荐用留存的 h3-test 容器）：
#   docker exec h3-test bash -lc 'bash /work/tests/run-batch-script-tests.sh'
#
#   # h3-test 不存在时，用项目自有镜像建一个常驻测试容器（不新建镜像，jq 仅装在容器可写层）：
#   docker run -d --name h3-test --entrypoint bash \
#     -v "$(pwd)":/work:ro minimax-h3-sglang:latest -c 'sleep infinity'
#   docker exec h3-test bash -lc 'apt-get update -qq && apt-get install -y -qq jq'
#
# 可调：PORT（mock 监听端口，默认 30010）；KEEP_WORK=1 保留临时目录便于排查。
# =============================================================================

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${TESTS_DIR}/.." && pwd)"
PORT="${PORT:-30010}"
# 显式列出全 9 段，不让测试依赖被测脚本的默认段列表（用户临时改默认段不应弄挂测试）
ALL9="$(for i in 1 2 3 4 5 6 7 8 9; do printf '%s ' "${ROOT_DIR}/scripts/prompts/jiaoxintong2/seg${i}.txt"; done)"
ALL7="$(for i in 1 2 3 4 5 6 7; do printf '%s ' "${ROOT_DIR}/scripts/prompts/jiaoxintong3/seg${i}.txt"; done)"
ALL7V4="$(for i in 1 2 3 4 5 6 7; do printf '%s ' "${ROOT_DIR}/scripts/prompts/jiaoxintong4/seg${i}.txt"; done)"
WORK="$(mktemp -d /tmp/h3-batch-tests.XXXXXX)"
POSTS="${WORK}/posts.jsonl"
LOGDIR="${WORK}/logs"
mkdir -p "$LOGDIR"

PASS=0
FAIL=0
CASE=""

cleanup() {
  if [ -n "${MOCK_PID:-}" ] && kill -0 "${MOCK_PID}" 2>/dev/null; then
    kill "${MOCK_PID}" 2>/dev/null
    wait "${MOCK_PID}" 2>/dev/null
  fi
  if [ -n "${MOCK_B:-}" ] && kill -0 "${MOCK_B}" 2>/dev/null; then
    kill "${MOCK_B}" 2>/dev/null
    wait "${MOCK_B}" 2>/dev/null
  fi
  if [ -n "${MOCK_C:-}" ] && kill -0 "${MOCK_C}" 2>/dev/null; then
    kill "${MOCK_C}" 2>/dev/null
    wait "${MOCK_C}" 2>/dev/null
  fi
  if [ -n "${MOCK_D:-}" ] && kill -0 "${MOCK_D}" 2>/dev/null; then
    kill "${MOCK_D}" 2>/dev/null
    wait "${MOCK_D}" 2>/dev/null
  fi
  if [ "${KEEP_WORK:-0}" = "1" ]; then
    echo "[keep] 临时目录保留：${WORK}"
  else
    rm -rf "$WORK"
  fi
}
trap cleanup EXIT

ok()   { echo "    ✓ $1"; PASS=$((PASS + 1)); }
bad()  { echo "    ✗ $1"; FAIL=$((FAIL + 1)); }

assert_eq() {  # $1=期望 $2=实际 $3=说明
  if [ "$1" = "$2" ]; then ok "$3 = [$2]"; else bad "$3 期望=[$1] 实际=[$2]"; fi
}

assert_file() {  # $1=路径 $2=说明
  if [ -s "$1" ]; then ok "$2 ($(basename "$1"))"; else bad "$2：文件不存在或为空 $1"; fi
}

assert_lacks() {  # $1=文件 $2=模式 $3=说明
  if grep -q "$2" "$1" 2>/dev/null; then
    bad "$3：出现不该有的 [$2] —— $(grep -m1 "$2" "$1")"
  else
    ok "$3（无 [$2]）"
  fi
}

# 取第 N 条请求（1 基）的某个 jq 表达式结果
q() { sed -n "${1}p" "$POSTS" | jq -r "${2}"; }

# 第 N 条请求的参考图文件名列表（逗号分隔，去掉 URI 前缀）
imgs_of() {
  local out="" u
  while IFS= read -r u; do out+="${u##*/} "; done < <(q "$1" '.conditions[].uri')
  echo $out | tr ' ' ',' | sed 's/,$//'
}

reset_posts() { : > "$POSTS"; }

run_script() {  # $1=脚本名 $2=case日志名，其余为 KEY=VAL 环境变量
  local name="$1" tag="$2"; shift 2
  ( cd "$ROOT_DIR" && env PORT="$PORT" HOST=127.0.0.1 POLL_INTERVAL=1 \
      LOG_DIR="$LOGDIR" IMAGE_PREFIX="${IMAGE_PREFIX-http://53.192.28.254:8210/images/}" \
      "$@" bash "${ROOT_DIR}/scripts/${name}" ) > "${WORK}/${tag}.log" 2>&1
  echo $? > "${WORK}/${tag}.rc"
}

rc_of() { cat "${WORK}/${1}.rc"; }

# ----------------------------- 准备 mock 与素材 -----------------------------
echo "======================================================"
echo " MiniMax-H3 分镜批量脚本冒烟测试"
echo "======================================================"
echo "  仓库根  : ${ROOT_DIR}"
echo "  临时目录: ${WORK}"
echo "  mock 端口: ${PORT}"

command -v jq >/dev/null 2>&1 || { echo "缺少 jq，请在测试容器内安装： apt-get install -y jq"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "缺少 python3"; exit 2; }

reset_posts
python3 "${TESTS_DIR}/mock_video_server.py" --port "$PORT" --log "$POSTS" > "${WORK}/mock.log" 2>&1 &
MOCK_PID=$!

for i in $(seq 1 30); do
  curl -s -o /dev/null "http://127.0.0.1:${PORT}/health" && break
  sleep 0.3
done
curl -s -o /dev/null "http://127.0.0.1:${PORT}/health" || {
  echo "mock 服务未能启动："; cat "${WORK}/mock.log"; exit 2; }
echo "  mock    : 已就绪 (pid ${MOCK_PID})"

# 本地占位参考图（测 file:// 模式与 vLLM 脚本用）
for f in dxb.png hxr.png logo.png aaa.png bbb.png ccc.png \
         xc.png xz.png xl.png lz.png zxk.png zbx.png xw.png ts.png qbg.png \
         lay.png wdg.png zns.png \
         first_shot.png first_shot.PNG image1.png image2.png image3.png image4.png image5.png \
         image6.png image7.png image8.png image9.png image10.png \
         image133.png image134.png image135.png image136.png; do
  : > "${WORK}/${f}"
done

# 第二个 mock，专用于验证 A/B 两个服务并行接线
PORT_B="${PORT_B:-30012}"
POSTS_B="${WORK}/posts_b.jsonl"
python3 "${TESTS_DIR}/mock_video_server.py" --port "${PORT_B}" --log "${POSTS_B}" > "${WORK}/mock_b.log" 2>&1 &
MOCK_B=$!
PORT_C="${PORT_C:-30013}"
POSTS_C="${WORK}/posts_c.jsonl"
python3 "${TESTS_DIR}/mock_video_server.py" --port "${PORT_C}" --log "${POSTS_C}" > "${WORK}/mock_c.log" 2>&1 &
MOCK_C=$!
PORT_D="${PORT_D:-30014}"
POSTS_D="${WORK}/posts_d.jsonl"
python3 "${TESTS_DIR}/mock_video_server.py" --port "${PORT_D}" --log "${POSTS_D}" > "${WORK}/mock_d.log" 2>&1 &
MOCK_D=$!
sleep 1

# ================================= T1 =================================
CASE="T1 jiaoxintong2 全 9 段：逐段时长 / 逐段参考图 / stem 命名"
echo "── ${CASE}"
reset_posts
run_script ref2va-jiaoxintong2-sglang.sh t1 OUTPUT_PREFIX="${WORK}/jiaoxintong2_" SEGMENT_FILES="${ALL9}"
assert_eq "0" "$(rc_of t1)" "T1 退出码"
assert_eq "9" "$(wc -l < "$POSTS" | tr -d ' ')" "T1 提交请求数"
assert_eq "13 15 12 10 12 15 8 13 6" "$(jq -r '.target.duration_seconds' "$POSTS" | tr '\n' ' ' | sed 's/ $//')" "T1 逐段时长"
assert_eq "3 2 2 1 1 4 1 2 1" "$(jq -r '.conditions|length' "$POSTS" | tr '\n' ' ' | sed 's/ $//')" "T1 逐段参考图数"
assert_eq "9:16" "$(jq -r '.target.aspect_ratio' "$POSTS" | sort -u | tr '\n' ' ' | sed 's/ $//')" "T1 画幅"
assert_eq "first_shot.PNG,image4.png,image5.png" "$(imgs_of 1)" "T1 段1 图片顺序（含 .PNG 大写）"
assert_eq "image2.png,image3.png" "$(imgs_of 8)" "T1 段8 图片顺序"
assert_eq "image2.png" "$(imgs_of 9)" "T1 段9 图片顺序"
# 注：输出名 = OUTPUT_PREFIX + 段文件名 stem，因此前缀不能再带 seg，否则会拼成 ..._segseg1.mp4
for i in 1 2 3 4 5 6 7 8 9; do assert_file "${WORK}/jiaoxintong2_seg${i}.mp4" "T1 产出"; done
assert_lacks "${WORK}/t1.log" "unbound variable" "T1 无 set -u unbound"

# ================================= T2 =================================
CASE="T2 jiaoxintong2 单段重跑 seg7：命名/时长/图都对得上"
echo "── ${CASE}"
reset_posts
rm -f "${WORK}/jiaoxintong2_seg7.mp4"
run_script ref2va-jiaoxintong2-sglang.sh t2 \
  OUTPUT_PREFIX="${WORK}/jiaoxintong2_" \
  SEGMENT_FILES="${ROOT_DIR}/scripts/prompts/jiaoxintong2/seg7.txt"
assert_eq "0" "$(rc_of t2)" "T2 退出码"
assert_eq "1" "$(wc -l < "$POSTS" | tr -d ' ')" "T2 提交请求数"
assert_eq "8" "$(q 1 '.target.duration_seconds')" "T2 段7 时长"
assert_eq "image1.png" "$(imgs_of 1)" "T2 段7 参考图"
assert_file "${WORK}/jiaoxintong2_seg7.mp4" "T2 产出（不是 seg1）"
assert_lacks "${WORK}/t2.log" "unbound variable" "T2 无 set -u unbound"

# ================================= T3 =================================
CASE="T3 jiaoxintong(v1) 单段重跑 seg5：命名与图跟段号走"
echo "── ${CASE}"
reset_posts
run_script ref2va-jiaoxintong-sglang.sh t3 \
  OUTPUT_PREFIX="${WORK}/jiaoxintong_" \
  SEGMENT_FILES="${ROOT_DIR}/scripts/prompts/jiaoxintong/seg5.txt"
assert_eq "0" "$(rc_of t3)" "T3 退出码"
assert_eq "image133.png" "$(imgs_of 1)" "T3 段5 参考图"
assert_file "${WORK}/jiaoxintong_seg5.mp4" "T3 产出（不是 seg1）"
assert_lacks "${WORK}/t3.log" "unbound variable" "T3 无 set -u unbound"

# ================================= T4 =================================
CASE="T4 story-sglang 单段重跑 seg3：命名跟文件名（旧行为会叫 story_seg1）"
echo "── ${CASE}"
reset_posts
run_script ref2va-story-sglang.sh t4 \
  OUTPUT_PREFIX="${WORK}/story_" \
  SEGMENT_FILES="${ROOT_DIR}/scripts/prompts/story/seg3.txt" \
  REF_IMAGE_URIS="${WORK}/dxb.png ${WORK}/hxr.png ${WORK}/logo.png"
assert_eq "0" "$(rc_of t4)" "T4 退出码"
assert_eq "dxb.png,hxr.png,logo.png" "$(imgs_of 1)" "T4 每段共用 3 张 subject 图"
assert_file "${WORK}/story_seg3.mp4" "T4 产出"
assert_lacks "${WORK}/t4.log" "unbound variable" "T4 无 set -u unbound"

# ================================= T5 =================================
CASE="T5 story(vLLM 同步) 默认 4 段命名"
echo "── ${CASE}"
reset_posts
run_script ref2va-story.sh t5 \
  OUTPUT_PREFIX="${WORK}/storyv_" \
  REF_IMAGES="${WORK}/dxb.png ${WORK}/hxr.png ${WORK}/logo.png"
assert_eq "0" "$(rc_of t5)" "T5 退出码"
for i in 1 2 3 4; do assert_file "${WORK}/storyv_seg${i}.mp4" "T5 产出"; done
assert_lacks "${WORK}/t5.log" "unbound variable" "T5 无 set -u unbound"

# ================================= T6 =================================
CASE="T6 SEGMENT_DURATIONS_STR 与段数不一致应报错退出"
echo "── ${CASE}"
reset_posts
run_script ref2va-jiaoxintong2-sglang.sh t6 \
  OUTPUT_PREFIX="${WORK}/jiaoxintong2_" \
  SEGMENT_FILES="${ROOT_DIR}/scripts/prompts/jiaoxintong2/seg1.txt ${ROOT_DIR}/scripts/prompts/jiaoxintong2/seg2.txt ${ROOT_DIR}/scripts/prompts/jiaoxintong2/seg3.txt" \
  SEGMENT_DURATIONS_STR="10|20"
assert_eq "1" "$(rc_of t6)" "T6 退出码（非 0）"
if grep -q "不一致" "${WORK}/t6.log"; then ok "T6 输出不一致报错"; else bad "T6 未见报错文本"; fi
assert_eq "0" "$(wc -l < "$POSTS" | tr -d ' ')" "T6 未提交任何请求"

# ================================= T7 =================================
CASE="T7 SEGMENT_IMAGES_STR 覆盖生效（段数一致）"
echo "── ${CASE}"
reset_posts
run_script ref2va-jiaoxintong2-sglang.sh t7 \
  OUTPUT_PREFIX="${WORK}/ovr_" \
  SEGMENT_FILES="${ROOT_DIR}/scripts/prompts/jiaoxintong2/seg1.txt ${ROOT_DIR}/scripts/prompts/jiaoxintong2/seg2.txt" \
  SEGMENT_IMAGES_STR="${WORK}/aaa.png ${WORK}/bbb.png|${WORK}/ccc.png" \
  SEGMENT_DURATIONS_STR="7|9"
assert_eq "0" "$(rc_of t7)" "T7 退出码"
assert_eq "aaa.png,bbb.png" "$(imgs_of 1)" "T7 段1 用覆盖图"
assert_eq "ccc.png" "$(imgs_of 2)" "T7 段2 用覆盖图"
assert_eq "7 9" "$(jq -r '.target.duration_seconds' "$POSTS" | tr '\n' ' ' | sed 's/ $//')" "T7 逐段覆盖时长"
for i in 1 2; do assert_file "${WORK}/ovr_seg${i}.mp4" "T7 产出"; done

# ================================= T8 =================================
CASE="T8 IMAGE_PREFIX 指向本地目录时转成 file:// URI"
echo "── ${CASE}"
reset_posts
run_script ref2va-jiaoxintong2-sglang.sh t8 \
  OUTPUT_PREFIX="${WORK}/local_" IMAGE_PREFIX="${WORK}/" \
  SEGMENT_FILES="${ROOT_DIR}/scripts/prompts/jiaoxintong2/seg4.txt"
assert_eq "0" "$(rc_of t8)" "T8 退出码"
assert_eq "file://" "$(q 1 '.conditions[0].uri' | cut -c1-7)" "T8 URI 前缀"
assert_eq "image9.png" "$(imgs_of 1)" "T8 段4 参考图"

# ================================= T9 =================================
CASE="T9 IMAGE_PREFIX 默认 http 前缀"
echo "── ${CASE}"
reset_posts
run_script ref2va-jiaoxintong2-sglang.sh t9 \
  OUTPUT_PREFIX="${WORK}/http_" \
  SEGMENT_FILES="${ROOT_DIR}/scripts/prompts/jiaoxintong2/seg4.txt"
assert_eq "0" "$(rc_of t9)" "T9 退出码"
assert_eq "http://53.192.28.254:8210/images/image9.png" "$(q 1 '.conditions[0].uri')" "T9 完整 URI"

# ================================= T10 =================================
CASE="T10 jiaoxintong3 扫码入职 7 段：16:9 / 逐段时长 / 逐段参考图"
echo "── ${CASE}"
reset_posts
run_script ref2va-jiaoxintong3-sglang.sh t10 OUTPUT_PREFIX="${WORK}/jiaoxintong3_" SEGMENT_FILES="${ALL7}"
assert_eq "0" "$(rc_of t10)" "T10 退出码"
assert_eq "7" "$(wc -l < "$POSTS" | tr -d ' ')" "T10 提交请求数"
assert_eq "16:9" "$(jq -r '.target.aspect_ratio' "$POSTS" | sort -u | tr '\n' ' ' | sed 's/ $//')" "T10 画幅"
assert_eq "15 15 15 15 15 15 10" "$(jq -r '.target.duration_seconds' "$POSTS" | tr '\n' ' ' | sed 's/ $//')" "T10 逐段时长"
assert_eq "3 3 2 2 2 1 1" "$(jq -r '.conditions|length' "$POSTS" | tr '\n' ' ' | sed 's/ $//')" "T10 逐段参考图数"
assert_eq "first_shot.PNG,image2.png,image3.png" "$(imgs_of 1)" "T10 段1 图片顺序"
assert_eq "image3.png,image4.png,image5.png" "$(imgs_of 2)" "T10 段2 图片顺序（与段1共用 image3 做衔接）"
assert_eq "image10.png" "$(imgs_of 6)" "T10 段6 图片"
assert_eq "first_shot.PNG" "$(imgs_of 7)" "T10 段7 落板图片（大写 .PNG 保持）"
for i in 1 2 3 4 5 6 7; do assert_file "${WORK}/jiaoxintong3_seg${i}.mp4" "T10 产出"; done
assert_lacks "${WORK}/t10.log" "unbound variable" "T10 无 set -u unbound"

# =============================== T11 ===============================
CASE="T11 jiaoxintong3 单段重跑 seg7（落板段：10s / 无旁白 / 输出名不错位）"
echo "── ${CASE}"
reset_posts
run_script ref2va-jiaoxintong3-sglang.sh t11 \
  OUTPUT_PREFIX="${WORK}/jiaoxintong3_" \
  SEGMENT_FILES="${ROOT_DIR}/scripts/prompts/jiaoxintong3/seg7.txt"
assert_eq "0" "$(rc_of t11)" "T11 退出码"
assert_eq "1" "$(wc -l < "$POSTS" | tr -d ' ')" "T11 提交请求数"
assert_eq "10" "$(q 1 '.target.duration_seconds')" "T11 段7 时长"
assert_eq "first_shot.PNG" "$(imgs_of 1)" "T11 段7 参考图"
assert_file "${WORK}/jiaoxintong3_seg7.mp4" "T11 产出（不是 seg1）"

# ================================= T12 =================================
CASE="T12 jiaoxintong4 扫码入职 7×15s：16:9 / 单图段 / 图片顺序"
echo "── ${CASE}"
reset_posts
run_script ref2va-jiaoxintong4-sglang.sh t12 OUTPUT_PREFIX="${WORK}/jiaoxintong4_" SEGMENT_FILES="${ALL7V4}"
assert_eq "0" "$(rc_of t12)" "T12 退出码"
assert_eq "7" "$(wc -l < "$POSTS" | tr -d ' ')" "T12 提交请求数"
assert_eq "16:9" "$(jq -r '.target.aspect_ratio' "$POSTS" | sort -u | tr '\n' ' ' | sed 's/ $//')" "T12 画幅"
assert_eq "15 15 15 15 15 15 15" "$(jq -r '.target.duration_seconds' "$POSTS" | tr '\n' ' ' | sed 's/ $//')" "T12 逐段时长"
assert_eq "2 2 1 1 1 2 2" "$(jq -r '.conditions|length' "$POSTS" | tr '\n' ' ' | sed 's/ $//')" "T12 逐段参考图数"
assert_eq "first_shot.PNG,image2.png" "$(imgs_of 1)" "T12 段1 图片顺序"
assert_eq "image3.png,image4.png" "$(imgs_of 2)" "T12 段2 图片顺序"
assert_eq "image5.png" "$(imgs_of 3)" "T12 段3 单图"
assert_eq "image8.png,image9.png" "$(imgs_of 6)" "T12 段6 图片顺序"
assert_eq "image10.png,first_shot.PNG" "$(imgs_of 7)" "T12 段7 图片顺序（落板图在第二位）"
for i in 1 2 3 4 5 6 7; do assert_file "${WORK}/jiaoxintong4_seg${i}.mp4" "T12 产出"; done
assert_lacks "${WORK}/t12.log" "unbound variable" "T12 无 set -u unbound"
assert_lacks "${WORK}/t12.log" $'\r' "T12 日志无 CRLF 残留"

# =============================== T13 ===============================
CASE="T13 jiaoxintong4 单段重跑 seg5（单图段：15s / image7.png / 输出名不错位）"
echo "── ${CASE}"
reset_posts
run_script ref2va-jiaoxintong4-sglang.sh t13 \
  OUTPUT_PREFIX="${WORK}/jiaoxintong4_" \
  SEGMENT_FILES="${ROOT_DIR}/scripts/prompts/jiaoxintong4/seg5.txt"
assert_eq "0" "$(rc_of t13)" "T13 退出码"
assert_eq "1" "$(wc -l < "$POSTS" | tr -d ' ')" "T13 提交请求数"
assert_eq "15" "$(q 1 '.target.duration_seconds')" "T13 段5 时长"
assert_eq "image7.png" "$(imgs_of 1)" "T13 段5 单图"
assert_file "${WORK}/jiaoxintong4_seg5.mp4" "T13 产出（不是 seg1）"

# ================================= T14 =================================
CASE="T14 fengkong A 半（段1–6）：时长/角色图顺序/16:9/stem 命名"
echo "── ${CASE}"
reset_posts
run_script ref2va-fengkong-a-sglang.sh t14 OUTPUT_PREFIX="${WORK}/fk_"
assert_eq "0" "$(rc_of t14)" "T14 退出码"
assert_eq "6" "$(wc -l < "$POSTS" | tr -d ' ')" "T14 提交请求数"
assert_eq "16:9" "$(jq -r '.target.aspect_ratio' "$POSTS" | sort -u | tr '\n' ' ' | sed 's/ $//')" "T14 画幅"
assert_eq "15 15 15 15 15 14" "$(jq -r '.target.duration_seconds' "$POSTS" | tr '\n' ' ' | sed 's/ $//')" "T14 段1-6 时长"
assert_eq "xc.png,xz.png,zxk.png" "$(imgs_of 1)" "T14 段1 角色图顺序（原全局 Subject 1,2,5→段内 1,2,3）"
assert_eq "xc.png"        "$(imgs_of 2)" "T14 段2 角色图"
assert_eq "xc.png,xz.png" "$(imgs_of 3)" "T14 段3 角色图顺序"
assert_eq "xz.png"        "$(imgs_of 4)" "T14 段4（原全局 Subject 2→段内 1）"
assert_eq "xl.png,lz.png" "$(imgs_of 5)" "T14 段5（原全局 3,4→段内 1,2）"
assert_eq "lz.png"        "$(imgs_of 6)" "T14 段6（原全局 4→段内 1）"
for i in 1 2 3 4 5 6; do assert_file "${WORK}/fk_seg${i}.mp4" "T14 产出"; done
assert_eq "0" "$(ls -1 "${WORK}"/fk_seg7.mp4 2>/dev/null | wc -l | tr -d ' ')" "T14 未越界跑段7"

# ================================= T15 =================================
CASE="T15 fengkong B 半（段7–12）：打到第二个服务 PORT_B"
echo "── ${CASE}"
: > "$POSTS_B"
run_script ref2va-fengkong-b-sglang.sh t15 OUTPUT_PREFIX="${WORK}/fk_" PORT="${PORT_B}"
assert_eq "0" "$(rc_of t15)" "T15 退出码"
assert_eq "6" "$(wc -l < "$POSTS_B" | tr -d ' ')" "T15 提交到第二服务的请求数"
assert_eq "6" "$(wc -l < "$POSTS" | tr -d ' ')" "T15 主服务请求数未变（B 没误打过来）"
bdurs=$(jq -r '.target.duration_seconds' "$POSTS_B" | tr '\n' ' ' | sed 's/ $//')
assert_eq "14 14 15 15 14 14" "$bdurs" "T15 段7-12 时长"
assert_eq "lz.png" "$(sed -n 1p "$POSTS_B" | jq -r '[.conditions[].uri|split("/")|last]|join(",")')" "T15 段7 角色图"
assert_eq "xc.png" "$(sed -n 2p "$POSTS_B" | jq -r '[.conditions[].uri|split("/")|last]|join(",")')" "T15 段8（无图角色不占上传位）"
assert_eq "zxk.png,zbx.png" "$(sed -n 6p "$POSTS_B" | jq -r '[.conditions[].uri|split("/")|last]|join(",")')" "T15 段12 角色图顺序"
for i in 7 8 9 10 11 12; do assert_file "${WORK}/fk_seg${i}.mp4" "T15 产出"; done

# ================================= T16 =================================
CASE="T16 A+B 合并：12 段无重叠、时长表完整、可顺序拼接"
echo "── ${CASE}"
combined="$(jq -r '.target.duration_seconds' "$POSTS" | tr '\n' ' '; jq -r '.target.duration_seconds' "$POSTS_B" | tr '\n' ' ')"
assert_eq "15 15 15 15 15 14 14 14 15 15 14 14" "$(echo $combined)" "T16 全 12 段时长序列"
assert_eq "12" "$(( $(wc -l < "$POSTS") + $(wc -l < "$POSTS_B") ))" "T16 两服务合计请求数"
assert_eq "175" "$(jq -r '.target.duration_seconds' "$POSTS" "$POSTS_B" | awk '{s+=$1} END{print s}')" "T16 全片生成总时长(字卡另算 4s)"
nfiles=$(ls -1 "${WORK}"/fk_seg*.mp4 2>/dev/null | wc -l | tr -d ' ')
assert_eq "12" "$nfiles" "T16 seg1..12 产出齐全（无互相覆盖）"

# ================================= T17 =================================
CASE="T17 prompt 与图表一致性：conditions 数 == 段内有图 Subject 数，且标签连续"
echo "── ${CASE}"
bad=0
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  p="${ROOT_DIR}/scripts/prompts/fengkong/seg${i}.txt"
  n_img=$(grep '^<Subject [0-9]*> is' "$p" | grep -cE 'from [a-z]+\.png')
  labels=$(grep '^<Subject [0-9]*> is' "$p" | grep -E 'from [a-z]+\.png' | grep -o '[0-9]*' | head -1)
  maxl=$(grep '^<Subject [0-9]*> is' "$p" | grep -E 'from [a-z]+\.png' | grep -o '[0-9]*' | sort -n | tail -1)
  # 图表里的图数（从 A 脚本的表取，保证脚本与提示词不跑偏）
  tbl=$(grep -oE "^  \[$i\]=\"[^\"]*\"" "${ROOT_DIR}/scripts/ref2va-fengkong-a-sglang.sh" | sed -E 's/^  \[[0-9]+\]="//; s/"$//')
  tbl_cnt=$(echo $tbl | wc -w | tr -d ' ')
  if [ "$n_img" != "$tbl_cnt" ] || [ "${labels:-1}" != "1" ] || [ "${maxl:-1}" != "$n_img" ]; then
    bad=$((bad + 1))
    echo "      ✗ 段${i}: 内有图=${n_img} 表内图数=${tbl_cnt} 首标签=${labels:-?} 最大标签=${maxl:-?}"
  fi
done
if [ "$bad" -eq 0 ]; then ok "T17 12 段的 conditions 数、图表、标签连续性全部一致"; else bad "T17 有 ${bad} 段不一致"; fi

# ================================= T18 =================================
CASE="T18 yingxiao A 半（段1–7）：全 15s / xw恒为1 / 三图段仅段2"
echo "── ${CASE}"
reset_posts
run_script ref2va-yingxiao-a-sglang.sh t18 OUTPUT_PREFIX="${WORK}/yx_"
assert_eq "0" "$(rc_of t18)" "T18 退出码"
assert_eq "7" "$(wc -l < "$POSTS" | tr -d ' ')" "T18 提交请求数"
assert_eq "16:9" "$(jq -r '.target.aspect_ratio' "$POSTS" | sort -u | tr '\n' ' ' | sed 's/ $//')" "T18 画幅"
assert_eq "15 15 15 15 15 15 15" "$(jq -r '.target.duration_seconds' "$POSTS" | tr '\n' ' ' | sed 's/ $//')" "T18 段1-7 时长"
assert_eq "xw.png,ts.png"        "$(imgs_of 1)" "T18 段1 上传顺序"
assert_eq "xw.png,ts.png,qbg.png" "$(imgs_of 2)" "T18 段2 上传顺序（全片唯一三图段）"
assert_eq "xw.png,qbg.png"       "$(imgs_of 3)" "T18 段3 上传顺序"
assert_eq "xw.png,qbg.png"       "$(imgs_of 7)" "T18 段7 上传顺序"
for i in 1 2 3 4 5 6 7; do assert_file "${WORK}/yx_seg${i}.mp4" "T18 产出"; done
assert_eq "0" "$(ls -1 "${WORK}"/yx_seg8.mp4 2>/dev/null | wc -l | tr -d ' ')" "T18 未越界跑段8"

# ================================= T19 =================================
CASE="T19 yingxiao B 半（段8–14）：打到第二个服务 PORT_B"
echo "── ${CASE}"
: > "$POSTS_B"
run_script ref2va-yingxiao-b-sglang.sh t19 OUTPUT_PREFIX="${WORK}/yx_" PORT="${PORT_B}"
assert_eq "0" "$(rc_of t19)" "T19 退出码"
assert_eq "7" "$(wc -l < "$POSTS_B" | tr -d ' ')" "T19 提交到第二服务的请求数"
assert_eq "7" "$(wc -l < "$POSTS" | tr -d ' ')" "T19 主服务请求数未变（B 没误打过来）"
assert_eq "15 15 15 15 15 15 15" "$(jq -r '.target.duration_seconds' "$POSTS_B" | tr '\n' ' ' | sed 's/ $//')" "T19 段8-14 时长"
assert_eq "xw.png,qbg.png" "$(sed -n 1p "$POSTS_B" | jq -r '[.conditions[].uri|split("/")|last]|join(",")')" "T19 段8 上传顺序"
assert_eq "xw.png,qbg.png" "$(sed -n 7p "$POSTS_B" | jq -r '[.conditions[].uri|split("/")|last]|join(",")')" "T19 段14 上传顺序"
for i in 8 9 10 11 12 13 14; do assert_file "${WORK}/yx_seg${i}.mp4" "T19 产出"; done

# ================================= T20 =================================
CASE="T20 yingxiao A+B 合并：14 段无重叠、总时长 210s、A/B 两张表一致"
echo "── ${CASE}"
assert_eq "14" "$(( $(wc -l < "$POSTS") + $(wc -l < "$POSTS_B") ))" "T20 两服务合计请求数"
assert_eq "210" "$(jq -r '.target.duration_seconds' "$POSTS" "$POSTS_B" | awk '{s+=$1} END{print s}')" "T20 全片总时长"
assert_eq "14" "$(ls -1 "${WORK}"/yx_seg*.mp4 2>/dev/null | wc -l | tr -d ' ')" "T20 seg1..14 产出齐全"
# A/B 两份脚本的参考图表必须逐字一致（拆两半并行时最容易改漏一边）
difft=$(diff <(grep -A20 'declare -A SEG_IMG_BY_IDX' "${ROOT_DIR}/scripts/ref2va-yingxiao-a-sglang.sh" | sed -nE 's/^  \[[0-9]+\]=.*/&/p') \
             <(grep -A20 'declare -A SEG_IMG_BY_IDX' "${ROOT_DIR}/scripts/ref2va-yingxiao-b-sglang.sh" | sed -nE 's/^  \[[0-9]+\]=.*/&/p') | grep -c '^[<>]')
assert_eq "0" "$difft" "T20 A/B 两份脚本的角色图表完全一致"

# ================================= T21 =================================
CASE="T21 yingxiao 提示词自身一致性：<Subject K> 与 <Picture K> 一一对应且连续"
echo "── ${CASE}"
bad=0
for i in $(seq 1 14); do
  p="${ROOT_DIR}/scripts/prompts/yingxiao/seg${i}.txt"
  pairs=$(grep '^<Subject [0-9]*> is' "$p" | sed -nE 's/^<Subject ([0-9]+)>.*<Picture ([0-9]+)> \(([a-z]+\.png)\).*/\1 \2 \3/p')
  mis=$(echo "$pairs" | awk '$1!=$2{print "S"$1"≠P"$2}' | tr '\n' ' ')
  cnt=$(echo "$pairs" | grep -c .)
  first=$(echo "$pairs" | awk 'NR==1{print $1}')
  maxl=$(echo "$pairs" | awk '{if($1>m)m=$1} END{print m+0}')
  tbl=$(grep -oE "^  \[$i\]=\"[^\"]*\"" "${ROOT_DIR}/scripts/ref2va-yingxiao-a-sglang.sh" | sed -E 's/^  \[[0-9]+\]="//; s/"$//')
  tbl_cnt=$(echo $tbl | wc -w | tr -d ' ')
  if [ -n "$mis" ] || [ "$first" != "1" ] || [ "$maxl" != "$cnt" ] || [ "$cnt" != "$tbl_cnt" ]; then
    bad=$((bad + 1)); echo "      ✗ 段${i}: 错位=[$mis] 首标签=$first 最大=$maxl 定义数=$cnt 表内=$tbl_cnt"
  fi
done
if [ "$bad" -eq 0 ]; then ok "T21 14 段均 Subject↔Picture 一一对应、连续、与脚本表一致"; else bad "T21 有 ${bad} 段不一致"; fi

# ================================= T22 =================================
CASE="T22 fengkong2 A（段1–6）：逐段时长/上传图顺序/段12外均含ypg"
echo "── ${CASE}"
reset_posts; : > "$POSTS_C"
run_script ref2va-fengkong2-a-sglang.sh t22 OUTPUT_PREFIX="${WORK}/fk2_"
assert_eq "0" "$(rc_of t22)" "T22 退出码"
assert_eq "6" "$(wc -l < "$POSTS" | tr -d ' ')" "T22 提交请求数"
assert_eq "16:9" "$(jq -r '.target.aspect_ratio' "$POSTS" | sort -u | tr '\n' ' ' | sed 's/ $//')" "T22 画幅"
assert_eq "14 10 11 12 15 15" "$(jq -r '.target.duration_seconds' "$POSTS" | tr '\n' ' ' | sed 's/ $//')" "T22 段1-6 时长"
assert_eq "xc.png"                  "$(imgs_of 1)" "T22 段1 单图"
assert_eq "xc.png,ypg.png,xz.png"   "$(imgs_of 2)" "T22 段2 上传顺序（ypg 为 Subject 2）"
assert_eq "ypg.png,xz.png,xl.png"   "$(imgs_of 4)" "T22 段4 上传顺序（ypg 开头）"
assert_eq "xl.png,ypg.png"          "$(imgs_of 5)" "T22 段5 上传顺序"
assert_eq "lz.png"                  "$(imgs_of 6)" "T22 段6 单图"
for i in 1 2 3 4 5 6; do assert_file "${WORK}/fk2_seg${i}.mp4" "T22 产出"; done

# ================================= T23 =================================
CASE="T23 fengkong2 B（段7–11）：打到第二个服务 PORT_B"
echo "── ${CASE}"
: > "$POSTS_B"
run_script ref2va-fengkong2-b-sglang.sh t23 OUTPUT_PREFIX="${WORK}/fk2_" PORT="${PORT_B}"
assert_eq "0" "$(rc_of t23)" "T23 退出码"
assert_eq "5" "$(wc -l < "$POSTS_B" | tr -d ' ')" "T23 第二服务请求数"
assert_eq "8 15 13 13 12" "$(jq -r '.target.duration_seconds' "$POSTS_B" | tr '\n' ' ' | sed 's/ $//')" "T23 段7-11 时长"
assert_eq "lz.png"        "$(sed -n 1p "$POSTS_B" | jq -r '[.conditions[].uri|split("/")|last]|join(",")')" "T23 段7"
assert_eq "xc.png,ypg.png" "$(sed -n 3p "$POSTS_B" | jq -r '[.conditions[].uri|split("/")|last]|join(",")')" "T23 段9"
assert_eq "xc.png"         "$(sed -n 5p "$POSTS_B" | jq -r '[.conditions[].uri|split("/")|last]|join(",")')" "T23 段11"
for i in 7 8 9 10 11; do assert_file "${WORK}/fk2_seg${i}.mp4" "T23 产出"; done

# ================================= T24 =================================
CASE="T24 fengkong2 C（段12–16）：第三服务；段12 只传 xc（无图角色已去编号）"
echo "── ${CASE}"
run_script ref2va-fengkong2-c-sglang.sh t24 OUTPUT_PREFIX="${WORK}/fk2_" PORT="${PORT_C}"
assert_eq "0" "$(rc_of t24)" "T24 退出码"
assert_eq "5" "$(wc -l < "$POSTS_C" | tr -d ' ')" "T24 第三服务请求数"
assert_eq "12 14 11 15 15" "$(jq -r '.target.duration_seconds' "$POSTS_C" | tr '\n' ' ' | sed 's/ $//')" "T24 段12-16 时长"
assert_eq "xc.png" "$(sed -n 1p "$POSTS_C" | jq -r '[.conditions[].uri|split("/")|last]|join(",")')" "T24 段12 只传 1 张（销售负责人不占位）"
assert_eq "xc.png,xz.png,lz.png,zxk.png,zbx.png" "$(sed -n 4p "$POSTS_C" | jq -r '[.conditions[].uri|split("/")|last]|join(",")')" "T24 段15 五人同框图序"
for i in 12 13 14 15 16; do assert_file "${WORK}/fk2_seg${i}.mp4" "T24 产出"; done

# ================================= T25 =================================
CASE="T25 fengkong2 三服务合并：16 段无重叠、总时长 205s、三份表一致"
echo "── ${CASE}"
assert_eq "16" "$(( $(wc -l < "$POSTS") + $(wc -l < "$POSTS_B") + $(wc -l < "$POSTS_C") ))" "T25 三服务合计请求数"
assert_eq "205" "$(jq -r '.target.duration_seconds' "$POSTS" "$POSTS_B" "$POSTS_C" | awk '{s+=$1} END{print s}')" "T25 全片总时长"
assert_eq "16" "$(ls -1 "${WORK}"/fk2_seg*.mp4 2>/dev/null | wc -l | tr -d ' ')" "T25 seg1..16 产出齐全"
ta=$(grep -A20 '^declare -A SEG_IMG_BY_IDX' "${ROOT_DIR}/scripts/ref2va-fengkong2-a-sglang.sh" | sed -nE 's/^  \[[0-9]+\]=.*/&/p')
tb=$(grep -A20 '^declare -A SEG_IMG_BY_IDX' "${ROOT_DIR}/scripts/ref2va-fengkong2-b-sglang.sh" | sed -nE 's/^  \[[0-9]+\]=.*/&/p')
tc=$(grep -A20 '^declare -A SEG_IMG_BY_IDX' "${ROOT_DIR}/scripts/ref2va-fengkong2-c-sglang.sh" | sed -nE 's/^  \[[0-9]+\]=.*/&/p')
assert_eq "$ta" "$tb" "T25 A/B 映射表逐字一致"; assert_eq "$ta" "$tc" "T25 A/C 映射表逐字一致"

# ================================= T26 =================================
CASE="T26 银行卡限额与管控：四脚本分段、四服务并行、合计 188s"
echo "── ${CASE}"
reset_posts; : > "$POSTS_B"; : > "$POSTS_C"; : > "$POSTS_D"
run_script ref2va-yinhang-a-sglang.sh t31 OUTPUT_PREFIX="${WORK}/yh_"
assert_eq "0" "$(rc_of t31)" "T26 A 退出码"
assert_eq "4" "$(wc -l < "$POSTS" | tr -d ' ')" "T26 A 段1-4 请求数"
assert_eq "16:9" "$(jq -r '.target.aspect_ratio' "$POSTS" | sort -u | tr '\n' ' ' | sed 's/ $//')" "T26 画幅"
assert_eq "11 14 14 11" "$(jq -r '.target.duration_seconds' "$POSTS" | tr '\n' ' ' | sed 's/ $//')" "T26 A 逐段时长"
assert_eq "lay.png,xl.png" "$(imgs_of 1)" "T26 段1 图序（李阿姨在前）"
assert_eq "xl.png,lay.png" "$(imgs_of 2)" "T26 段2 图序（小刘在前，同两人换序）"

run_script ref2va-yinhang-b-sglang.sh t31b OUTPUT_PREFIX="${WORK}/yh_" PORT="${PORT_B}"
assert_eq "0" "$(rc_of t31b)" "T26 B 退出码"
assert_eq "4" "$(wc -l < "$POSTS_B" | tr -d ' ')" "T26 B 段5-8 请求数（第二服务）"
assert_eq "13 13 13 12" "$(jq -r '.target.duration_seconds' "$POSTS_B" | tr '\n' ' ' | sed 's/ $//')" "T26 B 逐段时长"
assert_eq "wdg.png,xl.png" "$(sed -n 1p "$POSTS_B" | jq -r '[.conditions[].uri|split("/")|last]|join(",")')" "T26 段5 图序"

run_script ref2va-yinhang-c-sglang.sh t31c OUTPUT_PREFIX="${WORK}/yh_" PORT="${PORT_C}"
assert_eq "0" "$(rc_of t31c)" "T26 C 退出码"
assert_eq "4" "$(wc -l < "$POSTS_C" | tr -d ' ')" "T26 C 段9-12 请求数（第三服务）"
assert_eq "12 11 13 12" "$(jq -r '.target.duration_seconds' "$POSTS_C" | tr '\n' ' ' | sed 's/ $//')" "T26 C 逐段时长"
assert_eq "zns.png,xl.png" "$(sed -n 3p "$POSTS_C" | jq -r '[.conditions[].uri|split("/")|last]|join(",")')" "T26 段11 图序"

run_script ref2va-yinhang-d-sglang.sh t31d OUTPUT_PREFIX="${WORK}/yh_" PORT="${PORT_D}"
assert_eq "0" "$(rc_of t31d)" "T26 D 退出码"
assert_eq "3" "$(wc -l < "$POSTS_D" | tr -d ' ')" "T26 D 段13-15 请求数（第四服务）"
assert_eq "14 14 11" "$(jq -r '.target.duration_seconds' "$POSTS_D" | tr '\n' ' ' | sed 's/ $//')" "T26 D 逐段时长"
assert_eq "xl.png" "$(sed -n 2p "$POSTS_D" | jq -r '[.conditions[].uri|split("/")|last]|join(",")')" "T26 段14 单图段"
assert_eq "lay.png,wdg.png,zns.png,xl.png" "$(sed -n 3p "$POSTS_D" | jq -r '[.conditions[].uri|split("/")|last]|join(",")')" "T26 段15 四图段"

assert_eq "15" "$(( $(wc -l < "$POSTS") + $(wc -l < "$POSTS_B") + $(wc -l < "$POSTS_C") + $(wc -l < "$POSTS_D") ))" "T26 四服务合计请求数"
assert_eq "188" "$(jq -r '.target.duration_seconds' "$POSTS" "$POSTS_B" "$POSTS_C" "$POSTS_D" | awk '{s+=$1} END{print s}')" "T26 全片总时长"
assert_eq "15" "$(ls -1 "${WORK}"/yh_seg*.mp4 2>/dev/null | wc -l | tr -d ' ')" "T26 seg1..15 产出齐全无覆盖"
ya=$(grep -A16 '^declare -A SEG_IMG_BY_IDX' "${ROOT_DIR}/scripts/ref2va-yinhang-a-sglang.sh" | sed -nE 's/^  \[[0-9]+\]=.*/&/p')
for x in b c d; do
  assert_eq "$ya" "$(grep -A16 '^declare -A SEG_IMG_BY_IDX' "${ROOT_DIR}/scripts/ref2va-yinhang-$x-sglang.sh" | sed -nE 's/^  \[[0-9]+\]=.*/&/p')" "T26 A/$x 映射表逐字一致"
done
# 四个脚本的默认 IMAGE_PREFIX 必须都指向独立子目录 yhk/（xl.png 与风控版同名不同人，共用目录会串角色）
for x in a b c d; do
  ip=$(grep -oE '^IMAGE_PREFIX="\$\{IMAGE_PREFIX-[^}]+\}"' "${ROOT_DIR}/scripts/ref2va-yinhang-$x-sglang.sh")
  assert_eq 'IMAGE_PREFIX="${IMAGE_PREFIX-http://53.192.28.254:8210/images/yhk/}"' "$ip" "T26 $x 默认 IMAGE_PREFIX 为 yhk/ 子目录"
done

# ================================= T27 =================================
CASE="T27 信用卡逾期还款纠纷化解：双脚本双服务并行、合计 204s"
echo "── ${CASE}"
reset_posts; : > "$POSTS_B"
run_script ref2va-xyk-a-sglang.sh t27 OUTPUT_PREFIX="${WORK}/xyk_"
assert_eq "0" "$(rc_of t27)" "T27 A 退出码"
assert_eq "7" "$(wc -l < "$POSTS" | tr -d ' ')" "T27 A 段1-7 请求数"
assert_eq "16:9" "$(jq -r '.target.aspect_ratio' "$POSTS" | sort -u | tr '\n' ' ' | sed 's/ $//')" "T27 画幅"
assert_eq "15 15 15 15 15 15 15" "$(jq -r '.target.duration_seconds' "$POSTS" | tr '\n' ' ' | sed 's/ $//')" "T27 A 逐段时长"
assert_eq "xl.png"        "$(imgs_of 1)" "T27 段1 单图"
assert_eq "lxs.png,xl.png" "$(imgs_of 2)" "T27 段2 图序（李先生在前）"
assert_eq "xl.png,lxs.png" "$(imgs_of 4)" "T27 段4 图序（同两人换序）"
for i in 1 2 3 4 5 6 7; do assert_file "${WORK}/xyk_seg${i}.mp4" "T27 A 产出"; done

run_script ref2va-xyk-b-sglang.sh t27b OUTPUT_PREFIX="${WORK}/xyk_" PORT="${PORT_B}"
assert_eq "0" "$(rc_of t27b)" "T27 B 退出码"
assert_eq "7" "$(wc -l < "$POSTS_B" | tr -d ' ')" "T27 B 段8-14 请求数（第二服务）"
assert_eq "7" "$(wc -l < "$POSTS" | tr -d ' ')" "T27 主服务请求数未变"
assert_eq "15 15 15 15 15 15 9" "$(jq -r '.target.duration_seconds' "$POSTS_B" | tr '\n' ' ' | sed 's/ $//')" "T27 B 逐段时长（段14=9s）"
assert_eq "lxs.png,xl.png" "$(sed -n 5p "$POSTS_B" | jq -r '[.conditions[].uri|split("/")|last]|join(",")')" "T27 段12 图序"
assert_eq "lxs.png"        "$(sed -n 7p "$POSTS_B" | jq -r '[.conditions[].uri|split("/")|last]|join(",")')" "T27 段14 定帧段单图"
for i in 8 9 10 11 12 13 14; do assert_file "${WORK}/xyk_seg${i}.mp4" "T27 B 产出"; done

assert_eq "14" "$(( $(wc -l < "$POSTS") + $(wc -l < "$POSTS_B") ))" "T27 两服务合计请求数"
assert_eq "204" "$(jq -r '.target.duration_seconds' "$POSTS" "$POSTS_B" | awk '{s+=$1} END{print s}')" "T27 全片总时长"
assert_eq "14" "$(ls -1 "${WORK}"/xyk_seg*.mp4 2>/dev/null | wc -l | tr -d ' ')" "T27 seg1..14 产出齐全无覆盖"
xa=$(grep -A15 '^declare -A SEG_IMG_BY_IDX' "${ROOT_DIR}/scripts/ref2va-xyk-a-sglang.sh" | sed -nE 's/^  \[[0-9]+\]=.*/&/p')
xb=$(grep -A15 '^declare -A SEG_IMG_BY_IDX' "${ROOT_DIR}/scripts/ref2va-xyk-b-sglang.sh" | sed -nE 's/^  \[[0-9]+\]=.*/&/p')
assert_eq "$xa" "$xb" "T27 A/B 映射表逐字一致"
for x in a b; do
  ip=$(grep -oE '^IMAGE_PREFIX="\$\{IMAGE_PREFIX-[^}]+\}"' "${ROOT_DIR}/scripts/ref2va-xyk-$x-sglang.sh")
  assert_eq 'IMAGE_PREFIX="${IMAGE_PREFIX-http://53.192.28.254:8210/images/xyk/}"' "$ip" "T27 $x 默认 IMAGE_PREFIX 为 xyk/ 子目录"
done

# ------------------------------- 汇总 -------------------------------
echo "======================================================"
echo " 通过 ${PASS} 项 / 失败 ${FAIL} 项"
if [ "$FAIL" -ne 0 ]; then
  echo " 失败用例日志见：${WORK}/（KEEP_WORK=1 运行时保留）"
  echo "======================================================"
  exit 1
fi
echo "======================================================"
