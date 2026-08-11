# MiniMax-H3 Skills 详解

本目录（`./skills`）包含 MiniMax Hub / H3 生态下的一组 **创作型 Skill（技能）**。每个 Skill 是一套结构化的提示词工程工作流，用于把用户的创意意图（故事、音乐、参考图、风格约束等）转化为可直接送交视频/图像生成模型（默认 MiniMax H3）的锁定提示词、分镜脚本与成片方案。

> 说明：仓库中已有的 `skills/README.md` 为英文版总览。本文件为**中文详细解析**，补充每个 Skill 的结构、用途、核心工作流与文件组织。

---

## 1. Skill 通用结构

每个 Skill 目录通常包含以下文件：

| 文件 | 作用 |
| --- | --- |
| `SKILL.md` / `SKILL.cn.md` | 技能主说明，含 `name`、`description`（触发条件/适用场景）与分步骤工作流（STEP 1…N）。`SKILL.cn.md` 为中文版。 |
| `meta.yaml` | 元数据：中文显示名、版本号、分类标签（tag）、摘要（summary）、详细描述（desc）、作者与来源（official / official-featured / community）。 |
| `references/` | 工作流所需的模板或参考规范（如确认图模板、视频提示词模板、提示词写作指南）。 |
| `agents/` | 可选的代理定义（如 `openai.yaml`），声明技能的默认提示词与调用方式。 |

`skills-lock.json` 位于仓库根目录，记录已锁定/已安装的技能清单。

---

## 2. Skill 清单

| # | Skill 目录 | 中文名 | 分类 | 来源 |
| --- | --- | --- | --- | --- |
| 1 | `h3-prompt-writing` | H3 视频提示词写作 | 提示词工程（基础能力） | official |
| 2 | `3d-animation-short-generator` | 3D 动画短片生成器 | 动画 | community |
| 3 | `minimalist-product-ad-generator` | 极简产品广告生成器 | 广告/电商 | official-featured |
| 4 | `papercraft-stop-motion-explainer` | 纸艺定格讲解动画生成器 | 教育/动画 | official-featured |
| 5 | `brand-promo-video-generator` | 品牌宣传视频生成器 | 广告/品牌 | official-featured |
| 6 | `music-video-subtitle-generator` | 音乐 MV 动态字幕生成器 | 音频音乐 | official-featured |
| 7 | `co-op-game-intro-generator` | 双人游戏开场视频生成器 | 创意实验 | official |
| 8 | `paper-collage-explainer-generator` | 纸拼贴讲解动画生成器 | 教育/动画 | official-featured |
| 9 | `handdrawn-live-video-generator` | 手绘实拍融合视频生成器 | 创意实验/动画 | official-featured |

---

## 3. 各 Skill 详细解析

### 3.1 `h3-prompt-writing` — H3 视频提示词写作

**定位**：基础提示词工程能力，是所有视频类 Skill 的底层规范，不面向终端用户直接"生成视频"，而是把多模态请求改写为 H3 生成提示词。

**核心能力**：支持四种生成模式，统一映射到 H3 的时间线式提示词结构：

| 模式 | 含义 |
| --- | --- |
| `T2VA` | 纯文本 → 完整视听时间线 |
| `I2VA` | 文本 + 首帧图 → 从首帧向前发展 |
| `FL2VA` | 文本 + 首帧 + 尾帧 → 首末帧之间的连续路径 |
| `L2VA` | 文本 + 尾帧 → 推断开头并收敛到尾帧 |

**最终提示词结构**（两类字段）：
- 对齐指令（I2VA/FL2VA/L2VA 的首行）
- 三核心字段：`integrated_multimodal_description`（视听描述）、`overall_soundscape`（环境音/物理音）、`non_diegetic_music`（仅观众可听的背景乐）

**配套参考文档**：
- `references/base-en.txt`：T2VA/I2VA/FL2VA/L2VA 写作指南，含镜头语言（Zoom/Push/Pan/Truck/Tilt/Pedestal/Arc/Tracking/POV/Roll 等，含运动类型+幅度+速度三维度）、说话人 ID（`(S1)`/`(S2)`）、对白/歌词 `<d>[语言] ...</d>`、`<scenetrans>`/`<cutoff>` 跨切连续、屏幕文字、声景与配乐写法，并附 4 个完整示例。
- `references/ref-en.txt`：全参考（full-reference）模式改写格式，定义 6 段式输出：`subject_definitions` / `summary` / `retention_analysis` / `detailed_description` / `overall_soundscape` / `non_diegetic_music`；参考标签 `<Subject N>`、`<Picture N>`、`<Video N>`、`<Audio N>` 及保留关系标记（`fully_preserved`/`partially_preserved`/`attribute_transfer`/`weak_reference`、`fully_copy`/`partially_copy`/`reference`/`weak_reference`）。
- `agents/openai.yaml`：声明技能默认提示词 `Use $h3-prompt-writing to rewrite this multimodal request into a MiniMax H3 generation prompt.`

---

### 3.2 `3d-animation-short-generator` — 3D 动画短片生成器

**适用**：把一句故事创意变成风格统一的完整 3D 动画短片（剧情动画、生日纪念、品牌故事、社媒短片）。不适用于单图、简单修图、真人写实或单镜头。

**工作流**：项目简报与故事大纲 → 角色卡（带标签）与无人物场景卡 → 逐秒镜头表（动作/镜头/音频/连续性）→ 文本分镜或铅笔分镜 → 选视频模型 → 逐镜头生成 → 全片拼接 → BGM 匹配 → 成片复查。

**关键治理**：
- 角色一致性：锁定面部、发型、服装、比例、姿态、光感；换风格时只改渲染不改身份锚点。
- 场景连续性：尾帧接下镜首帧、同色温、匹配剪辑/同方向运动。
- 节奏控制：避免单镜头拉伸导致变形；>15s 自动多镜头拼接。
- `references/` 下提供 3D 风格库、角色/场景卡模板、镜头表模板与质量检查清单。

---

### 3.3 `minimalist-product-ad-generator` — 极简产品广告生成器

**适用**：电商/品牌产品广告。把产品图或描述变成高级极简质感广告，强调留白、产品主体、干净布光与克制运镜。

**要点**：固定"产品主体 + 大量负空间 + 统一色调 + 轻运镜"的视觉语法；分镜从产品亮相、细节、使用场景到品牌收尾；默认输出比例与节奏适配信息流投放。

---

### 3.4 `papercraft-stop-motion-explainer` — 纸艺定格讲解动画生成器

**适用**：用纸艺/手工定格语言做知识点、观点或抽象概念的讲解动画（教育、知识区、社媒 B-roll）。

**风格签名**：半调（halftone）剪纸、平涂色块、暖奶油描边、柔和纸影、手工撕边、层叠纸缝、定格装配动效 + 触感纸声（slide/pop/press/tap/rustle）。

**音频策略（默认）**：保留触感纸声效，**默认不加 BGM、不加口播/旁白、不加字幕**，三者仅作可选附加项，需用户明确确认。

**工作流**（双闸门审批）：
- Gate 1：先产出"制作方案文档"（Brief + 视觉隐喻 + 脚本/视觉节拍轨 + 分镜），等用户批准再生成任何素材。
- Gate 2：生成每个片段的静帧（最终帧锚点），确认后再做定格视频。
- 失败处理：假文字/UI、纸纹过脏、开场色与静帧冲突、丢失定格装配等均有明确回退策略。

---

### 3.5 `brand-promo-video-generator` — 品牌宣传视频生成器

**适用**：品牌叙事/宣传片。把品牌要素（定位、卖点、调性、视觉资产）转化为带情绪节奏的品牌视频。

**要点**：强调品牌一致性（色板、字标、语气）、开场钩子、价值点递进、情感收束；与 `minimalist-product-ad-generator` 的区别在于更重叙事与品牌调性，而非单品极简展示。

---

### 3.6 `music-video-subtitle-generator` — 音乐 MV 动态字幕生成器

**适用**：带歌词贴字/动态字幕的 AI MV 或情绪短片。分析节拍与人声时序，区分人物/场景/文字参考，设计随节奏变化的空间字幕，并把长作品拆成可衔接镜头。

**核心规则**：
- 预锁：画幅（9:16 / 16:9 / 1:1 / 21:9 等）、目标时长、音乐窗口、歌词归属（用户歌词锁定不可改，无歌词则先生成原创歌词再锁定）。
- >15s **强制多镜头拼接**：锁定一条全局 Master Audio；把 30s 拆成 4–8 个 2–5s 镜头；尾帧接首帧、节拍硬切、对齐全局音频网格。
- 五重连续性锁：人声口型、节奏节拍、色调分级、转场运动、字幕动效衔接。
- 字幕是"空间设计层"而非普通字幕条，绝不遮挡眼睛/主要表情；编辑严格硬切、无淡入淡出。
- 最终提示词写入 Canvas 文本节点 `完整MV Prompt`，后续修订更新同一节点。

---

### 3.7 `co-op-game-intro-generator` — 双人游戏开场视频生成器

**适用**：双人合作游戏主菜单/开场动画。不适用于可玩游戏开发、复杂多页 UI、精确品牌标识复刻。

**工作流**（先确认图再出视频）：
- STEP 1 选预设视觉风格（最高优先级，控制配色/UI/角色渲染/字体）。
- STEP 2 收集 PLAYER 1 / PLAYER 2 名称、游戏名、可选角色参考图（仅用于身份锚点，重绘进所选风格）。
- STEP 3 按 `references/h3-confirmation-image-template.md` 构建"确认首图"提示词（固定菜单框架 + 动态风格填充 + 配色联动：主色/UI 色/文字色/功能色，五色内）。
- STEP 4 生成唯一一张确认首图；STEP 5 等用户批准；STEP 6 按 `references/h3-video-prompt-template.md` 回填最终视频提示词并用 MiniMax H3 生成。
- 失败修复：文字不可读→删屏上文字；身份互换→强化姓名/位置/颜色；脸漂移→复用参考图并保留身份锚点。

**模板文件**：
- `references/h3-confirmation-image-template.md`：固定菜单框架（16:9、居中双人、左上玩家卡、右侧竖菜单、底部警示条、Z 型阅读路径、Continue 为视觉焦点）。
- `references/h3-video-prompt-template.md`：最终视频提示词骨架（风格/角色/UI 文案/事件节奏/运动方向/负向约束）。

---

### 3.8 `paper-collage-explainer-generator` — 纸拼贴讲解动画生成器

**适用**：与 `papercraft-stop-motion-explainer` 同属"纸感讲解"家族，但视觉语言为**编辑风半调纸拼贴**（flat bold color field + 黑白半调照片剪贴 + 局部彩色卡纸点缀 + 暖奶油描边）。

**要点**：
- STEP 1 解析输入的"核心含义/情绪/动作动词/视觉隐喻/关键对象/音频暗示"。
- Gate 1 制作方案（含视觉隐喻、脚本/视觉节拍轨、分镜），Gate 2 生成静帧（最终帧锚点）。
- STEP 5 定格装配顺序：干净色场 → 基础结构滑入/弹入 → 主隐喻元素入场 → 次对象逐个装配（轻弹/压平/停顿）→ 锁定 → 末尾定格。
- 色彩语义：赭橙/红=紧迫、芥黄=警示、墨绿=认知/重置、深紫=记忆/神秘、青=协作、玫红=荒诞/仪式。
- 同样默认保留拼贴 SFX，不加 BGM/口播/字幕（除非明确请求）。

---

### 3.9 `handdrawn-live-video-generator` — 手绘实拍融合视频生成器

**适用**：单场景创意短片——粗糙发光手绘动画与实拍空间融合。不适用于精致 CG、恐怖跳吓、毛绒角色、多场景剪辑。

**强制影像结构**（15 秒 / 16:9）：
1. 0–3s：实拍手与手绘动画**清晰接触**（缠指、落掌心、被抓逃、指尖诞生）。
2. 3–6s / 6–10s / 10–13s：同一实体**连续变形**（保留前一形态痕迹），拍摄者参与（伸手/抓/追/开门/接住/被恶作剧）。
3. 13–15s：**空间级变形**（线扩散到墙/地/天花/窗，变巨花/星空/夕阳/丝带/涂鸦小镇）+ 感动余韵 + 可爱笑点。
4. 相机**总是慢半拍**：实体已出画才跟随摇/移/推进；不居中。
5. 手绘质感：蜡笔/粉笔/彩铅/粉彩/粗糙笔刷，线条轻抖、毛边、逐帧重画感。
6. 禁止：3D CG、毛绒感、均匀矢量线、平滑霓虹、恐怖怪物、巨眼、裂口、牙齿、威吓、跳吓、突然黑屏。

**语言规则**：最终提示词用用户输入的**主导语言**输出（中文输入→中文，日文→日文），仅专有名词/模型名/字面参数保留原文；先输出提示词，再附一句同语言"建议用 H3 生成"的推荐，**用户确认前不生成视频**。

---

## 4. 横向规律（Skill 设计范式）

1. **确认闸门（Gate）**：多数成片类 Skill 在生成前设置方案/首图审批节点（如 3D、纸艺、纸拼贴、双人游戏），避免一次性生成跑偏。
2. **参考图角色隔离**：人物卡 / 场景卡 / 文字（字幕/UI）卡分离，避免跨污染（音乐 MV、双人游戏尤为严格）。
3. **多镜头拼接协议**：>15s 时统一采用"锁定全局音频 + 尾帧接首帧 + 节拍硬切 + 五重连续性锁"。
4. **默认音频策略克制**：纸艺/纸拼贴默认仅保留触感音效，BGM/口播/字幕须显式确认。
5. **Hub 兼容**：写锁定提示词到画布文本节点，媒体生成委托给 Hub 的 image/video/music/editing 代理，不硬编码输出路径。
6. **底层规范统一**：所有视频类 Skill 的提示词最终都映射到 `h3-prompt-writing` 的 T2VA/I2VA/FL2VA/L2VA 与全参考模式结构。

---

## 5. 快速索引（按用途选 Skill）

| 需求 | 选用 Skill |
| --- | --- |
| 改写/审计任意多模态请求为 H3 提示词 | `h3-prompt-writing` |
| 故事 → 完整 3D 动画短片 | `3d-animation-short-generator` |
| 产品图 → 极简电商广告 | `minimalist-product-ad-generator` |
| 品牌 → 叙事宣传片 | `brand-promo-video-generator` |
| 知识点/观点 → 纸艺定格讲解 | `papercraft-stop-motion-explainer` |
| 文案/概念 → 纸拼贴讲解 | `papercollage-explainer-generator` |
| 音乐/歌词 → 卡点 MV + 动态字幕 | `music-video-subtitle-generator` |
| 双人游戏 → 菜单开场动画 | `co-op-game-intro-generator` |
| 场景创意 → 手绘×实拍融合短片 | `handdrawn-live-video-generator` |
</content>
<parameter name="explanation">在根目录编写详细中文 README，解析 skills 目录下所有 skill 的结构、用途与工作流。