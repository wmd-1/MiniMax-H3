#!/usr/bin/env bash
set -uo pipefail

# =============================================================================
# MiniMax-H3 分镜批量脚本冒烟测试
# =============================================================================
#
# 被测对象：scripts/ref2va-jiaoxintong3-sglang.sh / ref2va-jiaoxintong2-sglang.sh /
#           ref2va-jiaoxintong-sglang.sh / ref2va-story-sglang.sh / ref2va-story.sh
#
# 覆盖点：
#   1) 输出视频命名 = OUTPUT_PREFIX + 段提示词文件名 stem（不按循环序号）
#   2) 每段独立参考图，且 conditions[] 顺序 == <Picture N> 顺序
#   3) jiaoxintong2 逐段时长（13/15/12/10/12/15/8/13/6，合计 104s）与 jiaoxintong3 逐段时长
#      （15x6 + 落板10，合计 100s，画幅 16:9）
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
         first_shot.png first_shot.PNG image1.png image2.png image3.png image4.png image5.png \
         image6.png image7.png image8.png image9.png image10.png \
         image133.png image134.png image135.png image136.png; do
  : > "${WORK}/${f}"
done

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

# ------------------------------- 汇总 -------------------------------
echo "======================================================"
echo " 通过 ${PASS} 项 / 失败 ${FAIL} 项"
if [ "$FAIL" -ne 0 ]; then
  echo " 失败用例日志见：${WORK}/（KEEP_WORK=1 运行时保留）"
  echo "======================================================"
  exit 1
fi
echo "======================================================"
