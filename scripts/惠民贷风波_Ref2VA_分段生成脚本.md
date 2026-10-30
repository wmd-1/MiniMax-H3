# 《惠民贷风波》Ref2VA 分段生成脚本

> 生成模式：**Ref2VA（全参考）** ｜ 每段时长：**15s（整数）** ｜ 段数：**15 段** ｜ 总时长：**225s ≈ 3分45秒**  
> 每段 `subject_definitions` 均从 `<Subject 1>` 重新编号，可独立生成、独立抽卡。  
> 分段时长一律取整数秒（全部 15s）；口播估算与镜内切点为精度保留小数，不必取整。

---

## 一、素材映射

| 文件名       | 角色                    | 出现段        |
| --------- | --------------------- | ---------- |
| `ldh.png` | 李大海（45岁，小微企业主，惠民贷借款人） | 1–15（全段）   |
| `zxm.png` | 张晓敏（李大海妻子）            | 1、2        |
| `xw.png`  | 小王（交通银行客户经理）          | 3、4、5、8–15 |
| `xl.png`  | 小刘（外包催收人员，电话端）        | 6、7        |

生成时按段上传对应图片即可，未出现的角色不必上传。

---

## 二、分段与节奏规划

| 段  | 场景       | 台词内容                         | 字数 | 口播     | 时长  | 镜次（切点）              |
| -- | -------- | ---------------------------- | -- | ------ | --- | ------------------- |
| 1  | 客厅·日     | 李大海抱怨逾期 + 张晓敏质疑越还越多          | 64 | ≈13.9s | 15s | 0 / 8.3 / 15        |
| 2  | 客厅餐桌·日   | 李大海算罚息、要求减免                  | 42 | ≈9.1s  | 15s | 0 / 5.6 / 10 / 15   |
| 3  | 营业厅      | 李大海激动陈情 + 小王接住情绪             | 51 | ≈11.1s | 15s | 0 / 3.6 / 9.8 / 15  |
| 4  | 营业厅      | 小王解释罚息无法减免、提协商方案             | 56 | ≈12.2s | 15s | 0 / 7.6 / 12.8 / 15 |
| 5  | 营业厅→家中·夜 | 李大海质问「凭什么」离场 → 电话响起          | 29 | ≈6.3s  | 15s | 0 / 7 / 15          |
| 6  | 家中·夜     | 小刘通知逾期22天、明日12点前还款 + 李大海顶回一句 | 59 | ≈12.7s | 15s | 0 / 9 / 12 / 15     |
| 7  | 家中·夜     | 李大海爆发 + 小刘「只能走法律程序」+ 挂断      | 57 | ≈12.4s | 15s | 0 / 7 / 13.4 / 15   |
| 8  | 网点洽谈位    | 李大海投诉 + 小王回应诉求               | 60 | ≈13.0s | 15s | 0 / 7.5 / 15        |
| 9  | 网点洽谈位    | 小王介绍四种纾困方案                   | 42 | ≈9.1s  | 15s | 0 / 6 / 10 / 15     |
| 10 | 网点洽谈位    | 展期条件：前提 + 四类材料               | 63 | ≈13.7s | 15s | 0 / 5 / 15          |
| 11 | 网点洽谈位    | 展期期限上限规则                     | 61 | ≈13.3s | 15s | 0 / 6 / 15          |
| 12 | 网点洽谈位    | 线下协商还款 + 签署《承诺书》             | 63 | ≈13.7s | 15s | 0 / 5.6 / 15        |
| 13 | 网点洽谈位    | 暂停诉讼催收 / 合同不变 / 征信仍上报        | 53 | ≈11.5s | 15s | 0 / 4.1 / 12.3 / 15 |
| 14 | 网点洽谈位    | 李大海确认办理 + 小王应下试算             | 57 | ≈12.4s | 15s | 0 / 9.2 / 15        |
| 15 | 网点洽谈位    | 小王收尾 + 签字 + 结尾字幕             | 9  | ≈2.0s  | 15s | 0 / 3.4 / 7.2 / 15  |

每段总时长统一为 **15s（整数）**；口播列是按 4.5–4.8 字/秒估算的参考值，镜内切点为小数不受限制。全片口播约 168s，占 225s 的 75%，属于对话剧的正常密度，没有一句被压到 5 字/秒以上。

---

## 三、对原剧本的必要修正（请确认）

1. **「女士」→「先生」**：第四场小王台词「女士，我理解您的诉求」，被称呼对象是李大海（男），已改为「先生」。
2. **「展期后不超过贷款总期限明」→「展期后不超过贷款总期限」**：原文末字「明」疑为笔误，已删除。
3. **占位符 `XX` / `X年X月` 保留原样**：原剧本「每月XX日前，至少偿还XX元，并在X年X月前还清全部欠款」，若直接送进 TTS 会读成「叉叉」。**生成前请替换为实际约定值**（例如「每月15日前，至少偿还2000元，并在2027年6月前还清全部欠款」），替换位置在 Segment 12 的台词内。其余数字保持原剧本原样。
4. **李大海的爆发句跨段切分**：「我说了我现在没钱！／你们天天打电话有意思吗？……」在句号处断开，前一句收在 Segment 6 结尾，后一句起于 Segment 7 开头。原因是 7 号段还要装小刘的回话和挂断动作，整段爆发塞进 15s 会让语速和挂断都挤到位。
5. **小刘的视觉出场**：原剧本他只有「电话那头」的声音。因您提供了 `xl.png`，Segment 6 加了一个**电话端切镜**（他的台词一句未改、时序未变、声音跨剪切连续）。若不需要，直接删掉 Segment 6 的 `[Shot 2]` 并把 `[Shot 3]` 的时间码前移即可。
6. **「你好，再不给我减免，我就要投诉」**：保留原句；第四场开头用「小王起身示意请坐」承接「预约到网点面谈」的场景说明。
7. **结尾字幕**按原剧本作为**画面字幕**处理（不做配音），在 Segment 15 淡入并保持到片尾。

---

## 四、通用生成设置

- **模式**：Ref2VA 全参考，不使用 I2VA / FL2VA / L2VA。
- **时长**：每段统一填 **15**（整数秒），不带小数；镜内切点用 `MM:SS.mmm` 表达，可带小数。
- **视觉基调（全片统一）**：真人实拍、写实短剧质感、浅景深；家中暖色调生活光，营业厅冷白顶光。
- **角色一致性**：`subject_definitions` 中只声明「外形完全取自对应图片」，**不添加任何发色、服装、体型等额外描述**，避免模型自由发挥。
- **语速基准**：对话戏 4.6–4.8 字/秒，政策解释 4.5 字/秒。所有 `[Shot N]` 切点均已按此核算。

---

## 五、分段 Prompt

### Segment 1 ｜逾期焦虑 · 客厅白天

素材：`ldh.png`、`zxm.png`

```text
subject_definitions:
<Subject 1> is 李大海, the 45-year-old small-business owner and 惠民贷 borrower, whose appearance is taken directly from the reference image ldh.png; his face, hair and clothing follow that image exactly, with nothing added or altered.
<Subject 2> is 张晓敏, 李大海's wife, whose appearance is taken directly from the reference image zxm.png; her face, hair and clothing follow that image exactly, with nothing added or altered.

summary:
[reference generation] The target video is a single domestic exchange in the living room of 李大海's apartment in daylight. <Subject 1> paces while airing his loan worries, then <Subject 2> walks in from the kitchen and questions why the 惠民贷 balance keeps growing. Both identities come from their reference images and stay identical across the two shots.

retention_analysis:
<Subject 1> (appears in [Shot 1], [Shot 2]): fully_preserved - the identity, face, hair and clothing from ldh.png are retained in both shots.
<Subject 2> (appears in [Shot 2]): fully_preserved - the identity, face, hair and clothing from zxm.png are retained as she enters from the kitchen and speaks.

detailed_description:
The target video is live-action, cinematic and realistic in a modern Chinese family-drama register, lit by soft late-morning daylight through a balcony window, with warm wood tones and a shallow depth of field.
[Shot 1] A medium-wide static shot frames a compact apartment living room: a fabric sofa with cushions on the left, a low wooden coffee table holding a stack of bank statements and a phone, a wall clock above the sofa, and the edge of a dining table at the right rear. <Subject 1> (S1), 李大海, walks back and forth in front of the coffee table, brows drawn together, one hand rubbing the back of his neck. The camera tracks him with small amplitude at slow speed as he turns toward the window mid-stride. He speaks in a low, tired, slightly hoarse male voice at a subdued, worried pace, <d>[Chinese] 现在生意这么难做，贷款利滚利都要还不上了，这月又逾期了，银行肯定又要来电话了。</d> He exhales, stops pacing, and stares down at the statements on the table.
[Shot 2] At 00:08.300, the shot cuts to a medium shot from the kitchen-doorway side as <Subject 2> (S2), 张晓敏, steps out of the kitchen wiping her hands on a small towel. She slows at the edge of the living room, looks at the statements, then at <Subject 1>. The camera pushes in with small amplitude at slow speed. She speaks in a clear, slightly sharp female voice with an impatient but controlled tone, <d>[Chinese] 上个月刚还了2000，怎么又不够还利息了？这惠民贷怎么越还越多啊？</d> She lowers the towel and holds his gaze without looking away.

overall_soundscape:
Quiet apartment room tone with a faint refrigerator hum and a clock ticking steadily. Soft footsteps shift on the floor as <Subject 1> paces, and the towel rustles when <Subject 2> stops in the doorway.

non_diegetic_music:
A sparse low piano figure at a slow tempo with one sustained string note underneath, kept well below the dialogue.
```

---

### Segment 2 ｜账单与罚息 · 客厅餐桌

素材：`ldh.png`、`zxm.png`

```text
subject_definitions:
<Subject 1> is 李大海, the 45-year-old small-business owner, whose appearance is taken directly from the reference image ldh.png; his face, hair and clothing follow that image exactly, including the same clothing as in the previous scene.
<Subject 2> is 张晓敏, his wife, whose appearance is taken directly from the reference image zxm.png; her face, hair and clothing follow that image exactly.

summary:
[reference generation] The target video continues the same living room a few seconds later. <Subject 1> sits at the dining table working through the penalty interest on a repayment statement and pushes the paper toward <Subject 2>, who reads it in silence. All identity details come from the two reference images.

retention_analysis:
<Subject 1> (appears in [Shot 1], [Shot 2], [Shot 3]): fully_preserved - the identity, face, hair and clothing from ldh.png are retained through the shot changes.
<Subject 2> (appears in [Shot 3]): fully_preserved - the identity, face, hair and clothing from zxm.png are retained.

detailed_description:
The target video keeps the same live-action, cinematic, realistic family-drama look, with soft daylight from the balcony window falling across the table and a shallow depth of field.
[Shot 1] A medium two-shot frames the dining table from the side, with the living room sofa blurred in the background. <Subject 1> (S1), 李大海, sits down heavily, unfolds a repayment statement across the tabletop, pulls a small calculator toward himself and starts tapping keys with his index finger. <Subject 2>, 张晓敏, stands behind the opposite chair with one hand on its back. <Subject 1> (S1) speaks in the same tired, hoarse male voice, now with a sharper edge of grievance, <d>[Chinese] 我算了一下，光罚息一个月就涨1000多，</d> He stops typing and pushes the calculator aside with the back of his hand.
[Shot 2] At 00:05.600, the shot cuts to a close insert over his shoulder: the statement lies flat with rows of printed figures, his index finger sliding down the column and stopping, the calculator screen reflecting the window light so the digits stay unreadable. <Subject 1> (S1) continues off this framing, his voice rising at the end of the sentence, <d>[Chinese] 这什么时候是个头啊！银行一点政策都没有，凭什么不给我们减免？</d> His finger taps the paper twice on the final word.
[Shot 3] At 00:10.000, the shot cuts back to the medium two-shot. <Subject 2> (S2) pulls the statement toward herself, scans it, and lifts her eyes to <Subject 1> without speaking. He leans back in the chair and presses two fingers to his brow. The camera holds a static shot while the clock on the wall keeps ticking.

overall_soundscape:
The soft click of calculator keys and the dry rustle of paper against the tabletop carry through the room. A chair creaks as <Subject 1> leans back, and the wall clock keeps ticking underneath the quiet room tone.

non_diegetic_music:
The same sparse piano figure continues at a slow tempo, joined by a low sustained string note that fades out on the last frame.
```

---

### Segment 3 ｜协商被拒（上）· 营业厅

素材：`ldh.png`、`xw.png`

```text
subject_definitions:
<Subject 1> is 李大海, the 45-year-old small-business owner, whose appearance is taken directly from the reference image ldh.png; his face, hair and clothing follow that image exactly.
<Subject 2> is 小王, the 交通银行 account manager, whose appearance is taken directly from the reference image xw.png; her face, hair and clothing follow that image exactly, with nothing added or altered.

summary:
[reference generation] The target video moves to a consultation desk inside a 交通银行 branch, where <Subject 1> leans over the desk and pleads his case while <Subject 2> stays composed behind it and opens with an acknowledgement of his feelings. Both identities are taken from their reference images.

retention_analysis:
<Subject 1> (appears in [Shot 1], [Shot 2], [Shot 3]): fully_preserved - the identity, face, hair and clothing from ldh.png are retained across all three shots.
<Subject 2> (appears in [Shot 3]): fully_preserved - the identity, face, hair and clothing from xw.png are retained.

detailed_description:
The target video is live-action, cinematic and realistic, shot inside a modern Chinese bank branch lobby with cool white ceiling light, light-grey stone flooring and a blue-and-white counter line behind the consultation desk.
[Shot 1] A medium-wide static shot frames a consultation desk in the branch lobby. <Subject 1> (S1), 李大海, stands with both palms pressed flat on the desk edge and his upper body leaning forward, a folded set of documents under one hand. A queue-number slip and a name-card holder sit between him and the desk. He speaks in a loud, strained male voice with a fast, agitated rhythm, <d>[Chinese] 我不是不还钱，我是真的遇到困难了！</d> The camera pushes in with small amplitude at slow speed.
[Shot 2] At 00:03.600, the shot cuts to a tighter angle on <Subject 1> (S1) from the desk side. His shoulders rise with each breath, and he strikes his own chest once with his fingertips before gesturing at the documents. He continues in the same strained voice, cracking slightly on the last words, <d>[Chinese] 你们银行能不能人性化一点？让我分期还，每个月少还点不行吗？</d> He taps the documents against the desk edge as the line ends.
[Shot 3] At 00:09.800, the shot cuts to a medium shot of <Subject 2> (S2), 小王, seated behind the desk with her forearms resting on it and her hands loosely folded. Her posture stays upright and her expression is calm. She speaks in a clear, even, professional female voice at a measured pace, <d>[Chinese] 李先生，您的心情我理解。</d> She keeps eye contact the whole time. Across the desk, <Subject 1> pulls back a little and his jaw tightens.

overall_soundscape:
A quiet bank-hall ambience with distant footsteps on the stone floor, a low ventilation hum and an occasional soft chime from the queue system. Paper shifts under <Subject 1>'s palm as he leans on the desk.

non_diegetic_music:
A muted low string drone at a slow tempo with irregular piano notes, held under the dialogue without building.
```

---

### Segment 4 ｜协商被拒（下）· 营业厅
素材：`ldh.png`、`xw.png`

```text
subject_definitions:
<Subject 1> is 李大海, whose appearance is taken directly from the reference image ldh.png; his face, hair and clothing follow that image exactly and stay unchanged from the previous scene.
<Subject 2> is 小王, whose appearance is taken directly from the reference image xw.png; her face, hair and clothing follow that image exactly.

summary:
[reference generation] The target video stays at the same consultation desk. <Subject 2> explains that penalty interest cannot be waived and offers a negotiated repayment option, and <Subject 1> rejects it and starts comparing the bank with others. Identities come from the two reference images.

retention_analysis:
<Subject 1> (appears in [Shot 2], [Shot 3]): fully_preserved - the identity, face, hair and clothing from ldh.png are retained.
<Subject 2> (appears in [Shot 1], [Shot 3]): fully_preserved - the identity, face, hair and clothing from xw.png are retained.

detailed_description:
The target video continues the same live-action, cinematic, realistic bank-branch setting with the same cool ceiling light and blue-and-white counter line.
[Shot 1] A medium close shot frames <Subject 2> (S1), 小王, behind the consultation desk, her hands folded on the surface in front of her, a pen resting beside them. The camera holds a static shot as she speaks in the same clear, even, professional female voice, keeping her tone level and her pace unhurried, <d>[Chinese] 但根据监管和总行规定，罚息复利确实无法减免。我们可以帮您申请协商还款方案。</d> She inclines her head slightly on the last clause and slides a blank application form an inch toward him.
[Shot 2] At 00:07.600, the shot cuts to a close shot of <Subject 1> (S2), 李大海, from the opposite side of the desk. He lifts one hand palm-out to cut her off, then lets it fall onto the desk edge. He speaks in a raised, resentful male voice with a hard, clipped rhythm, <d>[Chinese] 我不想听，你们就知道收利息，根本不考虑我们的实际情况！</d> His jaw works and he turns his head half away from her.
[Shot 3] At 00:12.800, the shot cuts to a medium two-shot across the desk. <Subject 2> keeps her hands folded and her eyes on him, holding her reply. <Subject 1> leans back with his arms crossed, breathing hard through his nose. The camera holds still until the end of the shot.

overall_soundscape:
The bank-hall ambience continues with the ventilation hum and a distant chime. Fabric rustles as <Subject 1> shifts his weight, and the application form drags softly across the desk surface.

non_diegetic_music:
A low sustained string note with a slow, sparse piano figure underneath, staying level and fading slightly toward the end.
```

---

### Segment 5 ｜离场与来电 · 营业厅 → 家中夜晚
素材：`ldh.png`、`xw.png`（`xw.png` 仅用于第 1 镜）

```text
subject_definitions:
<Subject 1> is 李大海, whose appearance is taken directly from the reference image ldh.png; his face, hair and clothing follow that image exactly in both the bank and the apartment.
<Subject 2> is 小王, whose appearance is taken directly from the reference image xw.png; her face, hair and clothing follow that image exactly.

summary:
[reference generation] The target video closes the bank scene and opens the night scene at home. <Subject 1> throws one last accusation at <Subject 2> and walks out, then the same character stands in his dim apartment as his phone rings and he recognises the number. Identities come from the two reference images.

retention_analysis:
<Subject 1> (appears in [Shot 1], [Shot 2]): fully_preserved - the identity, face, hair and clothing from ldh.png are retained in both locations.
<Subject 2> (appears in [Shot 1]): fully_preserved - the identity, face, hair and clothing from xw.png are retained.

detailed_description:
The target video is live-action, cinematic and realistic, with the first shot keeping the cool bank-branch light and the second shot switching to warm dim apartment light.
[Shot 1] A medium shot frames the consultation desk from the side. <Subject 1> (S1), 李大海, pushes his chair back with the backs of his legs, sweeps his documents off the desk and says in a harsh, loud male voice with a fast delivery, <d>[Chinese] 其他银行都能减免，凭什么你们不行？</d> He shoulders his bag and turns away from the desk. The camera pans right with large amplitude at slow speed, following him as he walks out of frame past the counter line. Behind him, <Subject 2> begins to rise from her chair with one hand lifted to explain, then stops.
[Shot 2] At 00:07.000, the shot cuts to a medium shot of the apartment living room at night, lit only by a warm floor lamp and the blue glow of a television in standby. A phone lies face-up on the coffee table and starts vibrating, its screen lighting up with an incoming call. <Subject 1> (S1) walks in from the right in the same clothing, stops at the table and looks down at the screen. The camera tilts down with small amplitude at slow speed as he picks the phone up and reads the number. He exhales through his nose and says in a low, resigned voice, <d>[Chinese] 又来了，这都第几个电话了？</d> He swipes to answer and lifts the phone to his ear.

overall_soundscape:
Office ambience with a distant chime and footsteps on stone, cut off abruptly by the room tone of a quiet apartment at night. A phone vibrates against the wooden tabletop and stops when it is picked up.

non_diegetic_music:
N/A
```

---

### Segment 6 ｜催收通知 · 家中夜晚 / 催收端

素材：`xl.png`、`ldh.png`

```text
subject_definitions:
<Subject 1> is 小刘, the outsourced collection agent, whose appearance is taken directly from the reference image xl.png; his face, hair and clothing follow that image exactly.
<Subject 2> is 李大海, the borrower, whose appearance is taken directly from the reference image ldh.png; his face, hair and clothing follow that image exactly, matching the previous night scene at home.

summary:
[reference generation] The target video is a phone call at night. <Subject 2> listens in his dim living room while <Subject 1> delivers the overdue notice from a collection-office desk, the voice continuing uninterrupted across the cut between them, until <Subject 2> finally pushes back for the first time.

retention_analysis:
<Subject 1> (appears in [Shot 2]): fully_preserved - the identity, face, hair and clothing from xl.png are retained.
<Subject 2> (appears in [Shot 1], [Shot 3]): fully_preserved - the identity, face, hair and clothing from ldh.png are retained.

detailed_description:
The target video is live-action, cinematic and realistic, with a warm dim apartment interior and a cooler, harsher collection-office interior in the cutaway.
[Shot 1] A close shot frames <Subject 2> (S2), 李大海, standing beside the coffee table at night with the phone pressed to his ear, a lamp glowing behind him out of focus. The camera holds a static shot. The caller's voice arrives through the earpiece with a slightly compressed phone timbre: a firm, brisk male voice belonging to <Subject 1> (S1), speaking evenly without pause, <d>[Chinese] 李先生，您贷款已经逾期22天了，根据合同规定，您必须在明天中午12点前归还全部欠款，</d> <Subject 2> keeps his eyes on the floor and his free hand closes slowly into a fist.
[Shot 2] At 00:09.000, the shot cuts to a medium shot of <Subject 1> (S1), 小刘, seated at a cluttered desk with a headset microphone at his mouth and a printed call list in front of him, lit by cold overhead light. His voice carries over the cut without a break as he leans toward the microphone and continues with the same brisk delivery, <d>[Chinese] 否则我们将采取进一步措施！</d> He taps the call list once with a pen.
[Shot 3] At 00:12.000, the shot cuts back to <Subject 2> (S2) in the apartment, framed slightly wider so his shoulders and free arm are visible. His expression hardens and he cuts in over the earpiece in a tight, rising male voice, <d>[Chinese] 我说了我现在没钱！</d> His free hand slaps down against his own thigh on the last word.

overall_soundscape:
A quiet apartment room tone with a faint electrical hum from the lamp. The earpiece leaks a thin, compressed voice, a hand slaps once against fabric, and the headset and paper rustle faintly in the collection-office cutaway.

non_diegetic_music:
A single low electronic pulse repeating at a slow, steady tempo under the call, with no melodic movement.
```

---

### Segment 7 ｜爆发与挂断 · 家中夜晚

素材：`ldh.png`、`xl.png`

```text
subject_definitions:
<Subject 1> is 李大海, whose appearance is taken directly from the reference image ldh.png; his face, hair and clothing follow that image exactly, unchanged from the previous call scene.
<Subject 2> is 小刘, the collection agent on the other end of the line, whose appearance is taken directly from the reference image xl.png.

summary:
[reference generation] The target video is the second half of the night call. <Subject 1> shouts back at the phone and <Subject 2> answers flatly from his desk before <Subject 1> hangs up in anger.

retention_analysis:
<Subject 1> (appears in [Shot 1], [Shot 3]): fully_preserved - the identity, face, hair and clothing from ldh.png are retained.
<Subject 2> (appears in [Shot 2]): fully_preserved - the identity, face, hair and clothing from xl.png are retained.

detailed_description:
The target video is live-action, cinematic and realistic, alternating warm dim apartment light with cold collection-office light.
[Shot 1] A medium close shot frames <Subject 1> (S1), 李大海, in the apartment, standing beside the sofa with the phone at his ear, carrying straight on from his last outburst. His free hand cuts through the air as he speaks in the same loud, breaking male voice at a fast, furious pace, <d>[Chinese] 你们天天打电话有意思吗？我老婆孩子都被你们骚扰多少次了？</d> He plants his feet once the line is out and his chest heaves.
[Shot 2] At 00:07.000, the shot cuts to a close shot of <Subject 2> (S2), 小刘, at the collection desk, headset in place, eyes on the call list. He answers in the same brisk, flat, procedural male voice with no rise in volume, <d>[Chinese] 这是我们的工作职责与工作流程，按目前的情况只能走法律程序了！</d> He draws a short line on the list with his pen as he finishes.
[Shot 3] At 00:13.400, the shot cuts back to <Subject 1> (S1) in the apartment. His thumb hits the screen hard to end the call, and he drops the phone onto the sofa cushion. The camera holds a static shot on his face as he breathes out and stares at nothing, his jaw still tight.

overall_soundscape:
The apartment room tone continues with a faint lamp hum. The phone's plastic casing knocks against the cushion, and a harsh double breath from <Subject 1> carries through the last beat. A low desk ambience and faint keyboard clicks sit under the cutaway.

non_diegetic_music:
The low electronic pulse accelerates slightly under the argument and stops dead on the hang-up, leaving only room tone.
```

---

### Segment 8 ｜网点面谈 · 投诉
素材：`ldh.png`、`xw.png`

```text
subject_definitions:
<Subject 1> is 李大海, whose appearance is taken directly from the reference image ldh.png; his face, hair and clothing follow that image exactly.
<Subject 2> is 小王, the account manager, whose appearance is taken directly from the reference image xw.png; her face, hair and clothing follow that image exactly, unchanged from the earlier branch scene.

summary:
[reference generation] The target video opens the in-branch appointment. <Subject 1> sits down and immediately threatens a complaint over the penalty interest, and <Subject 2> receives it calmly and restates her understanding of his demand. Identities come from the two reference images.

retention_analysis:
<Subject 1> (appears in [Shot 1], [Shot 2]): fully_preserved - the identity, face, hair and clothing from ldh.png are retained.
<Subject 2> (appears in [Shot 1], [Shot 2]): fully_preserved - the identity, face, hair and clothing from xw.png are retained.

detailed_description:
The target video is live-action, cinematic and realistic, set in a bank branch consultation corner with cool white ceiling light, a light wooden desk and a frosted glass partition behind the manager's chair.
[Shot 1] A medium-wide static shot frames the consultation desk. <Subject 2>, 小王, stands beside her chair and gestures with an open palm toward the seat opposite. <Subject 1> (S1), 李大海, sets his bag on the floor, sits down, drags the chair an inch closer and plants both forearms on the desk. He speaks at once in a loud, hard male voice with a rapid, confrontational rhythm, <d>[Chinese] 你好，再不给我减免，我就要投诉！而且这个利息涨得太离谱了，我们要求减免！</d> He jabs a finger at the desk surface on the final words. <Subject 2> sits down opposite him and settles her hands on the desk.
[Shot 2] At 00:07.500, the shot cuts to a medium close shot of <Subject 2> (S2), 小王, facing him across the desk. She keeps her back straight, her gaze level, and her voice in the same clear, even, professional register at a measured pace, <d>[Chinese] 先生，我理解您的诉求。</d> She gives one slow nod and keeps her hands still on the desk. The camera holds a static shot through the end of the frame.

overall_soundscape:
A quiet bank-interior ambience with a ventilation hum, distant footsteps and a faint printer running somewhere behind the partition. A chair leg scrapes once on the floor as <Subject 1> sits down.

non_diegetic_music:
A restrained low string pad at a slow tempo with a single muted piano tone repeating at wide intervals.
```

---

### Segment 9 ｜四种纾困方案 · 网点洽谈位
素材：`xw.png`、`ldh.png`

```text
subject_definitions:
<Subject 1> is 小王, the account manager, whose appearance is taken directly from the reference image xw.png; her face, hair and clothing follow that image exactly.
<Subject 2> is 李大海, whose appearance is taken directly from the reference image ldh.png; his face, hair and clothing follow that image exactly.

summary:
[reference generation] The target video stays at the same consultation desk. <Subject 1> lays out four relief options and writes them on a form one by one, and <Subject 2> reads them with the first sign of softening.

retention_analysis:
<Subject 1> (appears in [Shot 1], [Shot 2]): fully_preserved - the identity, face, hair and clothing from xw.png are retained.
<Subject 2> (appears in [Shot 3]): fully_preserved - the identity, face, hair and clothing from ldh.png are retained.

detailed_description:
The target video keeps the same live-action, cinematic, realistic bank-interior look with cool ceiling light and a shallow depth of field over the desk.
[Shot 1] A medium shot frames <Subject 1> (S1), 小王, seated behind the desk with a printed form and a pen in front of her, angled slightly toward the man opposite. The camera pushes in with small amplitude at slow speed as she speaks in the same clear, professional female voice at an even, unhurried pace, <d>[Chinese] 但我们可以帮您申请个性化纾困方案，我们的纾困方案有四种，</d> She uncaps the pen and sets its tip on the form.
[Shot 2] At 00:06.000, the shot cuts to a closer angle over the desk corner, framing the form and her hand. She writes four short lines down the page in order while naming each one in the same steady voice, <d>[Chinese] 续授信、无还本续贷、展期、线下协商还款。</d> The form now reads "续授信  无还本续贷  展期  线下协商还款". She turns the page a quarter turn and pushes it toward the far side of the desk.
[Shot 3] At 00:10.000, the shot cuts to a close shot of <Subject 2> (S2), 李大海, on the opposite side. He looks down at the form, his brow loosening a little, then lifts his eyes back to her with his arms still crossed. The camera holds a static shot while his fingers drum once against his sleeve.

overall_soundscape:
Quiet bank-interior ambience with the ventilation hum continuing. The pen cap clicks off, the nib scratches lightly across the paper, and the form drags softly over the desk surface.

non_diegetic_music:
A slow piano figure with a warmer register than before, one sustained low string note underneath, no percussion.
```

---

### Segment 10 ｜展期方案（一）· 前提与材料

素材：`xw.png`、`ldh.png`

```text
subject_definitions:
<Subject 1> is 小王, the account manager, whose appearance is taken directly from the reference image xw.png; her face, hair and clothing follow that image exactly.
<Subject 2> is 李大海, whose appearance is taken directly from the reference image ldh.png; his face, hair and clothing follow that image exactly.

summary:
[reference generation] The target video explains the extension option at the same desk. <Subject 1> states the precondition of clearing the current overdue amount and then lists the four required document sets while <Subject 2> watches the papers being laid out.

retention_analysis:
<Subject 1> (appears in [Shot 1], [Shot 2]): fully_preserved - the identity, face, hair and clothing from xw.png are retained.
<Subject 2> (appears in [Shot 2]): fully_preserved - the identity, face, hair and clothing from ldh.png are retained.

detailed_description:
The target video keeps the same live-action, cinematic, realistic bank-interior look, cool ceiling light falling on a clean desk with documents fanned out across it.
[Shot 1] A medium close shot frames <Subject 1> (S1), 小王, behind the desk, the written form still under her hand. She squares the form with her fingertips and speaks in the same clear, even, professional female voice at a steady, measured pace, <d>[Chinese] 如您能结清目前逾期，我们可以给您申请展期业务，</d> She raises her eyes from the paper to the man opposite and holds them there.
[Shot 2] At 00:05.000, the shot cuts to a high-angle close shot of the desk surface, with <Subject 2>'s hands resting at the near edge of the frame. <Subject 1> (S1) slides four items into view one after another — an identification document, an income-proof folder, a credit report printout and a short stack of statements — and taps each with the tip of her pen as she names it in the same unhurried voice, <d>[Chinese] 需您提供身份证明材料、借款人（含配偶、共同借款人等）收入证明材料、征信报告、还款出现困难等资料。</d> The pen comes to rest at the edge of the last document. <Subject 2>'s right hand pulls back slightly from the desk.

overall_soundscape:
Quiet bank-interior room tone with the ventilation hum underneath. Paper slides across the desk in separate soft strokes and the pen taps lightly on each document.

non_diegetic_music:
A single sustained low string note with widely spaced piano tones at a slow tempo, staying flat and quiet.
```

---

### Segment 11 ｜展期方案（二）· 期限上限

素材：`xw.png`、`ldh.png`

```text
subject_definitions:
<Subject 1> is 小王, whose appearance is taken directly from the reference image xw.png; her face, hair and clothing follow that image exactly, unchanged from the previous shot.
<Subject 2> is 李大海, whose appearance is taken directly from the reference image ldh.png; his face, hair and clothing follow that image exactly.

summary:
[reference generation] The target video continues the extension explanation at the same desk. <Subject 1> sets out the term limits for loans under one year and over one year and closes with the overall cap, while <Subject 2> follows her pen on the sheet.

retention_analysis:
<Subject 1> (appears in [Shot 1], [Shot 2]): fully_preserved - the identity, face, hair and clothing from xw.png are retained.
<Subject 2> (appears in [Shot 2]): fully_preserved - the identity, face, hair and clothing from ldh.png are retained.

detailed_description:
The target video keeps the same live-action, cinematic, realistic bank-interior look and the same desk layout as the preceding shot.
[Shot 1] A medium close shot frames <Subject 1> (S1), 小王, holding the pen above a printed term sheet. She speaks in the same clear, even, professional female voice, slowing her pace slightly so each clause lands clearly, <d>[Chinese] 展期1年（含）以内的贷款，展期期限累计不得超过原贷款期限；</d> She draws a short vertical stroke on the sheet to mark the boundary of the first year.
[Shot 2] At 00:06.000, the shot cuts to an over-the-shoulder two-shot from behind <Subject 2> (S2), 李大海, with his shoulder and the back of his head soft in the foreground and the term sheet in focus beyond. <Subject 1> (S1) draws a longer horizontal line beneath the first stroke and then a second line half its length, moving the pen as she speaks in the same steady voice, <d>[Chinese] 1年以上的贷款，展期期限累计不得超过原贷款期限的一半。展期后不超过贷款总期限。</d> <Subject 2> gives a single slow nod as the pen comes to a stop. The camera holds a static shot to the end of the frame.

overall_soundscape:
The bank room tone continues with a faint page turn and the light scratch of the pen on paper. A distant chair scrapes across stone flooring beyond the partition.

non_diegetic_music:
The same low string note with sparse piano at a slow tempo, one tone rising a step near the end and holding.
```

---

### Segment 12 ｜线下协商还款 · 承诺书

素材：`xw.png`、`ldh.png`

```text
subject_definitions:
<Subject 1> is 小王, whose appearance is taken directly from the reference image xw.png; her face, hair and clothing follow that image exactly.
<Subject 2> is 李大海, whose appearance is taken directly from the reference image ldh.png; his face, hair and clothing follow that image exactly.

summary:
[reference generation] The target video introduces the offline negotiated repayment route at the same desk. <Subject 1> explains that a signed commitment letter is required and pushes the blank form toward <Subject 2>, describing the monthly obligation and the final deadline clause by clause.

retention_analysis:
<Subject 1> (appears in [Shot 1], [Shot 2]): fully_preserved - the identity, face, hair and clothing from xw.png are retained.
<Subject 2> (appears in [Shot 2]): fully_preserved - the identity, face, hair and clothing from ldh.png are retained.

detailed_description:
The target video keeps the same live-action, cinematic, realistic bank-interior look, with the documents on the desk now including a single-page form printed with a bold heading.
[Shot 1] A medium close shot frames <Subject 1> (S1), 小王, setting the term sheet aside and drawing a fresh single-page form in front of her. She speaks in the same clear, even, professional female voice at a steady, measured pace, <d>[Chinese] 如果您确实无法结清目前逾期，我们可以提供线下协商还款，</d> She turns the form so its heading faces the far side of the desk.
[Shot 2] At 00:05.600, the shot cuts to a close shot of the desk from the side, the form filling the lower frame with the heading "还款承诺书" across the top and several blank fields beneath. <Subject 1>'s (S1) index finger moves down the page, touching each blank field in turn while she continues in the same steady voice, <d>[Chinese] 需签署还款《承诺书》，承诺按月还款，每月某日前，至少偿还某元，并在某年某月前还清全部欠款。</d> Her finger stops on the final field, and she slides the form and a pen toward <Subject 2> (S2), whose hand comes into frame and rests on the edge of the paper without lifting it.

overall_soundscape:
Quiet bank-interior room tone with the ventilation hum continuing. The form slides across the desk with a dry paper sound, the pen rolls a few centimetres on the surface, and a soft breath is audible from <Subject 2>.

non_diegetic_music:
A slow piano figure in a lower register with one sustained string note, very quiet under the explanation.
```

---

### Segment 13 ｜关键取舍 · 暂停催收与征信
素材：`xw.png`、`ldh.png`

```text
subject_definitions:
<Subject 1> is 小王, whose appearance is taken directly from the reference image xw.png; her face, hair and clothing follow that image exactly.
<Subject 2> is 李大海, whose appearance is taken directly from the reference image ldh.png; his face, hair and clothing follow that image exactly.

summary:
[reference generation] The target video states the conditions attached to the offline repayment route. <Subject 1> explains that suspension of litigation and collection only follows on-time monthly payment, and that the contract terms and credit reporting remain unchanged, while <Subject 2> absorbs the credit-report point.

retention_analysis:
<Subject 1> (appears in [Shot 1], [Shot 2]): fully_preserved - the identity, face, hair and clothing from xw.png are retained.
<Subject 2> (appears in [Shot 2], [Shot 3]): fully_preserved - the identity, face, hair and clothing from ldh.png are retained.

detailed_description:
The target video keeps the same live-action, cinematic, realistic bank-interior look and the same desk arrangement.
[Shot 1] A close shot frames <Subject 1> (S1), 小王, her hands resting flat on either side of the form. She speaks in the same clear, professional female voice, dropping her volume slightly and keeping her delivery even, <d>[Chinese] 如能按月履行承诺，我行将暂停诉讼、催收。</d> She lifts one hand and presses it down once, flat, on the desk to mark the condition.
[Shot 2] At 00:04.100, the shot cuts to a medium shot of <Subject 1> (S1) from the front, the frosted glass partition behind her. She keeps her hands together on the desk and continues in the same steady voice, giving each clause its own beat, <d>[Chinese] 线下协商还款不变更借款合同，应收利息、费用仍按照合同执行，逾期还款征信仍然上报。</d> On the last four words she holds <Subject 2>'s gaze deliberately and does not soften them. In the foreground edge of the frame, <Subject 2>'s posture goes still.
[Shot 3] At 00:12.300, the shot cuts to a close shot of <Subject 2> (S2), 李大海. His lips part slightly, then he presses them together and gives one slow nod, his eyes dropping to the form in front of him. The camera holds a static shot to the end of the frame.

overall_soundscape:
The bank room tone stays even, with a ventilation hum and a faint printer running behind the partition. A chair shifts once and a soft exhale comes from <Subject 2>.

non_diegetic_music:
One sustained string note at a low volume that slowly descends a step and holds to the final frame.
```

---

### Segment 14 ｜确认办理 · 试算
素材：`ldh.png`、`xw.png`

```text
subject_definitions:
<Subject 1> is 李大海, whose appearance is taken directly from the reference image ldh.png; his face, hair and clothing follow that image exactly.
<Subject 2> is 小王, the account manager, whose appearance is taken directly from the reference image xw.png; her face, hair and clothing follow that image exactly.

summary:
[reference generation] The target video closes the negotiation. <Subject 1> accepts the offline negotiated repayment route and asks for a monthly figure with no litigation and no collection calls, and <Subject 2> agrees and starts the calculation.

retention_analysis:
<Subject 1> (appears in [Shot 1], [Shot 2]): fully_preserved - the identity, face, hair and clothing from ldh.png are retained.
<Subject 2> (appears in [Shot 2]): fully_preserved - the identity, face, hair and clothing from xw.png are retained.

detailed_description:
The target video keeps the same live-action, cinematic, realistic bank-interior look with cool ceiling light and a shallow depth of field over the desk.
[Shot 1] A medium close shot frames <Subject 1> (S1), 李大海, leaning forward with one hand flat on the form in front of him. His earlier tension has dropped; he speaks in a lower, tired but steadier male voice at a normal, deliberate pace, <d>[Chinese] 那你给我办理一下线下协商还款吧，算一下我每月需还多少钱，这个期间不要起诉，不要催收了。</d> He taps the paper once with his index finger on each of the last two conditions.
[Shot 2] At 00:09.200, the shot cuts to a medium close shot of <Subject 2> (S2), 小王, on the opposite side. She gives a short, businesslike nod, pulls the form and a printed repayment table toward herself, and speaks in the same clear, even, professional female voice, <d>[Chinese] 好的。我帮您试算一下，请您签字确认。</d> She sets the tip of her pen on the table and starts running down a column of figures, her eyes moving with the pen. The camera holds a static shot as her hand moves steadily to the end of the frame.

overall_soundscape:
Quiet bank-interior room tone with the ventilation hum. Paper slides across the desk, and the soft tap of a pen tip on the tabletop repeats a few times in a steady rhythm.

non_diegetic_music:
A warm piano figure at a slow tempo with a low string note underneath, rising slightly in volume before settling.
```

---

### Segment 15 ｜签字与结尾字幕 · 网点洽谈位

素材：`xw.png`、`ldh.png`

```text
subject_definitions:
<Subject 1> is 小王, the account manager, whose appearance is taken directly from the reference image xw.png; her face, hair and clothing follow that image exactly.
<Subject 2> is 李大海, whose appearance is taken directly from the reference image ldh.png; his face, hair and clothing follow that image exactly.

summary:
[reference generation] The target video closes the story at the same desk. <Subject 1> hands over the trial result and assures him of follow-up support, <Subject 2> signs the commitment letter, and a closing caption appears over the last shot.

retention_analysis:
<Subject 1> (appears in [Shot 1], [Shot 3]): fully_preserved - the identity, face, hair and clothing from xw.png are retained.
<Subject 2> (appears in [Shot 2], [Shot 3]): fully_preserved - the identity, face, hair and clothing from ldh.png are retained.

detailed_description:
The target video keeps the same live-action, cinematic, realistic bank-interior look, and the final shot brightens slightly as the camera settles.
[Shot 1] A medium close shot frames <Subject 1> (S1), 小王, sliding a printed repayment schedule and the completed form across the desk, a pen laid on top of them. She looks up and speaks in the same clear, even, professional female voice, now a little warmer and slower, <d>[Chinese] 有任何问题随时联系我。</d> She keeps her hand on the schedule until <Subject 2>'s fingers reach it, then withdraws it.
[Shot 2] At 00:03.400, the shot cuts to a close shot of <Subject 2> (S2), 李大海, over the desk. He pulls the form square, picks up the pen, signs his name on the marked line in two slow strokes, replaces the cap and sets the pen down. He exhales once, sits back and pushes the form back across the desk.
[Shot 3] At 00:07.200, the shot cuts to a static medium-wide shot of the consultation corner, both of them seated across the desk as <Subject 1> gathers the documents into a folder. White Chinese characters fade in at the lower third reading "贷款需理性，按时还款很重要。遇到困难时，请及时与银行沟通协商。" The caption holds to the final frame while the two figures stay in place and the camera does not move.

overall_soundscape:
Quiet bank-interior room tone with the ventilation hum underneath. The pen cap clicks, the nib scratches briefly across paper, and the folder closes with a soft slap as the ambience settles into the final seconds.

non_diegetic_music:
A warm piano figure at a slow tempo resolving upward, joined by a sustained low string note that fades out under the closing caption.
```

---

## 六、生成前检查清单

- [ ] Segment 12 台词中的 `XX` / `X年X月` 已替换为实际约定数值（否则 TTS 会读成「叉叉」）。
- [ ] 每段只上传该段角色对应的图片，`subject_definitions` 与图片一一对应，不混入其他角色图。
- [ ] 每段时长填 **15**（整数秒，不带小数），`subject` 编号从 1 开始（已按段独立编号）。
- [ ] 若不需要小刘出镜，删除 Segment 6 的 `[Shot 2]`，把第 1 镜延长到 `00:11.500`、`[Shot 3]` 改为 `00:11.500`（小刘整句仍连续说完，李大海 11.5s 后接话）。
- [ ] 角色形象如需锁定更严，可在生成器中调高参考图权重，但不要往 prompt 里添加外貌描述。
