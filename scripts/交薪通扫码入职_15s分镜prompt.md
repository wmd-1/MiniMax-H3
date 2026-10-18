# 交薪通·扫码入职 —— Ref2VA 分段生成 Prompt（节奏修正版 v2）

- 模式：Ref2VA 全参考（排除 I2VA / T2VA）
- 总时长：100 秒，共 7 段（6×15s + 末尾落板 10s）
- v2 修正：原 6 段方案中"概览→按钮→表单"20s 内容被压进 15s、旁白 6 句超载；现解压为 7 段，旁白按 4 字/秒 + 句间 0.5s 停顿核算，各段均留 2s 以上余量，语速适中
- 节拍与镜头时序严格遵循原剧本顺序，未打乱
- 参考图映射：first_shot.PNG / image2.png ~ image10.png（共 11 张）
- 每段为独立生成 prompt，仅引用该段实际出现的图片，标签在各段内独立编号

## 段落总览

| 段 | 总时序 | 时长 | 内容 | 引用图 | 旁白字数 |
| --- | --- | --- | --- | --- | --- |
| 1 | 0:00–0:15 | 15s | 首帧标题 → 痛点画圈 → 概览推入 | first_shot / image2 / image3 | 35 |
| 2 | 0:15–0:30 | 15s | 聚焦扫码入职 → 新增二维码点击 → 表单前三字段 | image3 / image4 / image5 | 37 |
| 3 | 0:30–0:45 | 15s | 入职部门+批量开卡 → 自定义登记表 | image5 / image6 | 38 |
| 4 | 0:45–1:00 | 15s | 分发页两区域画圈 → 手工新增进入 | image7 / image8 | 32 |
| 5 | 1:00–1:15 | 15s | 字段高亮 → 批量导入 | image8 / image9 | 22 |
| 6 | 1:15–1:30 | 15s | 待入职管理三按钮 → 确认入职点击 | image10 | 20 |
| 7 | 1:30–1:40 | 10s | 拉远 → 品牌落板 → 淡出（无旁白） | first_shot | 0 |

---

## Segment 1（0:00–0:15，15s）

subject_definitions:
<Picture 1> is the opening brand page first_shot.PNG, a Bank of Communications branded white-background landing page, used as the exact first frame of [Shot 1].
<Picture 2> is the pain-point overview page image2.png, a white business page listing the pain points "纸质合同签约慢", "纸质合同保管烦", "纸质合同查找难" and "线下数据采集繁", each with small scene illustrations.
<Picture 3> is the three-step onboarding overview page image3.png, showing three step summaries "扫码入职", "入职审批" and "电子合同".

summary:
[keyframe completion + reference generation] A 15-second formal Chinese product-demo screen-recording segment for 交薪通, a Bank of Communications payroll and HR digital service platform for SMEs, in 16:9. The video opens on <Picture 1> with the title "交薪通·扫码入职" zooming in, then tours the four pain points on <Picture 2> with cursor circle annotations, and ends pushing into <Picture 3>. An off-screen business narrator (S1) speaks Mandarin at a moderate pace.

retention_analysis:
<Picture 1> ([Shot 1] first frame): fully_preserved - the white Bank of Communications brand page layout is retained as the opening frame with only the title overlay added.
<Picture 2> (appears in [Shot 2]): fully_preserved - all four pain-point text blocks and their scene illustrations are retained while the camera moves across them.
<Picture 3> (appears in [Shot 3]): fully_preserved - the full overview page is shown; no area is highlighted yet in this segment.

detailed_description:
The target video is a formal, steady 16:9 screen-capture product-demo recording of a Chinese enterprise web platform, with crisp interface rendering, press-ripple feedback on clicks, slight surrounding dimming during focus, and push/pull transitions instead of static cuts.
[Shot 1] The video begins from <Picture 1>, the white Bank of Communications brand landing page filling the frame. The title text "交薪通·扫码入职" in large dark characters scales gently from 90% to 100% while fading in, centered over the page, fully settled by 00:02. No narration yet; only quiet room tone.
[Shot 2] At 00:02.500, the camera pushes horizontally into <Picture 2>, the pain-point overview page. The lens first shows the whole page, then slowly zooms toward the text "纸质合同签约慢"; the area around it dims slightly and a mouse cursor draws a circle annotation around the text, holding about two seconds. The camera then pans right to "纸质合同保管烦" at about 00:05.000, continues to "纸质合同查找难" at about 00:07.500, and finally to "线下数据采集繁" at about 00:10.000, each receiving the same circle annotation and a two-second hold, the last annotation finishing by 00:12. Meanwhile the off-screen narrator (S1), a calm professional Mandarin business voice, speaks first stating each pain and then the solution, at a moderate pace with a clear half-second pause between sentences, <d>[Chinese] 传统入职，纸质合同签约慢。保管查找都麻烦。线下采集数据也繁琐。交薪通用三步解决。</d> The narration ends at about 00:13.500, leaving a brief quiet beat.
[Shot 3] At 00:12.000, the camera pushes vertically into <Picture 3>, the three-step onboarding overview page, showing "扫码入职", "入职审批" and "电子合同" in full view with safe margins and large clear text. The final second holds silently on the full overview page without any highlight yet.

overall_soundscape: Quiet office room tone with a faint interface ambience; a soft cursor tick accompanies each circle annotation.
non_diegetic_music: N/A

---

## Segment 2（0:15–0:30，15s）

subject_definitions:
<Picture 1> is the three-step onboarding overview page image3.png, showing "扫码入职", "入职审批" and "电子合同".
<Picture 2> is the onboarding-management page image4.png, showing the page layout with the "新增二维码" button.
<Picture 3> is the QR-code configuration form image5.png, with the fields "二维码名称", "入职登记表" and "入职部门".

summary:
[keyframe completion + reference generation] A 15-second formal Chinese screen-recording demo segment for 交薪通, continuing the scan-code onboarding flow in 16:9. The camera focuses on the "扫码入职" step of <Picture 1>, pushes into <Picture 2> and clicks the "新增二维码" button with a ripple, then moves through the first three fields of <Picture 3>. The off-screen business narrator (S1) speaks Mandarin.

retention_analysis:
<Picture 1> (appears in [Shot 1]): partially_preserved - the page is retained but only the "扫码入职" step is highlighted while the other two steps stay dimmed.
<Picture 2> (appears in [Shot 2]): fully_preserved - the management page layout and the "新增二维码" button are retained during hover and click.
<Picture 3> (appears in [Shot 3]): fully_preserved - the form fields and their current values are retained while the camera focuses on each in turn.

detailed_description:
The target video is a formal, steady 16:9 screen-capture product-demo recording of a Chinese enterprise web platform, with crisp interface rendering, hover glow, press-ripple click feedback, surrounding dimming during focus, and push/pull transitions.
[Shot 1] The video begins from <Picture 1>, the three-step overview page in full view. The camera pushes slightly toward the "扫码入职" step; that area enlarges gently, its surroundings dim, and a mouse cursor draws a circle annotation around it while "入职审批" and "电子合同" remain dimmed and unfocused. This focus holds about four seconds, until 00:04. The off-screen narrator (S1), a calm professional Mandarin business voice, states the segment's focus evenly, <d>[Chinese] 本片聚焦第一步，扫码入职。</d>
[Shot 2] At 00:04.000, the camera pulls out horizontally and pushes into <Picture 2>, the onboarding-management page. The lens zooms toward the "新增二维码" button; the cursor moves onto it at about 00:05.000 and a soft hover glow appears, then the cursor clicks the button and a press-ripple feedback spreads from the click point at about 00:07.000. The narrator (S1) continues, <d>[Chinese] HR进入入职管理页面。点击新增二维码。</d>
[Shot 3] At 00:09.000, the camera pushes vertically into <Picture 3>, the QR-code configuration form. The camera first focuses on the "二维码名称" input field for about 1.5 seconds, then pans to the "入职登记表" dropdown area at about 00:10.500, and moves to the "入职部门" area at about 00:12.000, each field held for about 1.5 seconds with a gentle focus dim. A small caption "第一步：创建入职二维码" floats up at the bottom of the frame at about 00:09.500. Throughout the segment the narrator (S1) speaks first stating each operation's purpose and then the action, never reading the on-screen text verbatim, <d>[Chinese] 填写名称，选择登记表。指定入职部门。</d> The narration ends by about 00:14, and the frame holds quietly on the focused "入职部门" field to the end.

overall_soundscape: Quiet office room tone; soft click ticks on the button press.
non_diegetic_music: N/A

---

## Segment 3（0:30–0:45，15s）

subject_definitions:
<Picture 1> is the QR-code configuration form image5.png, with the field "入职部门" and the option "同步批量开卡".
<Picture 2> is the custom onboarding registration form page image6.png, showing the text "12大类、80小项人事信息" with configurable items and required-field settings, plus the "新增登记表" button.

summary:
[keyframe completion + reference generation] A 15-second formal Chinese screen-recording demo segment for 交薪通, 16:9. The camera finishes the configuration form on <Picture 1> by checking "同步批量开卡", then slides into the custom registration form <Picture 2>, circles the capability text and clicks "新增登记表". The off-screen business narrator (S1) speaks Mandarin.

retention_analysis:
<Picture 1> (appears in [Shot 1]): fully_preserved - the "入职部门" field and the "同步批量开卡" option are retained during the checkbox check and circle annotation.
<Picture 2> (appears in [Shot 2]): fully_preserved - the "12大类、80小项人事信息" text, the configurable item list and the "新增登记表" button are retained throughout the shot.

detailed_description:
The target video is a formal, steady 16:9 screen-capture product-demo recording of a Chinese enterprise web platform, with crisp interface rendering, press-ripple click feedback, slight surrounding dimming during focus, and push/pull transitions.
[Shot 1] The video begins from <Picture 1>, the QR-code configuration form with the "入职部门" field in focus. The camera pans to the "同步批量开卡" option at about 00:01.000; the cursor clicks the checkbox, a check animation plays, and a circle annotation is drawn around the option while the surroundings dim slightly. The off-screen narrator (S1), a calm professional Mandarin business voice, says, <d>[Chinese] 还能同步批量开卡。</d>
[Shot 2] At 00:04.000, the camera slides horizontally into <Picture 2>, the custom onboarding registration form page. The camera pushes toward the text "12大类、80小项人事信息"; the surroundings dim and a mouse cursor draws a circle annotation around it, holding about three seconds until 00:07.500. The camera then pulls back slightly to show the full registration form with its configurable categories at about 00:08.000, and at about 00:10.500 the cursor moves to the "新增登记表" button and clicks it with a press-ripple feedback. A small caption "第二步：自定义入职登记表" floats up at the bottom of the frame at about 00:04.500. The narrator (S1) continues at a moderate pace with natural half-second pauses, <d>[Chinese] 第二步，自定义登记表。十二大类，八十小项。按需设置必填项。</d> The narration ends by about 00:14, and the frame holds on the updated form for the final second.

overall_soundscape: Quiet office room tone; soft click ticks on the checkbox press and the button press.
non_diegetic_music: N/A

---

## Segment 4（0:45–1:00，15s）

subject_definitions:
<Picture 1> is the print-QR-code and send-link page image7.png, showing the "下载入职二维码" area and the "复制链接" area.
<Picture 2> is the manual personnel-add page image8.png, showing the single-entry interface for adding a pending employee with a "新增人员" button and form fields.

summary:
[keyframe completion + reference generation] A 15-second formal Chinese screen-recording demo segment for 交薪通, 16:9. The camera annotates both distribution areas on <Picture 1>, then slides into the manual-add page <Picture 2> and zooms toward the "新增人员" button. The off-screen business narrator (S1) speaks Mandarin.

retention_analysis:
<Picture 1> (appears in [Shot 1]): fully_preserved - the page is shown in full view with both the "下载入职二维码" and "复制链接" areas retained and annotated in turn.
<Picture 2> (appears in [Shot 2]): fully_preserved - the "新增人员" button and the form fields with their values are retained during the zoom-in.

detailed_description:
The target video is a formal, steady 16:9 screen-capture product-demo recording of a Chinese enterprise web platform, with crisp interface rendering, press-ripple click feedback, slight surrounding dimming during focus, and push/pull transitions instead of static cuts.
[Shot 1] The video begins with a vertical push into <Picture 1>, the print-QR-code and send-link page, first showing the whole page. A small caption "第三步：分发二维码或链接" floats up at the bottom of the frame at about 00:01.000. At about 00:02.500 the cursor moves to the "下载入职二维码" area and draws a circle annotation around it while the surroundings dim slightly, holding about two and a half seconds. At about 00:06.000 the cursor moves to the "复制链接" area and circles it, holding until about 00:09.000. The off-screen narrator (S1), a calm professional Mandarin business voice at a moderate pace, states the purpose before each action with natural half-second pauses, <d>[Chinese] 第三步，分发二维码。可以下载打印。也可以复制链接发送。员工扫码就能填信息。</d> The narration ends by about 00:09.500.
[Shot 2] At 00:10.000, the camera slides horizontally into <Picture 2>, the manual personnel-add page. The camera zooms toward the "新增人员" button, and the cursor moves onto the first form field, its border lighting up in a highlight as the segment ends. The narrator (S1) introduces the alternative path evenly, <d>[Chinese] 除了扫码，也支持手工添加。</d>

overall_soundscape: Quiet office room tone; no clicks in this segment, only soft cursor movement.
non_diegetic_music: N/A

---

## Segment 5（1:00–1:15，15s）

subject_definitions:
<Picture 1> is the manual personnel-add page image8.png, showing the single-entry interface for adding a pending employee with form fields.
<Picture 2> is the batch-import page image9.png, showing the import flow with a "下载导入模板" button and template upload.

summary:
[keyframe completion + reference generation] A 15-second formal Chinese screen-recording demo segment for 交薪通, 16:9. The camera tours the highlighted form fields of <Picture 1>, then quickly slides out into the batch-import page <Picture 2> and clicks "下载导入模板". The off-screen business narrator (S1) speaks Mandarin.

retention_analysis:
<Picture 1> (appears in [Shot 1]): fully_preserved - the "新增人员" button and the form fields with their values are retained during the border-highlight tour.
<Picture 2> (appears in [Shot 2]): fully_preserved - the import page layout and the "下载导入模板" button are retained during hover and click.

detailed_description:
The target video is a formal, steady 16:9 screen-capture product-demo recording of a Chinese enterprise web platform, with crisp interface rendering, press-ripple click feedback, slight surrounding dimming during focus, and push/pull transitions instead of static cuts.
[Shot 1] The video begins from <Picture 1>, the manual personnel-add page with the "新增人员" button above the form. The cursor moves down the form fields one by one; each field's border lights up in a highlight as the cursor reaches it and dims as it leaves, the steady tour continuing from 00:00 until about 00:06.500. The off-screen narrator (S1), a calm professional Mandarin business voice, speaks with natural pauses, <d>[Chinese] 除了扫码，也支持手工添加。单条录入或批量导入都行。</d>
[Shot 2] At 00:07.000, the camera quickly slides out horizontally and cuts into <Picture 2>, the batch-import page. The camera zooms toward the "下载导入模板" button, the cursor clicks it with a press feedback at about 00:10.000, and a small caption "也支持手工或批量添加" floats up at the bottom of the frame at about 00:10.500. The frame holds quietly on the import page for the remaining seconds, with no further narration.

overall_soundscape: Quiet office room tone; a soft click tick on the template-button press.
non_diegetic_music: N/A

---

## Segment 6（1:15–1:30，15s）

subject_definitions:
<Picture 1> is the pending-employee management page image10.png, showing the management operations "调整入职日期", "确认入职" and "放弃入职" for pending onboarding staff.

summary:
[keyframe completion + reference generation] A 15-second formal Chinese screen-recording demo segment for 交薪通, 16:9. The camera pushes into the pending-employee management page <Picture 1> and annotates the three operation buttons in turn, then clicks "确认入职" with a ripple. The off-screen business narrator (S1) speaks Mandarin.

retention_analysis:
<Picture 1> (appears in [Shot 1]): fully_preserved - the management page layout and all three operation buttons "调整入职日期", "确认入职" and "放弃入职" are retained throughout the shot.

detailed_description:
The target video is a formal, steady 16:9 screen-capture product-demo recording of a Chinese enterprise web platform, with crisp interface rendering, press-ripple click feedback, slight surrounding dimming during focus, and push/pull transitions.
[Shot 1] The video begins with a vertical push into <Picture 1>, the pending-employee management page, the lens zooming toward the operation button area by 00:02.000. At about 00:03.000 the cursor moves to the "调整入职日期" button and draws a circle annotation around it while the surroundings dim slightly, holding about two and a half seconds. At about 00:06.000 the cursor moves to the "确认入职" button and circles it, again holding about two and a half seconds. At about 00:09.000 the cursor moves to the "放弃入职" button and circles it for another two-second hold. At about 00:11.500 the cursor returns to the "确认入职" button and clicks it; a press-ripple feedback spreads from the click point and the button state updates. The frame holds on the updated page for the last two seconds. Throughout the segment the off-screen narrator (S1), a calm professional Mandarin business voice at a moderate pace, states the purpose before each action with natural half-second pauses, <d>[Chinese] 待入职的员工可以线上管理。调整日期、确认或放弃。扫码入职，三步搞定。</d> The narration ends by about 00:12, leaving the ripple and the hold in silence.

overall_soundscape: Quiet office room tone; a soft click tick on the "确认入职" press.
non_diegetic_music: N/A

---

## Segment 7（1:30–1:40，10s）

subject_definitions:
<Picture 1> is the opening brand page first_shot.PNG, a Bank of Communications branded white-background landing page with the "交薪通" name in plain typesetting.

summary:
[keyframe completion] A 10-second formal Chinese closing segment for the 交薪通 product demo in 16:9. The camera slowly pulls back as <Picture 1> fades in as a stable brand end board, holds quietly, and gently fades out. No narration.

retention_analysis:
<Picture 1> ([Shot 1] keyframe): fully_preserved - the white Bank of Communications brand page is retained as the end board with no added overlays beyond a gentle fade.

detailed_description:
The target video is a formal, steady 16:9 closing shot in the same screen-recording visual style as the rest of the demo, with safe margins, large clear text, no exaggerated glow, and a calm restrained pace.
[Shot 1] The video opens with a slow zoom-out over a softly brightened blurred interface; the white Bank of Communications brand page <Picture 1> fades in gradually as the camera pulls back, fully sharp and centered by 00:03. The brand page then holds as a stable end board, quiet and steady, from 00:03 to about 00:07, with no camera movement and no overlaid text beyond what the page itself contains; the "交薪通" name appears only in plain typesetting as printed on the page, with no imitation of official graphic logos or script wordmarks. From 00:07 the frame gently fades out over the final three seconds, completing the video at 00:10. No narration or voice is heard at any point in this segment.

overall_soundscape: Quiet room tone only, with no interface sounds in the closing shot.
non_diegetic_music: N/A
