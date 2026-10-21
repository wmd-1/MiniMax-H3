# 对公营销情报官｜15s 分段视频生成脚本（Ref2VA 全参考模式）

## 一、全局设定

- **模式**：Ref2VA 全参考（`reference generation`），角色形象图仅作角色一致性参考，不作首/尾帧。
- **每段时长**：15.00s｜**段数**：14 段｜**总时长**：3'30"
- **语速基准**：中文约 4.2–4.5 字/秒（偏舒适，不赶），长句内部用气口切分，不加速吞字。
- **1s 空白画面**：原剧本共 6 处，分别落在第 3 段尾、第 6 段头/尾、第 8 段头、第 10 段中、第 13 段头。
- **占位符**：`XX旅游文化发展有限公司` 为原剧本占位名，若后续替换为真实企业名，全局替换即可，段内时序不变。

### 编号规则（每段独立重编）

因为 14 段是分别生成、各自独立的目标视频，**每段的 `<Subject>` / `<Picture>` / `(Sx)` 都从 1 开始重新编号**，不复用上一段的编号。

1. **`<Subject 1>` / `<Picture 1>` 恒为小王（xw.png）**。小王 14 段全部出镜，把他锚定为 1 号，每段固定第一个上传 xw.png，可杜绝上传顺序错位。
2. 其余角色按**该段出场先后**依次编号：同场出现同事则为 `<Subject 2>`，情报官顺延为 `<Subject 3>`；只有情报官出场的段落，情报官就是 `<Subject 2>`。
3. `<Picture N>` 与 `<Subject N>` **一一对应**（Subject K ← Picture K），上传顺序即编号顺序。
4. `(Sx)` 按**该段内实际发声先后**重新分配：谁先开口谁是 `S1`，不说话的角色不给编号。因此同一角色在不同段落的 `Sx` 可能不同，这是正确的——每段是独立生成，音色由台词外的文字描述（性别、年龄感、音色、语速）锁定，不依赖编号跨段继承。

### 每段上传顺序速查

| 段 | 上传顺序 | 编号 | 本段发声 |
|---|---|---|---|
| 1 | xw → ts | 小王=1、同事=2 | S1=小王 |
| 2 | xw → ts → qbg | 小王=1、同事=2、情报官=3 | S1=同事 |
| 3–14（除 1、2 段） | xw → qbg | 小王=1、情报官=2 | 见各段标注 |

## 二、段落总览

| 段 | 覆盖剧情 | 核心台词 / 字幕 | 本段发声 |
|---|---|---|---|
| 1 | 第一幕（前） | 小王独白「入职三个月了…」｜字幕：新员工拓客难？ | S1 小王 |
| 2 | 第一幕（后）+ 第二幕（起） | 同事「浙江刚出了旅游业新政策…」+ 小王打字提问 | S1 同事 |
| 3 | 第二幕（答） | 情报官答政策｜字幕：①政府政策加持 ②行内配套政策｜+1s 空白 | S1 情报官 |
| 4 | 第三幕（前） | 打字筛客 + 情报官答「10 家适配 / 5 家 A 级 / XX 公司 82 分」 | S1 情报官 |
| 5 | 第三幕（后）+ 第四幕（起） | 小王「太好了！就选定…」｜字幕：10 家线索・5 家 A 级｜+1s 空白 + 坐直「拜访前…」 | S1 小王 |
| 6 | 第四幕（答） | 打字生成研报 + 情报官答｜字幕：行业大盘心中有数｜+1s 空白 ×2（头尾） | S1 情报官 |
| 7 | 第五幕 | 小王「再帮我生成目标企业的访前一页纸！」+ 情报官答｜字幕：访前一页纸・知己知彼 | S1 小王、S2 情报官 |
| 8 | 第六幕（起） | +1s 空白 + 场景切换 + 小王自问「不少已经合作的存量客户…」 | S1 小王 |
| 9 | 第六幕（中） | 打字「帮我挖掘聊天线索。」+ 情报官答（10s） | S1 情报官 |
| 10 | 第六幕（收）+ 第七幕（起） | 小王「原来客户还有这么多潜在需求…」｜字幕：解析聊天记录…｜+1s 空白 + 走访归来犯难 | S1 小王 |
| 11 | 第七幕（中） | 小王「刚结束客户走访…」+ 拖拽上传全部录音 | S1 小王 |
| 12 | 第七幕（答） | 情报官答录音解析（9.5s）+ 小王「这下拜访材料整理归档省心多了！」+ 存档 | S1 情报官、S2 小王 |
| 13 | 第八幕（前） | +1s 空白 + 合上电脑 + 小王口诀（9s） | S1 小王 |
| 14 | 第八幕（收） | 情报官口诀收尾 + **定帧**「对公营销情报官・精准服务客户」 | S1 情报官 |

---

## 第 1 段（00:00–00:15）｜新人困境·开场

> **本段参考**：`<Picture 1>` = xw.png（小王）｜`<Picture 2>` = ts.png（同事）
> **本段发声**：`S1` = 小王（`<Subject 1>`）；同事本段无台词

```text
subject_definitions:
<Subject 1> is 小王, the newly hired corporate banking relationship manager taken from <Picture 1> (xw.png); his face, hair, build, and outfit follow <Picture 1> exactly, with no added or altered features.
<Subject 2> is 同事, the senior corporate banking relationship manager taken from <Picture 2> (ts.png); his face, hair, build, and outfit follow <Picture 2> exactly, with no added or altered features.

summary:
[reference generation] The target video is the opening beat of a live-action corporate workplace explainer set in a Wenzhou bank branch office. <Subject 1> sits at his desk stuck on how to find new corporate clients, and <Subject 2> walks past and rests a hand on his shoulder. Both characters keep their identity and outfit consistent with <Picture 1> and <Picture 2> in every shot.

retention_analysis:
<Subject 1> (appears in [Shot 1], [Shot 2]): fully_preserved - identity, face, hair, build, and outfit come from <Picture 1> unchanged; only posture, expression, and camera position change.
<Subject 2> (appears in [Shot 2]): fully_preserved - identity, build, and outfit come from <Picture 2> unchanged; only his entrance path and the hand-on-shoulder action are added.

detailed_description:
The target video is a live-action corporate explainer with bright, clean daylight, a light blue-and-white palette, crisp contrast, and shallow depth of field. The location is a modern bank branch office in Wenzhou: a floor-to-ceiling window on the left, grey-white desks, dual monitors on each desk, and a glass partition with empty desks receding to the right rear.
[Shot 1] A medium-wide shot frames <Subject 1> seated at his desk in three-quarter profile, shoulders slumped, staring at a spreadsheet on his laptop with a second monitor beside it. His appearance, hair, and outfit match <Picture 1> exactly. The camera pushes in with small amplitude at slow speed. At 00:01.500 he lifts his right hand and scratches the back of his head twice, lets the hand fall onto the desk, and exhales a long audible sigh. At 00:03.000 <Subject 1> (S1) says in a tired, slightly deflated young male voice at a natural conversational pace, <d>[Chinese] 入职三个月了，师傅让我独立拓客，可温州这么多企业，从哪儿下手啊？</d> He finishes with his brow furrowed and his lips pressed together, then taps the desk once with his index finger.
[Shot 2] At 00:10.200, the shot cuts to a slightly wider two-shot from behind his chair as <Subject 2>, whose appearance and outfit match <Picture 2> exactly, walks in from the right along the glass partition carrying a folder and stops behind <Subject 1>'s chair. At 00:11.000 a subtitle appears across the lower third in clean white type with a short red accent bar: "新员工拓客难？方向比努力更重要". At 00:13.500 <Subject 2> sets his right hand on <Subject 1>'s shoulder and gives it two light pats; <Subject 1> turns his head up toward him with a puzzled look and the shot ends on that beat.

overall_soundscape:
Quiet open-plan office room tone with a distant air-conditioning hum runs throughout. Keyboard clatter and a mouse click are heard in the opening beat, followed by the creak of a chair, a long tired sigh, and slow footsteps approaching on the hard floor before a soft fabric shift as a hand lands on a shoulder.

non_diegetic_music:
A light electronic pulse at a moderate tempo with a repeating plucked-synth arpeggio; a soft shaker and muted kick enter at 00:10.200 and continue to the final frame.
```

---

## 第 2 段（00:15–00:30）｜同事点醒 + 打开情报官

> **本段参考**：`<Picture 1>` = xw.png（小王）｜`<Picture 2>` = ts.png（同事）｜`<Picture 3>` = qbg.png（对公营销情报官）
> **本段发声**：`S1` = 同事（`<Subject 2>`）；小王本段无台词

```text
subject_definitions:
<Subject 1> is 小王, the newly hired corporate banking relationship manager taken from <Picture 1> (xw.png); his face, hair, build, and outfit follow <Picture 1> exactly.
<Subject 2> is 同事, the senior corporate banking relationship manager taken from <Picture 2> (ts.png); his face, hair, build, and outfit follow <Picture 2> exactly.
<Subject 3> is 对公营销情报官, the bank's in-house AI agent taken from <Picture 3> (qbg.png), appearing as the assistant avatar inside the "对公营销情报官" chat panel on the laptop screen; its look follows <Picture 3> exactly.

summary:
[reference generation] The target video continues the office scene: <Subject 2> leans down and points <Subject 1> toward the new Zhejiang tourism policy, then <Subject 1> turns to his laptop, opens the <Subject 3> chat panel, and types his first question. All three references keep their identity and outfit consistent with <Picture 1>, <Picture 2>, and <Picture 3>.

retention_analysis:
<Subject 1> (appears in [Shot 1], [Shot 2], [Shot 3], [Shot 4]): fully_preserved - identity and outfit from <Picture 1> are unchanged; expression shifts from puzzled to alert.
<Subject 2> (appears in [Shot 1]): fully_preserved - identity and outfit from <Picture 2> are unchanged; only his leaning posture is added.
<Subject 3> (appears in [Shot 3], [Shot 4]): fully_preserved - the assistant's look from <Picture 3> is reproduced as the avatar inside the chat panel without redrawing its features.

detailed_description:
The target video keeps the same bright corporate-explainer look, daylight office, light blue-and-white palette, and shallow depth of field.
[Shot 1] An over-the-shoulder two-shot holds <Subject 1> seated at his desk in the lower left and <Subject 2>, with his appearance and outfit matching <Picture 2> exactly, standing behind the chair on the right. <Subject 2> (S1) leans down slightly, taps the desk edge with two fingers, and says in a warm, steady mature male voice at an easy pace, <d>[Chinese] 小王，浙江刚出了旅游业新政策，你从政策里找找机会啊！</d> He straightens up and gestures once toward the laptop screen with his chin.
[Shot 2] At 00:05.500, the shot cuts to a close-up of <Subject 1>, whose face matches <Picture 1> exactly. His eyes widen as the idea lands; he blinks twice, his mouth opens slightly, and he turns his head sharply toward the laptop on the right.
[Shot 3] At 00:07.500, the shot cuts to an over-shoulder view of the laptop as <Subject 1> wakes the screen with a key press and clicks open the "对公营销情报官" panel: a white chat card with a blue header, the <Subject 3> avatar at the left of the message area, and a text input box along the bottom. The camera pushes in with small amplitude at slow speed as the panel finishes rendering at 00:09.200.
[Shot 4] At 00:10.000, the shot cuts to a close-up of the laptop screen. The cursor blinks in the input box and <Subject 1>'s typed characters appear one after another, forming "浙江旅游业最新贴息政策有哪些？" by 00:13.200. His right index finger presses Enter at 00:13.500; the input box clears and three loading dots begin to pulse beside the <Subject 3> avatar, which brightens as the reply bubble starts to form in the last instant of the shot.

overall_soundscape:
Office room tone continues underneath. A fingertip taps a desk edge, fabric shifts as someone stands upright, then a keyboard wakes with a short key click, a mouse button clicks, and rapid keyboard taps fill the second half of the shot sequence, ending with a soft Enter press and a single low interface blip.

non_diegetic_music:
The same light electronic pulse and plucked-synth arpeggio continue at a moderate tempo, with a quiet rising filter sweep from 00:07.500 to 00:10.000 and a thin high shimmer that enters with the chat panel and sustains to the end.
```

---

## 第 3 段（00:30–00:45）｜政策答案（含 1s 空白）

> **本段参考**：`<Picture 1>` = xw.png（小王）｜`<Picture 2>` = qbg.png（对公营销情报官）
> **本段发声**：`S1` = 情报官（`<Subject 2>`）；小王本段无台词（仅阅读反应）

```text
subject_definitions:
<Subject 1> is 小王, the newly hired corporate banking relationship manager taken from <Picture 1> (xw.png); his face, hair, build, and outfit follow <Picture 1> exactly.
<Subject 2> is 对公营销情报官, the bank's in-house AI agent taken from <Picture 2> (qbg.png), appearing as the assistant avatar inside the "对公营销情报官" chat panel on the laptop screen; its look follows <Picture 2> exactly.

summary:
[reference generation] The target video shows the <Subject 2> chat panel answering <Subject 1>'s policy question, with the two policy lines echoed as on-screen subtitles, and ends on a one-second blank frame. The agent's look stays consistent with <Picture 2> and the user's identity stays consistent with <Picture 1>.

retention_analysis:
<Subject 2> (appears in [Shot 1], [Shot 2]): fully_preserved - the assistant's look from <Picture 2> is kept unchanged in the chat panel while the reply bubble expands.
<Subject 1> (appears in [Shot 3]): fully_preserved - identity and outfit from <Picture 1> are unchanged; only his reading expression and the screen light on his face are added.

detailed_description:
The target video keeps the bright, clean corporate-explainer look, with cool screen light dominating the frame and daylight from the window behind.
[Shot 1] A medium close-up frames the laptop screen straight on. The "对公营销情报官" reply bubble expands under the <Subject 2> avatar, and the camera holds a static shot with a very slow push in of small amplitude. At 00:00.800 the first reply line finishes streaming in and the agent's voice begins.
[Shot 2] <Subject 2> (S1) speaks in a clear, evenly paced synthetic assistant voice, calm and unhurried, with clean articulation: <d>[Chinese] 浙江省出台《推动旅游业经济高质量发展若干政策》，力推文旅消费；我行同步发布《支持文旅消费行动方案》，配套行内专属产品！</d> While the line plays, the words stay highlighted line by line in the bubble, and at 00:03.000 two subtitle lines fade in across the lower third in white type: "①政府政策加持" on the first line and "②行内配套政策" on the second. The camera trucks right with small amplitude at slow speed to keep the last reply line and the two subtitles in frame.
[Shot 3] At 00:08.000, the shot cuts to a close-up of <Subject 1>, whose face matches <Picture 1> exactly, seen in three-quarter profile with the laptop glow on his cheek and the window daylight on his opposite side. His lips stay closed and his eyes track left to right as he reads; he gives one small nod at 00:11.500, and the agent's voice continues seamlessly across the cut without a break in delivery.
[Shot 4] At 00:14.000, the shot cuts to a completely blank white frame that holds motionless and silent for the final second of the video.

overall_soundscape:
A faint laptop fan and low office room tone sit underneath the whole segment. A soft keyboard tick and one short notification blip are heard in the first half second; a quiet chair shift and a single soft breath accompany the cut to <Subject 1>.

non_diegetic_music:
A sparse plucked-synth figure at a moderate tempo with a sustained warm pad underneath, holding a steady level through the reply and dropping out abruptly at 00:14.000 so the blank frame plays in silence.
```

---

## 第 4 段（00:45–01:00）｜筛客问句 + 十条线索（连续播报）

> **本段参考**：`<Picture 1>` = xw.png（小王）｜`<Picture 2>` = qbg.png（对公营销情报官）
> **本段发声**：`S1` = 情报官（`<Subject 2>`）；小王本段仅打字，无台词

```text
subject_definitions:
<Subject 1> is 小王, the newly hired corporate banking relationship manager taken from <Picture 1> (xw.png); his face, hair, build, and outfit follow <Picture 1> exactly.
<Subject 2> is 对公营销情报官, the bank's in-house AI agent taken from <Picture 2> (qbg.png), appearing as the assistant avatar inside the "对公营销情报官" chat panel on the laptop screen; its look follows <Picture 2> exactly.

summary:
[reference generation] The target video shows <Subject 1> typing a second screening question and the <Subject 2> panel answering in one continuous read-out, cutting from the chat bubble to a ranked result table of ten companies. The agent's look stays consistent with <Picture 2> and the user's identity stays consistent with <Picture 1>.

retention_analysis:
<Subject 1> (appears in [Shot 1], [Shot 3]): fully_preserved - identity and outfit from <Picture 1> are unchanged; only his hands, posture, and concentration are added.
<Subject 2> (appears in [Shot 2]): fully_preserved - the assistant's look from <Picture 2> is kept unchanged inside the chat header and beside the reply bubble.

detailed_description:
The target video keeps the bright corporate-explainer look. Screen content is shot straight on with shallow depth of field, and every interface element stays crisp and legible.
[Shot 1] A close-up of the laptop screen holds the "对公营销情报官" input box with the chat history scrolled up above it. <Subject 1>'s hands enter from the bottom of the frame, and the typed characters appear quickly and evenly, forming "浙江省温州市符合上述政策的旅游业企业有哪些？" by 00:01.500; he presses Enter at 00:01.800 and the bubble posts.
[Shot 2] At 00:01.800, the shot cuts to a medium close-up of the screen with the <Subject 2> avatar at the left of the reply area, its look matching <Picture 2> exactly, and the reply bubble streaming out. <Subject 2> (S1) continues in the same clear, evenly paced synthetic assistant voice: <d>[Chinese] 共筛选10家适配企业，其中A级高价值客户5家！</d> The camera pushes in with small amplitude at slow speed; the numerals "10" and "5" scale up briefly inside the bubble as they are spoken.
[Shot 3] At 00:06.800, the shot cuts to an over-shoulder view of the screen as the result table slides up from the bottom: ten rows with company names on the left, region and industry tags in the middle, and score bars on the right. The bars fill one after another from 00:07.000 to 00:09.500, and <Subject 2> (S1) continues across the cut without interruption: <d>[Chinese] 温州市XX旅游文化发展有限公司，82分，洞头区文旅国企平台，政策匹配度最高！</d> At 00:10.500 the top row's score bar reaches 82 and the row expands into a highlight card with a thin blue border; at 00:12.000 the camera trucks down with small amplitude at slow speed to follow the highlight card settling at the top of the list, and <Subject 1>'s index finger enters from the lower right and rests on that row. The shot holds on the highlighted row with the cursor blinking beside it until the end of the segment.

overall_soundscape:
Office room tone and a faint laptop fan continue underneath. Fast keyboard taps and one Enter press open the segment, followed by a soft message-post blip, a light interface ticking sound as the score bars fill, and a short two-note chime when the highlight card settles. A fingertip taps the screen edge once in the final second.

non_diegetic_music:
A steady plucked-synth ostinato at a moderate tempo with a light shaker pulse; a soft low string note enters at 00:06.800 and holds under the table animation, rising slightly in volume at 00:10.500 and staying level to the end.
```

---

## 第 5 段（00:60–01:15）｜锁定目标 + 坐直备战（含 1s 空白）

> **本段参考**：`<Picture 1>` = xw.png（小王）｜`<Picture 2>` = qbg.png（对公营销情报官）
> **本段发声**：`S1` = 小王（`<Subject 1>`）；情报官本段无台词

```text
subject_definitions:
<Subject 1> is 小王, the newly hired corporate banking relationship manager taken from <Picture 1> (xw.png); his face, hair, build, and outfit follow <Picture 1> exactly.
<Subject 2> is 对公营销情报官, the bank's in-house AI agent taken from <Picture 2> (qbg.png), appearing as the assistant avatar inside the "对公营销情报官" chat panel on the laptop screen; its look follows <Picture 2> exactly.

summary:
[reference generation] The target video shows <Subject 1> leaning toward the screen and excitedly locking in the target company, followed by a one-second blank frame, then cutting to him sitting up straight and committing to preparing for the visit. His identity stays consistent with <Picture 1> and the agent's look stays consistent with <Picture 2>.

retention_analysis:
<Subject 1> (appears in [Shot 1], [Shot 3]): fully_preserved - identity and outfit from <Picture 1> are unchanged; only his forward lean, excited expression, and straightened posture are added.
<Subject 2> (appears in [Shot 1]): fully_preserved - the assistant's look from <Picture 2> is retained in the chat panel visible over his shoulder.

detailed_description:
The target video keeps the bright corporate-explainer look, with warm daylight on one side of the subject and cool screen light on the other.
[Shot 1] A medium close-up frames <Subject 1>, whose face and outfit match <Picture 1> exactly, with the laptop screen occupying the lower left of the frame and the <Subject 2> avatar visible in the chat header. At 00:00.200 he leans forward toward the screen, his shoulders rising, and at 00:00.500 <Subject 1> (S1) says in a bright, rising young male voice at an energetic but clear pace, <d>[Chinese] 太好了！就选定XX旅游文化发展有限公司作为目标客户。</d> His right hand closes into a small fist on the desk edge on the last phrase. At 00:06.000 a subtitle fades in across the lower third in white type with a short red accent bar: "10 家线索・5 家 A 级・精准锁定"; he holds the excited expression and glances back and forth between the subtitle area and the highlighted row on screen until 00:08.500.
[Shot 2] At 00:08.500, the shot cuts to a completely blank white frame that holds motionless and silent for one second.
[Shot 3] At 00:09.500, the shot cuts to a medium wide shot from the side of the desk: <Subject 1> pulls his chair in, sits up straight, squares his shoulders, and straightens a stack of papers with both hands at 00:10.500. Then <Subject 1> (S1) says in a firm, focused voice with a deliberate pace, <d>[Chinese] 拜访前，我得先把行业情况摸透！</d> He turns back to the keyboard, and in the final half second his hands settle onto the keys ready to type.

overall_soundscape:
Office room tone continues underneath. A chair cushion compresses and a hand taps the desk edge, a fabric shift follows as he straightens up, papers rustle briefly under his palms, and a light chair roll on the hard floor closes the segment. A single soft breath is audible after the line in [Shot 3].

non_diegetic_music:
A plucked-synth ostinato at a moderate tempo with a light kick and shaker; the pattern cuts out at 00:08.500 for the blank frame, restarts with a brighter tone at 00:09.500, and holds level to the final frame.
```

---

## 第 6 段（01:15–01:30）｜研报一页纸（首尾各 1s 空白）

> **本段参考**：`<Picture 1>` = xw.png（小王）｜`<Picture 2>` = qbg.png（对公营销情报官）
> **本段发声**：`S1` = 情报官（`<Subject 2>`）；小王本段无台词

```text
subject_definitions:
<Subject 1> is 小王, the newly hired corporate banking relationship manager taken from <Picture 1> (xw.png); his face, hair, build, and outfit follow <Picture 1> exactly.
<Subject 2> is 对公营销情报官, the bank's in-house AI agent taken from <Picture 2> (qbg.png), appearing as the assistant avatar inside the "对公营销情报官" chat panel on the laptop screen; its look follows <Picture 2> exactly.

summary:
[reference generation] The target video opens on a one-second blank frame, then shows <Subject 1> typing a report request and the <Subject 2> panel generating a one-page industry brief, closing on a subtitle and a second blank frame. His identity stays consistent with <Picture 1> and the agent's look stays consistent with <Picture 2>.

retention_analysis:
<Subject 1> (appears in [Shot 3], [Shot 5]): fully_preserved - identity and outfit from <Picture 1> are unchanged; only his typing action and his reading of the printed sheet are added.
<Subject 2> (appears in [Shot 2]): fully_preserved - the assistant's look from <Picture 2> is retained in the chat panel and the generated document header.

detailed_description:
The target video keeps the bright corporate-explainer look, with the desk lit by daylight from the left and the screen glow from the front.
[Shot 1] The video opens on a completely blank white frame that holds motionless and silent for one second.
[Shot 2] At 00:01.000, the shot cuts to a close-up of the laptop screen. The cursor sits in the "对公营销情报官" input box and the typed characters appear quickly and evenly, forming "生成浙江省旅游业行业研报一页纸。" by 00:02.300; Enter is pressed at 00:02.500 and the reply bubble posts immediately. The <Subject 2> avatar, matching <Picture 2> exactly, brightens as the bubble streams out, and <Subject 2> (S1) says in the same clear, evenly paced synthetic assistant voice: <d>[Chinese] 已生成！行业背景、产业链、头部企业、行业前景一把摸透！</d> At 00:06.800 the reply bubble collapses into a document card that opens into a one-page brief titled "浙江省旅游业行业研报一页纸", with four labelled blocks filling the page from top to bottom; the camera pushes in with small amplitude at slow speed to follow the page rendering.
[Shot 3] At 00:08.000, the shot cuts to a medium shot of the desk from the front as <Subject 1>, whose face and outfit match <Picture 1> exactly, leans in and scans the page on screen, his eyes moving down the four blocks and his chin lifting slightly at 00:10.500. At 00:09.000 a subtitle fades in across the lower third in white type with a short red accent bar: "行业大盘心中有数" and holds to 00:11.000.
[Shot 4] At 00:11.000, the shot cuts to a completely blank white frame that holds motionless and silent for one second.
[Shot 5] At 00:12.000, the shot cuts to a medium close-up of <Subject 1> as he lifts a freshly printed sheet from the desk with both hands, holds it upright at chest height, and reads down the page with small nods at 00:13.200 and 00:14.300, his expression settling into quiet confidence as the segment ends.

overall_soundscape:
Office room tone continues underneath. Fast keyboard taps and an Enter press open the second shot, followed by a message-post blip, a soft page-render ticking sound, and a brief printer whirr at 00:11.600 just before the printed sheet is picked up. Paper slides against a desk and rustles twice as it is lifted and read.

non_diegetic_music:
A plucked-synth ostinato at a moderate tempo with a light shaker; the pattern drops out for both blank frames and re-enters each time with a soft muted kick, holding level to the end.
```

---

## 第 7 段（01:30–01:45）｜访前一页纸

> **本段参考**：`<Picture 1>` = xw.png（小王）｜`<Picture 2>` = qbg.png（对公营销情报官）
> **本段发声**：`S1` = 小王（`<Subject 1>`）→ `S2` = 情报官（`<Subject 2>`）

```text
subject_definitions:
<Subject 1> is 小王, the newly hired corporate banking relationship manager taken from <Picture 1> (xw.png); his face, hair, build, and outfit follow <Picture 1> exactly.
<Subject 2> is 对公营销情报官, the bank's in-house AI agent taken from <Picture 2> (qbg.png), appearing as the assistant avatar inside the "对公营销情报官" chat panel on the laptop screen; its look follows <Picture 2> exactly.

summary:
[reference generation] The target video shows <Subject 1> flipping through the industry brief with growing confidence, then asking the <Subject 2> panel for a one-page target-company brief and receiving a fully structured document. His identity stays consistent with <Picture 1> and the agent's look stays consistent with <Picture 2>.

retention_analysis:
<Subject 1> (appears in [Shot 1], [Shot 2], [Shot 3]): fully_preserved - identity and outfit from <Picture 1> are unchanged; only his reading, speaking, and typing actions are added.
<Subject 2> (appears in [Shot 2], [Shot 3]): fully_preserved - the assistant's look from <Picture 2> is retained in the chat panel and on the generated document.

detailed_description:
The target video keeps the bright corporate-explainer look, with daylight from the window on the left and a soft screen glow on the subject's face.
[Shot 1] A medium close-up frames <Subject 1>, whose face and outfit match <Picture 1> exactly, holding the printed industry brief in his left hand and turning it slightly toward the light. He reads down the page and nods twice, at 00:00.400 and 00:00.900. The camera pushes in with small amplitude at slow speed. At 00:01.000 <Subject 1> (S1) says in a confident, quickened but still clear young male voice, <d>[Chinese] 再帮我生成目标企业的访前一页纸！</d> while his right hand comes down onto the keyboard and begins typing in the final second of the line.
[Shot 2] At 00:05.000, the shot cuts to a close-up of the laptop screen: the input box shows "再帮我生成目标企业的访前一页纸！" and Enter is pressed at 00:05.600. The reply bubble posts under the <Subject 2> avatar, whose look matches <Picture 2> exactly, and <Subject 2> (S2) says in a clear, evenly paced synthetic assistant voice: <d>[Chinese] 一页纸已生成！企业画像、营销线索、营销话术、推荐产品全部理清！</d> As the line plays, the bubble resolves into a document card titled "目标企业访前一页纸" with four labelled panels filling in one after another: 企业画像, 营销线索, 营销话术, 推荐产品. The camera trucks down with small amplitude at slow speed to keep pace with the panels filling.
[Shot 3] At 00:13.500, the shot cuts to a medium close-up from the front as <Subject 1> looks up at the completed page on screen, his eyes brightening; a subtitle fades in across the lower third in white type with a short red accent bar: "访前一页纸・知己知彼" and holds to the final frame while he leans back slightly with a satisfied exhale.

overall_soundscape:
Office room tone continues underneath. Paper turns softly against a hand, a fingertip taps a keyboard, and a keyboard types rapidly in the final second of the first shot, followed by an Enter press and a message-post blip. A soft interface ticking sound accompanies the four panels filling in, and a light chair creak closes the segment.

non_diegetic_music:
A plucked-synth ostinato at a moderate tempo with a light shaker and muted kick; the pattern thins to a single sustained synth note from 00:05.000 and returns to full rhythm at 00:13.500, holding to the end.
```

---

## 第 8 段（01:45–02:00）｜聊天记录挖掘·场景切换（含 1s 空白）

> **本段参考**：`<Picture 1>` = xw.png（小王）｜`<Picture 2>` = qbg.png（对公营销情报官）
> **本段发声**：`S1` = 小王（`<Subject 1>`）；情报官本段无台词

```text
subject_definitions:
<Subject 1> is 小王, the newly hired corporate banking relationship manager taken from <Picture 1> (xw.png); his face, hair, build, and outfit follow <Picture 1> exactly.
<Subject 2> is 对公营销情报官, the bank's in-house AI agent taken from <Picture 2> (qbg.png), appearing as the assistant avatar inside the "对公营销情报官" chat panel on the laptop screen; its look follows <Picture 2> exactly.

summary:
[reference generation] After a one-second blank frame, the target video jumps forward in time to the same desk and shows <Subject 1> reading a WeCom Business chat window, realizing that existing clients still hold untapped needs, and preparing to upload the chat history to the <Subject 2> panel. His identity stays consistent with <Picture 1> and the agent's look stays consistent with <Picture 2>.

retention_analysis:
<Subject 1> (appears in [Shot 2], [Shot 3], [Shot 4]): fully_preserved - identity and outfit from <Picture 1> are unchanged; only the later time of day, his self-talk, and his computer actions are added.
<Subject 2> (appears in [Shot 4]): fully_preserved - the assistant's look from <Picture 2> is retained in the chat panel opened beside the chat window.

detailed_description:
The target video keeps the bright corporate-explainer look, but the daylight is now warmer and lower, and a thin stack of client files sits at the corner of the desk to signal that time has passed.
[Shot 1] The video opens on a completely blank white frame that holds motionless and silent for one second.
[Shot 2] At 00:01.000, the shot cuts to a medium wide shot of the same desk from a slightly different angle: <Subject 1>, whose face and outfit match <Picture 1> exactly, sits with an enterprise chat window filling most of the laptop screen, a conversation list down the left side and message bubbles on the right. He scrolls slowly with two fingers on the trackpad at 00:02.000, stops, tilts his head, and his eyes narrow as an idea forms.
[Shot 3] At 00:03.500, the shot cuts to a medium close-up of <Subject 1> in three-quarter profile. <Subject 1> (S1) mutters to himself in a low, thinking voice, slowed and almost questioning, and with the slightly guarded delivery of someone talking to himself in an open office, his lips clearly moving and his gaze drifting off the screen: <d>[Chinese] 不少已经合作的存量客户，还有哪些机会可以深挖？不如把微信聊天记录导出来分析看看！</d> On the last phrase his eyes come back to the screen and his right hand moves to the mouse.
[Shot 4] At 00:12.500, the shot cuts to a close-up of the laptop screen. The chat window shrinks to the left half, a file export progress strip fills and completes at 00:13.500, and an exported chat-record file tile drops onto the desktop. He drags the tile with the mouse into the "对公营销情报官" input box; the <Subject 2> avatar, matching <Picture 2> exactly, appears beside the attachment chip as the file locks in at 00:14.600 and the shot ends on the attached file chip.

overall_soundscape:
Office room tone continues underneath, and a quiet afternoon ambience with distant footsteps replaces the earlier bustle. A trackpad scroll ticks twice, a mouse button clicks, an export progress strip emits a short rising tone, and a soft drag-and-drop thud marks the chat-record file landing in the input box, followed by a single confirmation blip.

non_diegetic_music:
A plucked-synth ostinato at a moderate tempo, now with a warmer low synth pad; the pattern drops out for the blank frame, re-enters at 00:01.000 at a slightly lower level under the self-talk, and lifts back to full level at 00:12.500.
```

---

## 第 9 段（02:00–02:15）｜挖掘线索指令 + 报告生成

> **本段参考**：`<Picture 1>` = xw.png（小王）｜`<Picture 2>` = qbg.png（对公营销情报官）
> **本段发声**：`S1` = 情报官（`<Subject 2>`）；小王本段仅打字，无台词

```text
subject_definitions:
<Subject 1> is 小王, the newly hired corporate banking relationship manager taken from <Picture 1> (xw.png); his face, hair, build, and outfit follow <Picture 1> exactly.
<Subject 2> is 对公营销情报官, the bank's in-house AI agent taken from <Picture 2> (qbg.png), appearing as the assistant avatar inside the "对公营销情报官" chat panel on the laptop screen; its look follows <Picture 2> exactly.

summary:
[reference generation] The target video shows <Subject 1> typing a short instruction into the chat panel and the <Subject 2> agent returning a parsed-insight summary built from the uploaded chat records, ending on a generated report card. His identity stays consistent with <Picture 1> and the agent's look stays consistent with <Picture 2>.

retention_analysis:
<Subject 1> (appears in [Shot 1], [Shot 3]): fully_preserved - identity and outfit from <Picture 1> are unchanged; his hands and posture are the only additions.
<Subject 2> (appears in [Shot 1], [Shot 2], [Shot 3]): fully_preserved - the assistant's look from <Picture 2> is retained in the avatar and the report header.

detailed_description:
The target video keeps the bright corporate-explainer look, with warm late-day daylight and a soft screen glow lighting the subject's face.
[Shot 1] A close-up of the laptop screen holds the "对公营销情报官" input box with the chat-record file chip still attached above it. <Subject 1>'s hands enter from the bottom of the frame, and the typed characters appear quickly and evenly, forming "帮我挖掘聊天线索。" by 00:02.200; Enter is pressed at 00:02.500. The <Subject 2> avatar, matching <Picture 2> exactly, pulses once as the reply begins.
[Shot 2] At 00:02.500, the shot cuts to a medium close-up of the screen as the reply bubble streams out and the agent's voice starts. <Subject 2> (S1) says in a clear, evenly paced synthetic assistant voice: <d>[Chinese] 已解析微信对话记录，识别企业未表露痛点3项，挖掘潜在业务机会，存量客户营销线索报告已生成！</d> While the line plays, three labelled markers appear in sequence inside the bubble at 00:04.200, 00:06.000, and 00:07.600, each attached to an extracted chat snippet. The camera pushes in with small amplitude at slow speed, and at 00:09.000 the bubble collapses into a report card titled "存量客户营销线索报告".
[Shot 3] At 00:12.500, the shot cuts to a medium shot of the desk from the front as <Subject 1>, whose face and outfit match <Picture 1> exactly, moves the cursor onto the report card and clicks it at 00:13.200; the card opens into a full report page with a summary block at the top and a list of clue entries below, and his left hand rises to the desk edge as the page finishes loading in the final second.

overall_soundscape:
Office room tone continues underneath. Fast keyboard taps and an Enter press open the segment, followed by a message-post blip and a soft ticking sound as the three insight markers appear one by one. A mouse button clicks and a short page-open swoosh marks the report expanding, ending on a light interface settle tone.

non_diegetic_music:
A plucked-synth ostinato at a moderate tempo with a muted kick and light shaker; a sustained low synth note enters at 00:02.500 under the answer, rising slightly at 00:12.500 and holding to the end.
```

---

## 第 10 段（02:15–02:30）｜惊喜发现 + 走访归来（含 1s 空白）

> **本段参考**：`<Picture 1>` = xw.png（小王）｜`<Picture 2>` = qbg.png（对公营销情报官）
> **本段发声**：`S1` = 小王（`<Subject 1>`）；情报官本段无台词

```text
subject_definitions:
<Subject 1> is 小王, the newly hired corporate banking relationship manager taken from <Picture 1> (xw.png); his face, hair, build, and outfit follow <Picture 1> exactly.
<Subject 2> is 对公营销情报官, the bank's in-house AI agent taken from <Picture 2> (qbg.png), appearing as the assistant avatar inside the "对公营销情报官" chat panel on the laptop screen; its look follows <Picture 2> exactly.

summary:
[reference generation] The target video shows <Subject 1> opening the generated clue report and reacting with delight, followed by a one-second blank frame, then cutting to him back from a client visit facing a desk full of audio recordings. His identity stays consistent with <Picture 1> and the agent's look stays consistent with <Picture 2>.

retention_analysis:
<Subject 1> (appears in [Shot 1], [Shot 2], [Shot 4]): fully_preserved - identity and outfit from <Picture 1> are unchanged; only his surprised expression and his troubled posture after the time jump are added.
<Subject 2> (appears in [Shot 1]): fully_preserved - the assistant's look from <Picture 2> is retained in the report header.

detailed_description:
The target video keeps the bright corporate-explainer look; the first half uses warm late-day daylight at the desk, and the second half shifts to a cooler, softer light as the desk is covered with recording files.
[Shot 1] A close-up of the laptop screen holds the opened "存量客户营销线索报告", whose header carries the <Subject 2> mark matching <Picture 2> exactly. The page shows a summary block of three numbered pain points above a list of clue entries; the camera trucks down with small amplitude at slow speed along the list, and <Subject 1>'s index finger enters from the lower right to trace one entry at 00:00.600.
[Shot 2] At 00:01.000, the shot cuts to a medium close-up of <Subject 1>, whose face and outfit match <Picture 1> exactly. His eyebrows lift, his mouth opens, and he leans back a little as <Subject 1> (S1) says in a surprised, bright young male voice at an eager but clear pace: <d>[Chinese] 原来客户还有这么多潜在需求没有发掘！存量客户深耕又找到新方向了！</d> On the last phrase he straightens up and his right hand taps the desk once. At 00:08.000 a subtitle fades in across the lower third in white type with a short red accent bar: "解析聊天记录｜挖掘存量隐藏需求｜匹配行内产品" and holds to 00:09.500.
[Shot 3] At 00:09.500, the shot cuts to a completely blank white frame that holds motionless and silent for one second.
[Shot 4] At 00:10.500, the shot cuts to a medium wide shot of the same desk in cooler light. <Subject 1>, whose face and outfit match <Picture 1> exactly, walks in from the right and sets a shoulder bag down beside the chair at 00:11.500, then sits. The desk is now covered with a loose fan of audio-recording cards and a small digital voice recorder; he looks down at the pile, rubs the back of his neck, and his face falls into a worried frown as the segment ends.

overall_soundscape:
Office room tone continues underneath. A fingertip taps a screen edge, a hand taps a desk, and a chair shifts. After the blank frame, a shoulder bag settles on the floor, a chair is pulled out and sat in, and a soft loose rustle of paper cards is heard as the recordings fan out across the desk. A quiet exhale closes the segment.

non_diegetic_music:
A plucked-synth ostinato at a moderate tempo with a light shaker; the rhythm drops out for the blank frame, re-enters at 00:10.500 in a lower, thinner register with a single sustained note, and holds under the final beat.
```

---

## 第 11 段（02:30–02:45）｜录音上传与解析

> **本段参考**：`<Picture 1>` = xw.png（小王）｜`<Picture 2>` = qbg.png（对公营销情报官）
> **本段发声**：`S1` = 小王（`<Subject 1>`）；情报官本段无台词

```text
subject_definitions:
<Subject 1> is 小王, the newly hired corporate banking relationship manager taken from <Picture 1> (xw.png); his face, hair, build, and outfit follow <Picture 1> exactly.
<Subject 2> is 对公营销情报官, the bank's in-house AI agent taken from <Picture 2> (qbg.png), appearing as the assistant avatar inside the "对公营销情报官" chat panel on the laptop screen; its look follows <Picture 2> exactly.

summary:
[reference generation] The target video shows <Subject 1> stuck on a pile of visit recordings, complaining about it, then dragging the whole batch into the <Subject 2> panel and watching the files being parsed. His identity stays consistent with <Picture 1> and the agent's look stays consistent with <Picture 2>.

retention_analysis:
<Subject 1> (appears in [Shot 1], [Shot 2], [Shot 3]): fully_preserved - identity and outfit from <Picture 1> are unchanged; only his troubled expression, drag gesture, and watching posture are added.
<Subject 2> (appears in [Shot 2], [Shot 3]): fully_preserved - the assistant's look from <Picture 2> is retained in the chat panel and the parsing indicator.

detailed_description:
The target video keeps the bright corporate-explainer look with cooler, softer daylight and a clean screen glow on the desk.
[Shot 1] A medium close-up frames <Subject 1>, whose face and outfit match <Picture 1> exactly, seated behind a fan of audio-recording cards and a small digital voice recorder. He spreads the cards apart with both hands, looks down at the pile, and rubs the back of his neck. At 00:00.500 <Subject 1> (S1) says in a frustrated, slightly helpless young male voice at a slowed, sighing pace: <d>[Chinese] 刚结束客户走访，一堆录音材料，整理记录无从下手。</d> He lets his hand drop onto the desk on the last phrase.
[Shot 2] At 00:05.500, the shot cuts to an over-shoulder view of the desk and laptop. <Subject 1>'s left hand sweeps the recording cards together and his right hand drags the selected batch onto the "对公营销情报官" input box; the <Subject 2> avatar, matching <Picture 2> exactly, sits at the left of the chat area. The file chips stack into a compact attachment list from 00:06.200 to 00:08.000, each chip showing a filename and a small audio waveform.
[Shot 3] At 00:08.500, the shot cuts to a close-up of the screen. A parsing indicator appears under the attachment list and a progress arc sweeps around the <Subject 2> avatar; the waveform inside each chip lights up in sequence from left to right, filename by filename, and short grey text lines condense out of each waveform as it finishes. The camera pushes in with small amplitude at slow speed while the progress arc completes at 00:13.000 and a short status line appears: "解析完成". The shot holds on the completed attachment list with all chips lit until the end of the segment.

overall_soundscape:
Cool office room tone and a faint laptop fan continue underneath. Paper cards slide and rustle against the desk, a hand drags across a trackpad, and a soft multi-file upload swell is heard as the chips stack. A steady electronic parsing tick repeats as each waveform lights up, ending with a single clean two-note confirmation chime.

non_diegetic_music:
A thin plucked-synth pattern at a slow-to-moderate tempo with a soft sustained low synth note; the percussion stays sparse through the upload, and a light ticking layer joins at 00:08.500 and runs to the final frame.
```

---

## 第 12 段（02:45–03:00）｜走访记录生成与归档

> **本段参考**：`<Picture 1>` = xw.png（小王）｜`<Picture 2>` = qbg.png（对公营销情报官）
> **本段发声**：`S1` = 情报官（`<Subject 2>`）→ `S2` = 小王（`<Subject 1>`）

```text
subject_definitions:
<Subject 1> is 小王, the newly hired corporate banking relationship manager taken from <Picture 1> (xw.png); his face, hair, build, and outfit follow <Picture 1> exactly.
<Subject 2> is 对公营销情报官, the bank's in-house AI agent taken from <Picture 2> (qbg.png), appearing as the assistant avatar inside the "对公营销情报官" chat panel on the laptop screen; its look follows <Picture 2> exactly.

summary:
[reference generation] The target video shows the <Subject 2> agent delivering a complete visit-record summary after the audio parsing, then <Subject 1> reviewing the document, archiving it, and finally relaxing. His identity stays consistent with <Picture 1> and the agent's look stays consistent with <Picture 2>.

retention_analysis:
<Subject 1> (appears in [Shot 2], [Shot 3], [Shot 4]): fully_preserved - identity and outfit from <Picture 1> are unchanged; only his reading, clicking, and relieved expression are added.
<Subject 2> (appears in [Shot 1], [Shot 2]): fully_preserved - the assistant's look from <Picture 2> is retained in the avatar and the document header.

detailed_description:
The target video keeps the bright corporate-explainer look, with cool daylight from the window and a clean screen glow across the desk.
[Shot 1] A close-up of the laptop screen holds the completed attachment list with all waveform chips lit, and the parsing indicator switches to a check mark at 00:00.200.
[Shot 2] At 00:00.500, the shot cuts to a medium close-up of the screen as the reply bubble expands under the <Subject 2> avatar, whose look matches <Picture 2> exactly, and the agent's voice begins. <Subject 2> (S1) says in a clear, evenly paced synthetic assistant voice: <d>[Chinese] 录音解析完成，已提炼客户诉求、关键分歧、合作意向、待跟进事项，输出完整走访记录总结文档。</d> As the line plays, the bubble resolves into a document card titled "客户走访记录总结" and four labelled blocks appear in sequence at 00:03.800, 00:05.400, 00:07.000, and 00:08.600: 客户诉求, 关键分歧, 合作意向, 待跟进事项. The camera trucks down with small amplitude at slow speed to keep pace with the blocks filling in.
[Shot 3] At 00:10.500, the shot cuts to a medium shot of the desk from the front as <Subject 1>, whose face and outfit match <Picture 1> exactly, scrolls slowly through the finished summary, his eyes moving down the page and his head nodding once at 00:11.500. At 00:11.800 <Subject 1> (S2) says in a relieved, warm young male voice at a relaxed pace: <d>[Chinese] 这下拜访材料整理归档省心多了！</d>
[Shot 4] At 00:14.000, the shot cuts to a close-up of the screen: the cursor moves onto an "存档" button at the top right of the document and clicks it at 00:14.300; the button turns to a check state and the document thumbnail slides into an archive folder on screen. A long, audible exhale from <Subject 1> is heard over the final half second.

overall_soundscape:
Cool office room tone and a faint laptop fan continue underneath. A single confirmation chime marks the parsing check, a soft ticking sound accompanies the four summary blocks filling in, and a trackpad scroll ticks twice. A mouse button clicks, a light archive swoosh follows the document into the folder, and a long relaxed exhale closes the segment.

non_diegetic_music:
A plucked-synth ostinato at a moderate tempo with a warm sustained pad underneath; the percussion softens at 00:10.500 and the pattern resolves on a single long synth note in the final second.
```

---

## 第 13 段（03:00–03:15）｜合上电脑・前半口诀（含 1s 空白）

> **本段参考**：`<Picture 1>` = xw.png（小王）｜`<Picture 2>` = qbg.png（对公营销情报官）
> **本段发声**：`S1` = 小王（`<Subject 1>`）；情报官本段仅亮屏，无台词

```text
subject_definitions:
<Subject 1> is 小王, the newly hired corporate banking relationship manager taken from <Picture 1> (xw.png); his face, hair, build, and outfit follow <Picture 1> exactly.
<Subject 2> is 对公营销情报官, the bank's in-house AI agent taken from <Picture 2> (qbg.png), shown as the assistant avatar on the phone screen lying on the desk; its look follows <Picture 2> exactly.

summary:
[reference generation] After a one-second blank frame, the target video shows <Subject 1> closing his laptop, straightening up, and confidently reciting the first half of his summary, while a phone on the desk lights up with the <Subject 2> avatar as the agent prepares to answer. His identity stays consistent with <Picture 1> and the agent's look stays consistent with <Picture 2>.

retention_analysis:
<Subject 1> (appears in [Shot 2], [Shot 3], [Shot 4]): fully_preserved - identity and outfit from <Picture 1> are unchanged; only his closing action, recital, and fist gesture are added.
<Subject 2> (appears in [Shot 4]): fully_preserved - the assistant's look from <Picture 2> is retained unchanged as the avatar on the phone screen.

detailed_description:
The target video keeps the bright corporate-explainer look, with late-afternoon daylight warming the office slightly and a calm, settled atmosphere at the desk.
[Shot 1] The video opens on a completely blank white frame that holds motionless and silent for one second.
[Shot 2] At 00:01.000, the shot cuts to a close-up of <Subject 1>'s hands, whose skin and sleeve match <Picture 1> exactly, as he folds the laptop lid shut with one smooth press; the lid meets the base with a soft click at 00:02.400 and the screen glow dies.
[Shot 3] At 00:02.500, the shot cuts to a medium close-up of <Subject 1>, whose face and outfit match <Picture 1> exactly, sitting upright behind the closed laptop. The camera slowly arcs right with small amplitude at slow speed around him. <Subject 1> (S1) recites in a confident, rhythmic young male voice at a steady, clearly separated pace, counting each step with a small hand movement on the desk: <d>[Chinese] 有了情报官加持——政策找方向、匹配选客户、研报补认知、一页纸备拜访，聊天挖线索、录音做归档！</d> His chin lifts on the final phrase.
[Shot 4] At 00:11.500, the shot cuts to a slightly wider medium shot as <Subject 1> raises his right hand into a firm fist at chest height and holds it, his expression resolved. At 00:13.500 the phone lying on the desk beside the closed laptop lights up on its own, and the <Subject 2> avatar, matching <Picture 2> exactly, appears clearly on the phone screen; the shot holds on that lit phone and his fist until the end of the segment.

overall_soundscape:
Quiet late-afternoon office room tone continues underneath with a faint laptop fan that stops when the lid closes. The lid snaps shut with a soft mechanical click, the hinge settles, a hand taps the desk twice during the recital, and a short bright notification tone sounds from the phone at 00:13.500.

non_diegetic_music:
A plucked-synth ostinato at a moderate tempo with a muted kick; the pattern drops out for the blank frame, re-enters at 00:01.000 with a fuller low end, and rises in level from 00:11.500 to the final frame.
```

---

## 第 14 段（03:15–03:30）｜口诀收尾・定帧

> **本段参考**：`<Picture 1>` = xw.png（小王）｜`<Picture 2>` = qbg.png（对公营销情报官）
> **本段发声**：`S1` = 情报官（`<Subject 2>`，手机画外音）；小王本段无台词

```text
subject_definitions:
<Subject 1> is 小王, the newly hired corporate banking relationship manager taken from <Picture 1> (xw.png); his face, hair, build, and outfit follow <Picture 1> exactly.
<Subject 2> is 对公营销情报官, the bank's in-house AI agent taken from <Picture 2> (qbg.png), shown as the assistant avatar on the phone screen lying on the desk and heard as an off-screen voice from that phone; its look follows <Picture 2> exactly.

summary:
[reference generation] The target video delivers the <Subject 2> agent's closing mnemonic as an off-screen voice from the phone on the desk, shows <Subject 1> nodding in agreement, and ends on a freeze frame with the title card. His identity stays consistent with <Picture 1> and the agent's look stays consistent with <Picture 2>.

retention_analysis:
<Subject 1> (appears in [Shot 1], [Shot 2], [Shot 3]): fully_preserved - identity and outfit from <Picture 1> are unchanged; only his listening posture, nod, and the freeze of the final frame are added.
<Subject 2> (appears in [Shot 1], [Shot 3]): fully_preserved - the assistant's look from <Picture 2> is retained on the phone screen and reused unchanged in the end-card mark.

detailed_description:
The target video keeps the bright corporate-explainer look with warm late-afternoon daylight, and the final shot resolves into a clean graphic end card.
[Shot 1] A medium close-up frames <Subject 1>, whose face and outfit match <Picture 1> exactly, seated behind the closed laptop with his right fist still at chest height. The phone on the desk holds the lit <Subject 2> avatar, matching <Picture 2> exactly, and <Subject 2> (S1) speaks from the phone as an off-screen voice in a clear, evenly paced synthetic assistant voice, while <Subject 1>'s lips remain completely closed: <d>[Chinese] 记住口诀——找政策、筛客户、做准备、挖存量、理走访。对公拓客不再难！</d> The camera pushes in with small amplitude at slow speed on <Subject 1>'s face, and his eyes move down toward the phone as he listens.
[Shot 2] At 00:06.500, the shot cuts to a close-up of <Subject 1> as he nods twice, firmly, at 00:07.000 and 00:07.800, lowers his fist to the desk, and lets a small confident smile settle on his face.
[Shot 3] At 00:09.000, the image freezes on <Subject 1>'s smiling frame, holding completely motionless. Across the frozen frame a clean title card resolves: at 00:09.500 the line "对公营销情报官・精准服务客户" fades in across the centre in bold white type on a soft translucent light-blue band, and at 00:10.500 the <Subject 2> mark, matching <Picture 2> exactly, fades in above the text. The card and the frozen frame hold without motion until the final frame at 00:15.000.

overall_soundscape:
Quiet late-afternoon office room tone continues underneath and fades gradually from 00:09.000. A short bright phone speaker tone is heard as the agent's voice starts, and the room tone drops to near silence under the frozen end card.

non_diegetic_music:
A plucked-synth ostinato at a moderate tempo with a muted kick and warm pad, lifting in level through the agent's line, then resolving onto a sustained major chord at 00:09.000 that decays slowly and fades out by the final frame.
```

---

## 三、拼装与使用说明

1. **上传顺序必须按段核对**：第 1 段 `xw → ts`；第 2 段 `xw → ts → qbg`；第 3–14 段统一 `xw → qbg`。上传顺序即 `<Picture 1/2/3>` 的编号顺序，顺序错了角色映射就会串。
2. **编号每段重来**：`<Subject 1>` 永远是小王（他 14 段全出镜），同事与情报官按该段出场先后顺延；`(Sx)` 按该段发声先后重排——所以第 2 段同事是 `S1`、第 12 段小王是 `S2`，属正常现象，不影响跨段音色。
3. **音色靠文字锁定**：`S1/S2` 只是段内标签，真正的音色锚点是台词前后的描述——小王「清亮偏年轻男声」、同事「沉稳成熟男声」、情报官「中性、清晰、等速合成音」。这三句在不同段里措辞保持一致，切勿在不同段改成别的音色形容，否则拼接会听出两个声音。
4. **转场衔接**：第 3、6（头尾）、8、10、13 段的 1s 纯白画面即原剧本要求的空白过渡，剪辑时不用额外加黑场。
5. **时间跳跃**：第 8 段起光线转暖（下午），第 10 段后转冷柔光并出现录音文件，用于交代「多次成功案例后」与「走访归来」；造型不变。
6. **占位名**：`XX旅游文化发展有限公司` 替换为真实企业名时，名称变长会挤占第 4 段 0.4s 余量，建议把第 4 段 `[Shot 3]` 的 12.000 推镜提前 0.5s。
