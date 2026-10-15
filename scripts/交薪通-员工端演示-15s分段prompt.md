# 交薪通员工端操作演示 — 15s 分段视频生成 Prompt（Ref2VA 全参考模式）

- 总时长 **1:44（104s）**，按时序切分为 **9 段**，每段 ≤15s，顺序与原文完全一致。段落时长按内容密度配平（旁白字数 × 动作节点 + 阅读停顿），不注水也不赶拍；第 2/6 段旁白与屏幕最密，用满 15s，第 7/9 段内容轻，保留 8s/6s。
- 模式：Ref2VA（全参考）。每段 prompt 独立自包含，参考图在各段内重新编号为 `<Picture N>`，与该段【使用图片】对应。
- 旁白统一为 S1（中文商务旁白，沉稳适中语速），不添加背景音乐，屏幕文字处留阅读停顿。
- 全局约束已写入每段：不展示竞品、不仿造官方 Logo（"交薪通"仅普通排版）、image7 二维码模糊为演示数据、无虚假 HUD。

| 段 | 时长 | 覆盖时段 | 内容 | 使用图片 |
|---|---|---|---|---|
| 1 | 13s | 0:00–0:13 | 首帧标题 + 渠道登记登录 | first_shot, image4, image5 |
| 2 | 15s | 0:13–0:28 | 了解交薪通 / 联系客户经理 | image6, image7 |
| 3 | 12s | 0:28–0:40 | 扫码入职：验证手机号 + 填写 | image8, image9 |
| 4 | 10s | 0:40–0:50 | 保存 / 提交提示 | image9 |
| 5 | 12s | 0:50–1:02 | 管理员录入花名册 | image133 |
| 6 | 15s | 1:02–1:17 | 微信搜索小程序 → 登录 → 首页 | image134, image135, image1, image136 |
| 7 | 8s | 1:17–1:25 | 协议更新需先阅读 | image1 |
| 8 | 13s | 1:25–1:38 | 首页 / 切换企业 | image2, image3 |
| 9 | 6s | 1:38–1:44 | 结尾预告淡出 | image2 |

---

## 第 1 段（0:00–0:13，13s）首帧标题 + 渠道登记登录

【使用图片】`<Picture 1>` = first_shot.PNG（开场首帧）｜`<Picture 2>` = image4.png（外部渠道登记第一页）｜`<Picture 3>` = image5.png（外部渠道登录第二页）

```text
subject_definitions:
<Picture 1> is the first frame of the target video, a supplied screenshot (first_shot.PNG) serving as the opening still of a vertical 9:16 product-demo video for the 交薪通 employee app.
<Picture 2> is a screenshot of the 交薪通 external-channel registration first page, with a phone-number input field and a "获取验证码" button, used as the concrete frame the camera focuses into.
<Picture 3> is a screenshot of the 交薪通 external-channel second page with a verification-code input and a login button, pushed in horizontally as the next screen.

summary:
[keyframe completion + reference generation] The target video is a 13-second vertical 9:16 product-demo segment for the 交薪通 employee app, formal, steady and clear. It opens on the supplied still <Picture 1> with a title card, then pushes into <Picture 2> for phone-number registration and cuts to <Picture 3> for code login. A Chinese business narrator (S1) speaks in a measured pace. No background music.

retention_analysis:
<Picture 1> ([Shot 1] first frame): fully_preserved - the supplied screenshot remains a static still with only the title text animated over it.
<Picture 2> ([Shot 2] focus target): fully_preserved - the registration page layout, phone-number field and "获取验证码" button are retained.
<Picture 3> ([Shot 2] pushed-in screen): fully_preserved - the verification-code page layout and login button are retained.

detailed_description:
The target video is a formal vertical 9:16 UI-demo segment with clean large typography, generous safe margins, realistic cursor interaction (press feedback and click ripples), and push/pull transitions instead of static cuts.
[Shot 1] The video opens on the static still <Picture 1>, held motionless as the opening frame. At about 00:00.500, the title text "快速上手与扫码入职" pops in from the bottom edge with a slight scale-down settle and holds, large, sharp and legible. No narration in this shot.
[Shot 2] At 00:03.000, the whole frame zooms in smoothly from a global view and converges onto <Picture 2>, the external-channel registration page, settling on its phone-number input field while the surrounding edges dim slightly. A cursor moves in and clicks the input area with a soft press and ripple; the on-screen keyboard slides up from the bottom; a phone number types in digit by digit. The cursor then clicks the "获取验证码" button, which shows a press-down state and a subtle ripple. At about 00:08.000, the frame pushes out horizontally and <Picture 3>, the verification-code page, slides in from the right. The cursor clicks the code input, the code fills in, and the cursor clicks the login button with a clear press feedback. A caption "交薪通渠道登记" appears in clean large type. The narrator (S1), a steady professional Chinese business voice at a moderate pace, says <d>[Chinese] 在外部渠道看到交薪通。</d> then <d>[Chinese] 点击链接进入登记页。</d> and finally <d>[Chinese] 用手机号和验证码登录。</d>, leaving a short reading pause after each caption appears.

overall_soundscape:
Quiet room tone only; soft UI click sounds and a gentle keyboard tick accompany each cursor interaction.

non_diegetic_music:
N/A
```

---

## 第 2 段（0:13–0:28，15s）了解交薪通 / 联系客户经理

【使用图片】`<Picture 1>` = image6.png（了解交薪通介绍页）｜`<Picture 2>` = image7.png（联系客户经理二维码弹窗，二维码模糊）

```text
subject_definitions:
<Picture 1> is a screenshot of the "了解交薪通" product-introduction page, used as the concrete frame the camera pushes into, with an introduction button, an enterprise-name input and a "联系客户经理" button.
<Picture 2> is a screenshot of the customer-manager contact popup containing a QR code; the QR-code area must be rendered blurred as demonstration data and must never appear as a scannable real code.

summary:
[keyframe completion + reference generation] The target video is a 15-second vertical 9:16 product-demo segment for 交薪通. The camera pushes into <Picture 1>, demonstrates scrolling the introduction feed, typing an enterprise name, and opening the contact popup <Picture 2> whose QR code stays blurred. A Chinese business narrator (S1) speaks in a measured pace. No background music.

retention_analysis:
<Picture 1> ([Shot 1] focus target): fully_preserved - the introduction page layout, buttons and input field are retained.
<Picture 2> ([Shot 2] popup content): partially_preserved - the popup layout is retained, but the QR-code area is intentionally blurred into demonstration data and never shown sharp.

detailed_description:
The target video is a formal vertical 9:16 UI-demo segment with clean typography, cursor press feedback and ripples, staggered reveal on scroll, and push transitions.
[Shot 1] The frame pushes in smoothly and converges onto <Picture 1>, the "了解交薪通" introduction page, its edges dimming slightly. A cursor moves to the "了解交薪通" button and clicks it; the button enlarges slightly with a ripple. The page then scrolls vertically and the introduction information blocks float in one after another, each block holding clearly legible for at least two seconds as the feed passes. At about 00:07.500, the view cuts back to the input area of <Picture 1>; the cursor clicks the enterprise-name input and the name is typed in character by character. The cursor then clicks the "联系客户经理" button with a press ripple. At about 00:11.500, a popup rises from the bottom of the screen showing <Picture 2>, the customer-manager contact card, with its QR-code area kept blurred as demonstration data; the popup settles and stays clearly visible through the end. A caption "了解交薪通 / 联系客户经理" appears in large clean type. The narrator (S1), a steady professional Chinese business voice at a moderate pace, says <d>[Chinese] 想了解产品，点'了解交薪通'。</d> then <d>[Chinese] 想咨询，输入企业名称。</d> then <d>[Chinese] 点'联系客户经理'扫码沟通。</d> and finally <d>[Chinese] 二维码已做演示处理。</d>, pausing briefly as each on-screen element settles.

overall_soundscape:
Quiet room tone; soft UI clicks, a light scroll swish, and a gentle popup-rise whoosh.

non_diegetic_music:
N/A
```

---

## 第 3 段（0:28–0:40，12s）扫码入职：验证手机号 + 填写

【使用图片】`<Picture 1>` = image8.png（扫码入职验证手机号页）｜`<Picture 2>` = image9.png（入职申请信息填写页）

```text
subject_definitions:
<Picture 1> is a screenshot of the 交薪通 scan-to-onboard phone-verification page, with a verification-code input and a "下一步" button, used as the concrete frame after the scan animation.
<Picture 2> is a screenshot of the onboarding application form page, used as the concrete frame that slides in vertically at the end.

summary:
[keyframe completion + reference generation] The target video is a 12-second vertical 9:16 product-demo segment for 交薪通's scan-to-onboard flow. A simulated scan animation leads into <Picture 1> for phone verification, then the page slides into <Picture 2> where form fields light up in sequence. A Chinese business narrator (S1) speaks in a measured pace. No background music.

retention_analysis:
<Picture 1> ([Shot 1] focus target): fully_preserved - the verification page layout, code input and "下一步" button are retained.
<Picture 2> ([Shot 2] slid-in page): fully_preserved - the onboarding form layout and its fields are retained.

detailed_description:
The target video is a formal vertical 9:16 UI-demo segment with clean typography, cursor press feedback and ripples, and vertical push/slide transitions.
[Shot 1] The frame shows a simulated QR scan: a bright horizontal scanline sweeps slowly from top to bottom across the frame. At about 00:03.000, the scan finishes and the frame cuts into <Picture 1>, the phone-verification page of the scan-to-onboard flow. The cursor clicks the verification-code input with a press feedback; digits roll and fill into the field one by one. The cursor then clicks the "下一步" button, which shows a clear press-down state. At about 00:07.500, the page slides vertically and <Picture 2>, the onboarding application form, glides in from the bottom. On <Picture 2>, the form fields light up one after another in order, each highlighted field guiding the eye to fill in personal information and materials. A caption "扫码入职" appears in large clean type. The narrator (S1), a steady professional Chinese business voice at a moderate pace, says <d>[Chinese] 待入职的员工，扫码进入入职流程。</d> then <d>[Chinese] 先验证手机号。</d> and finally <d>[Chinese] 再填写入职信息和材料。</d>, leaving a short pause while each field lights up.

overall_soundscape:
Quiet room tone; a soft scan sweep tone, UI clicks, a light digit-roll tick, and a gentle page-slide whoosh.

non_diegetic_music:
N/A
```

---

## 第 4 段（0:40–0:50，10s）保存 / 提交提示

【使用图片】`<Picture 1>` = image9.png（入职申请信息填写页）

```text
subject_definitions:
<Picture 1> is a screenshot of the onboarding application form page, held on screen with a "保存" button and a "提交" button, used as the concrete focus target of this segment.

summary:
[keyframe completion + reference generation] The target video is a 10-second vertical 9:16 product-demo segment for 交薪通. It holds on <Picture 1> and pushes in twice, first to the "保存" button area, then to the "提交" button, explaining the save-versus-submit rule. A Chinese business narrator (S1) speaks in a measured pace. No background music.

retention_analysis:
<Picture 1> ([Shot 1] held page and focus target): fully_preserved - the form layout, the "保存" button and the "提交" button are retained.

detailed_description:
The target video is a formal vertical 9:16 UI-demo segment with clean typography and smooth push-in focus with slightly dimmed surroundings.
[Shot 1] The frame stays on <Picture 1>, the onboarding application form, holding steady for a moment so the page is clearly readable. The camera then pushes in gently and focuses on the "保存" button area; a cursor moves in and hovers, and the button takes on a soft glow under the hover. At about 00:05.000, the camera pushes in further toward the "提交" button, the surrounding form dimming slightly as the button becomes the clear focal point. A caption "保存可继续编辑，提交后不可改" appears in large clean type near the buttons. The narrator (S1), a steady professional Chinese business voice at a moderate pace, says <d>[Chinese] 注意，保存后还能继续编辑。</d> then <d>[Chinese] 提交后就不能再修改了。</d>, pausing between the two lines so the on-screen caption can be read.

overall_soundscape:
Quiet room tone; a subtle hover blip and a soft focus-push whoosh.

non_diegetic_music:
N/A
```

---

## 第 5 段（0:50–1:02，12s）管理员录入花名册

【使用图片】`<Picture 1>` = image133.png（管理员网页录入员工花名册界面）

```text
subject_definitions:
<Picture 1> is a screenshot of the administrator's web-based employee roster (花名册) page, used as the concrete frame pushed in from the right, with a roster table, an add button, and a form modal containing name, phone-number and ID-number fields.

summary:
[keyframe completion + reference generation] The target video is a 12-second vertical 9:16 product-demo segment for 交薪通. The previous frame slides out to the left and <Picture 1> pushes in from the right without any rotation, showing an administrator entering an employee into the roster via a form modal. A Chinese business narrator (S1) speaks in a measured pace. No background music.

retention_analysis:
<Picture 1> ([Shot 1] pushed-in page): fully_preserved - the roster page layout, add button, form modal and its name, phone and ID fields are retained.

detailed_description:
The target video is a formal vertical 9:16 UI-demo segment with clean typography, cursor press feedback and field-focus highlight rings.
[Shot 1] The frame performs a transition: the current view slides out to the left, and <Picture 1>, the administrator's web roster page, pushes in from the right in a flat, upright motion with no rotation. The scene simulates an administrator operating on the web page. The cursor moves to the roster's add (新增) button and clicks it with a press feedback; at about 00:04.000, a form modal slides in from the right side of the screen. The cursor fills the fields in sequence: first the 姓名 (name) field, then the 手机号 (phone number) field, then the 身份证 (ID number) field. Each time a field gains focus, its border lights up in a clear highlight before the characters are typed in. A caption "第一步：将员工录入花名册" appears in large clean type at the top. The narrator (S1), a steady professional Chinese business voice at a moderate pace, says <d>[Chinese] 员工要登录，管理员先做准备。</d> then <d>[Chinese] 在网页花名册录入员工信息。</d> and finally <d>[Chinese] 姓名、手机号、身份证都要填。</d>, pausing briefly as each field lights up.

overall_soundscape:
Quiet office-like room tone; soft UI clicks and a gentle modal-slide whoosh.

non_diegetic_music:
N/A
```

---

## 第 6 段（1:02–1:17，15s）微信搜索小程序 → 登录 → 首页

【使用图片】`<Picture 1>` = image134.png（微信搜索交通银行小程序页）｜`<Picture 2>` = image135.png（小程序内交薪通入口）｜`<Picture 3>` = image1.png（交薪通小程序登录页）｜`<Picture 4>` = image136.png（员工登录交薪通后的页面）

```text
subject_definitions:
<Picture 1> is a screenshot of the WeChat search page where "交通银行" is searched to find the mini program, used as the concrete frame after the zoom-through transition back to the phone.
<Picture 2> is a screenshot of the mini program page containing the 交薪通 entry, pushed in from the right.
<Picture 3> is a screenshot of the 交薪通 mini-program login page with a phone-number input, a verification-code input and a login button, pushed in next.
<Picture 4> is a screenshot of the employee's logged-in 交薪通 home page, popping in at the end.

summary:
[keyframe completion + reference generation] The target video is a 15-second vertical 9:16 product-demo segment for 交薪通. After a zoom-through transition back to the phone, it shows the WeChat search <Picture 1>, the mini-program entry <Picture 2>, the login page <Picture 3>, and the logged-in home <Picture 4> in strict order. A Chinese business narrator (S1) speaks in a measured pace. No background music.

retention_analysis:
<Picture 1> ([Shot 1] search page): fully_preserved - the WeChat search page layout and search box are retained.
<Picture 2> ([Shot 2] entry page): fully_preserved - the mini-program page and the 交薪通 entry are retained.
<Picture 3> ([Shot 3] login page): fully_preserved - the login page layout, inputs and login button are retained.
<Picture 4> ([Shot 3] home page): fully_preserved - the logged-in home layout is retained.

detailed_description:
The target video is a formal vertical 9:16 UI-demo segment with clean typography, cursor press feedback and ripples, staggered list reveals, and push/pull transitions.
[Shot 1] The frame zooms through a scale transition back onto the phone screen, landing on <Picture 1>, the WeChat search page. The cursor clicks the search box with a press feedback; the keyboard rises; the text "交通银行" types in; the search-result list floats up from below, items appearing one after another. At about 00:05.500, the cursor clicks the mini-program icon and <Picture 2>, the mini-program page, pushes in from the right. The cursor clicks the "交薪通" entry with a press ripple. At about 00:09.000, <Picture 3>, the login page, pushes in. The cursor clicks the phone-number input, the number fills in, the verification code rolls in, and the cursor clicks the login button with a clear press feedback. At about 00:13.000, <Picture 4>, the logged-in home page, pops in with a soft scale settle and holds through the end. A caption "登录交薪通" appears in large clean type. The narrator (S1), a steady professional Chinese business voice at a moderate pace, says <d>[Chinese] 录入完成后，员工打开微信。</d> then <d>[Chinese] 搜索交通银行小程序。</d> then <d>[Chinese] 找到交薪通入口。</d> and finally <d>[Chinese] 用手机号和验证码登录。</d>, pausing briefly at each screen change.

overall_soundscape:
Quiet room tone; soft UI clicks, keyboard ticks, a list-rise swish and a gentle push-in whoosh.

non_diegetic_music:
N/A
```

---

## 第 7 段（1:17–1:25，8s）协议更新需先阅读

【使用图片】`<Picture 1>` = image1.png（交薪通小程序登录页，含协议更新提示区域）

```text
subject_definitions:
<Picture 1> is a screenshot of the 交薪通 login page containing the agreement-update prompt area with a "阅读协议" action, used as the concrete focus target.

summary:
[keyframe completion + reference generation] The target video is an 8-second vertical 9:16 product-demo segment for 交薪通. It pushes into <Picture 1>'s agreement-update area, where a prompt box pops in from the top and the cursor clicks "阅读协议". A Chinese business narrator (S1) speaks in a measured pace. No background music.

retention_analysis:
<Picture 1> ([Shot 1] focus target): fully_preserved - the login page and its agreement-update prompt area are retained.

detailed_description:
The target video is a formal vertical 9:16 UI-demo segment with clean typography and a smooth push-in focus with slightly dimmed surroundings.
[Shot 1] The frame starts on <Picture 1>, the 交薪通 login page, then pushes in smoothly and focuses on the agreement-update prompt area near the login controls. At about 00:02.000, the prompt box pops in from the top with a soft settle, clearly legible. The cursor moves to the "阅读协议" action and clicks it with a press feedback and a subtle ripple. A caption "协议更新需先阅读" appears in large clean type. The narrator (S1), a steady professional Chinese business voice at a moderate pace, says <d>[Chinese] 如果协议有更新。</d> then <d>[Chinese] 要先阅读变更协议才能登录。</d>, pausing between the two lines so the caption can be read.

overall_soundscape:
Quiet room tone; a soft popup settle and a gentle UI click.

non_diegetic_music:
N/A
```

---

## 第 8 段（1:25–1:38，13s）首页 / 切换企业

【使用图片】`<Picture 1>` = image2.png（交薪通首页应用入口全景）｜`<Picture 2>` = image3.png（顶部企业名称切换下拉菜单）

```text
subject_definitions:
<Picture 1> is a screenshot of the 交薪通 home page showing the top company-name bar and the app entry area below it, used as the concrete frame this segment explores.
<Picture 2> is a screenshot of the enterprise-switch dropdown menu opened from the top company name, appearing when the menu opens.

summary:
[keyframe completion + reference generation] The target video is a 13-second vertical 9:16 product-demo segment for 交薪通. It shows the <Picture 1> home-page panorama with a top-down reveal of the modules, then opens the enterprise-switch dropdown <Picture 2> and switches companies. A Chinese business narrator (S1) speaks in a measured pace. No background music.

retention_analysis:
<Picture 1> ([Shot 1] panorama): fully_preserved - the home page layout, top company-name bar and app entry modules are retained.
<Picture 2> ([Shot 1] dropdown): fully_preserved - the dropdown menu layout and the enterprise entries are retained.

detailed_description:
The target video is a formal vertical 9:16 UI-demo segment with clean typography, cursor press feedback and ripples, and staggered module reveals.
[Shot 1] The frame opens on the <Picture 1> home-page panorama. The camera pushes down vertically from the top app area, and the modules appear one after another as the view descends, each module clearly visible in turn. At about 00:06.000, the cursor moves to the company name at the top of <Picture 1> and clicks it with a press feedback; the dropdown menu opens, corresponding to <Picture 2>, sliding down with a soft settle under the company-name bar. At about 00:09.000, the cursor clicks another enterprise in the dropdown; the click shows a press ripple and the enterprise switches. A caption "首页 / 切换企业" appears in large clean type. The narrator (S1), a steady professional Chinese business voice at a moderate pace, says <d>[Chinese] 登录后进入首页。</d> then <d>[Chinese] 员工、假勤、协同办公都能用。</d> and finally <d>[Chinese] 身兼多企的，点顶部切换企业。</d>, pausing briefly as each module is revealed and again while the menu is open.

overall_soundscape:
Quiet room tone; a soft descending reveal swish, UI clicks and a gentle dropdown settle.

non_diegetic_music:
N/A
```

---

## 第 9 段（1:38–1:44，6s）结尾预告淡出

【使用图片】`<Picture 1>` = image2.png（交薪通首页全景）

```text
subject_definitions:
<Picture 1> is a screenshot of the 交薪通 home page panorama, used as the concrete frame that zooms and fades out at the end of the video.

summary:
[keyframe completion + reference generation] The target video is a 6-second vertical 9:16 closing segment for 交薪通. It holds briefly on <Picture 1>, shows the next-episode caption, and zoom-fades out. A Chinese business narrator (S1) speaks in a measured pace. No background music.

retention_analysis:
<Picture 1> ([Shot 1] held frame): fully_preserved - the home page panorama is retained through the fade.

detailed_description:
The target video is a formal vertical 9:16 UI-demo closing segment with clean large typography and generous safe margins.
[Shot 1] The frame opens on <Picture 1>, the 交薪通 home page panorama, holding steady for about two seconds. A caption "下一集：首页与个人中心" appears in large clean type and stays legible. At about 00:03.500, <Picture 1> zooms out gently and fades, softening to a clean end frame; the caption fades last. The narrator (S1), a steady professional Chinese business voice at a moderate pace, says <d>[Chinese] 后面我们逐个看，每个功能怎么用。</d> and the line completes before the final fade finishes.

overall_soundscape:
Quiet room tone; a soft fade-out breath, no other effects.

non_diegetic_music:
N/A
```
