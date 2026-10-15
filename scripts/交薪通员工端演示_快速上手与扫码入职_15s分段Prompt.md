# 交薪通员工端操作演示「快速上手与扫码入职」— 15s 分段 Ref2VA 生成 Prompt

- 模式：Ref2VA 全参考模式，竖屏 9:16
- 切分为 **8 段，每段固定 15s**（拼接后全片约 2:00）；内容与镜头时序严格遵循原脚本，多出的时长全部用于静帧停留与旁白阅读停顿（语速不过快）
- 所有段间切分点均落在原脚本镜头/子镜头切点，拼接无跳变
- 统一首帧 `first_shot.png` **仅用于第 1 段**作为视频开场首帧；第 2–8 段直接以本段内容画面起帧，保证拼接后画面连续
- 全片无背景音乐；中文商务旁白（S1），语速适中，屏幕文字处留阅读停顿

## 分段总览（原时间轴 → 分段）

| 段 | 原时间轴 | 时长 | 内容 | 参考图 |
| --- | --- | --- | --- | --- |
| 1 | 0:00–0:13（+2s 停留） | 15s | 标题滑入 + 外部渠道登记/登录 | first_shot, image4, image5 |
| 2 | 0:13–0:25（+3s 停留） | 15s | 了解交薪通 + 联系客户经理（二维码模糊） | image6, image7 |
| 3 | 0:25–0:38（+2s 停留） | 15s | 扫码入职：验证手机号 + 填写信息 | image8, image9 |
| 4 | 0:38–0:46（+7s 阅读停顿） | 15s | 保存/提交提示要点 | image9 |
| 5 | 0:46–0:58（+3s 缓推） | 15s | 管理员网页录入花名册 | image133 |
| 6 | 0:58–1:12（+1s 停留） | 15s | 登录交薪通：搜索→入口→登录→成功 | image134, image135, image1, image136 |
| 7 | 1:12–1:27 | 15s | 协议更新需先阅读 + 首页 | image1, image2 |
| 8 | 1:27–1:40（+2s 收尾） | 15s | 切换企业 + 下一集预告过渡 | image3, image2 |

---

## 第 1 段（15s）：标题 + 外部渠道登记与登录

subject_definitions:
<Picture 1> is the unified opening title card (first_shot.png) provided by the user, used as the first frame of the target video.
<Picture 2> is the first page of the external-channel registration flow (image4.png), showing the 交薪通 channel registration page layout.
<Picture 3> is the second page of the external-channel login flow (image5.png), showing the phone-number and verification-code login form.

summary:
[keyframe completion + reference generation] The target video is a vertical 9:16 corporate product-demonstration clip. It opens on <Picture 1> with a Chinese title sliding in, then demonstrates the external-channel registration and verification-code login of the 交薪通 employee mini-program, using <Picture 2> and <Picture 3> as concrete screen anchors, narrated by a steady Chinese business voice (S1).

retention_analysis:
<Picture 1> ([Shot 1] first frame): fully_preserved - the title-card composition is retained as the video's first frame before the animated title takes over.
<Picture 2> ([Shot 2]): fully_preserved - the registration page layout and content are retained during the slow push-in.
<Picture 3> ([Shot 3]): fully_preserved - the verification-code login page is retained during the cross-fade and final hold.

detailed_description:
The target video is a vertical 9:16 corporate product-demonstration clip in a clean, formal business style: flat real UI screens, generous safe margins, large legible captions, no HUD, no exaggerated glow, and the name 交薪通 always rendered as plain text without imitating any official logo.
[Shot 1] The video begins from <Picture 1>, the unified title card held as a static full-frame image. The Chinese title "快速上手与扫码入职" slides up from the bottom edge into the lower third, settles with a slight scale-down snap, and stays locked with a calm reading pause. No narration yet; only quiet room tone.
[Shot 2] At 00:04.000, the title card dissolves into <Picture 2>, the first page of the external-channel registration flow displayed full-frame. The camera pushes in slowly and evenly, keeping every form field readable. A large caption "交薪通渠道登记" is fixed near the top with wide margins. The narrator (S1), a steady Chinese business voice at a moderate pace, says, <d>[Chinese] 在外部渠道看到交薪通。点击链接进入登记页。</d>
[Shot 3] At 00:09.500, a gentle cross-fade brings in <Picture 3>, the second page of the external-channel login showing the phone-number and verification-code fields. The push-in settles and the frame holds on the login page; the caption "交薪通渠道登记" remains. The narrator (S1) continues with a brief reading pause before the line, <d>[Chinese] 用手机号和验证码登录。</d> The frame holds to the end.

overall_soundscape:
Clean studio-quiet room tone throughout, with no ambience effects and no UI sounds.

non_diegetic_music:
N/A

---

## 第 2 段（15s）：了解交薪通 / 联系客户经理

subject_definitions:
<Picture 1> is the 了解交薪通 product-introduction page (image6.png), shown as the video's opening frame.
<Picture 2> is the 联系客户经理 QR-code dialog (image7.png); the QR-code area inside it is blurred and treated as demo data, never shown as a scannable real QR code.

summary:
[keyframe completion + reference generation] The target video is a vertical 9:16 corporate product-demonstration clip. It opens on the product-introduction page <Picture 1> and then cuts to the customer-manager QR-code dialog <Picture 2> with its code area blurred, narrated by a steady Chinese business voice (S1).

retention_analysis:
<Picture 1> ([Shot 1]): fully_preserved - the introduction page layout is retained during the fade-in and hold.
<Picture 2> ([Shot 2]): partially_preserved - the dialog layout is retained, but the QR-code area is blurred as demo data instead of shown as a scannable code.

detailed_description:
The target video is a vertical 9:16 corporate product-demonstration clip in a clean, formal business style: flat real UI screens, generous safe margins, large legible captions, no HUD, no exaggerated glow, and 交薪通 rendered as plain text only.
[Shot 1] The video opens on <Picture 1>, the 了解交薪通 product-introduction page, fading in gently and holding steady for several seconds so the page can be read at leisure. A large caption "了解交薪通" is fixed near the top with wide margins. The narrator (S1), a steady Chinese business voice at a moderate pace, says, <d>[Chinese] 想了解产品，点'了解交薪通'。想咨询，输入企业名称。</d>
[Shot 2] At 00:08.000, the shot cuts to <Picture 2>, the 联系客户经理 dialog floating over a dimmed background; the QR-code area inside the dialog is clearly blurred as demo data and is never presented as a scannable real code. The caption changes to "联系客户经理". The narrator (S1) continues with a short reading pause, <d>[Chinese] 点'联系客户经理'扫码沟通。二维码已做演示处理。</d> The frame holds on the blurred dialog to the end.

overall_soundscape:
Clean studio-quiet room tone throughout, with no ambience effects and no UI sounds.

non_diegetic_music:
N/A

---

## 第 3 段（15s）：扫码入职

subject_definitions:
<Picture 1> is the scan-to-onboard phone-number verification page (image8.png), shown as the video's opening frame, depicting the 手机号验证 step of the onboarding flow.
<Picture 2> is the onboarding application form page (image9.png), showing the 入职申请信息填写 layout.

summary:
[keyframe completion + reference generation] The target video is a vertical 9:16 corporate product-demonstration clip. It opens on the onboarding verification page <Picture 1> with a zoom push-in, then slides in the onboarding form page <Picture 2>, narrated by a steady Chinese business voice (S1).

retention_analysis:
<Picture 1> ([Shot 1]): fully_preserved - the verification page layout is retained during the zoom push-in.
<Picture 2> ([Shot 2]): fully_preserved - the onboarding form page layout is retained during the slide-in and hold.

detailed_description:
The target video is a vertical 9:16 corporate product-demonstration clip in a clean, formal business style: flat real UI screens, generous safe margins, large legible captions, no HUD, no exaggerated glow, and 交薪通 rendered as plain text only.
[Shot 1] The video opens on <Picture 1>, the scan-to-onboard phone-number verification page displayed full-frame. The camera zooms in smoothly and moderately, keeping the verification fields centered and readable. A large caption "扫码入职" is fixed near the top with wide margins. The narrator (S1), a steady Chinese business voice at a moderate pace, says, <d>[Chinese] 待入职的员工，扫码进入入职流程。先验证手机号。</d>
[Shot 2] At 00:08.000, <Picture 2>, the onboarding application form page, slides in from the right and settles full-frame, showing the 入职申请信息填写 layout with its form fields and material-upload areas. The caption "扫码入职" remains. The narrator (S1) continues with a short reading pause, <d>[Chinese] 再填写入职信息和材料。</d> The frame holds on the form page to the end.

overall_soundscape:
Clean studio-quiet room tone throughout, with no ambience effects and no UI sounds.

non_diegetic_music:
N/A

---

## 第 4 段（15s）：保存与提交提示

subject_definitions:
<Picture 1> is the onboarding application form page (image9.png), shown as the video's opening frame and held statically throughout, depicting the 入职申请信息填写 layout.

summary:
[keyframe completion + reference generation] The target video is a vertical 9:16 corporate product-demonstration clip. It opens on a static hold of the onboarding form page <Picture 1> while tip callouts fade in one after another, narrated by a steady Chinese business voice (S1).

retention_analysis:
<Picture 1> ([Shot 1]): fully_preserved - the form page layout is retained statically; only overlaid tip callouts are added on top.

detailed_description:
The target video is a vertical 9:16 corporate product-demonstration clip in a clean, formal business style: flat real UI screens, generous safe margins, large legible captions, no HUD, no exaggerated glow, and 交薪通 rendered as plain text only.
[Shot 1] The video opens on <Picture 1>, the onboarding application form page, which stays completely static and full-frame for the whole clip. A concise tip callout "保存可继续编辑" fades in over the lower area with wide margins around 00:02.000. The narrator (S1), a steady Chinese business voice at a deliberate, moderate pace, says, <d>[Chinese] 注意，保存后还能继续编辑。</d> A second callout "提交后不可改" fades in below it around 00:07.000, and the narrator (S1) continues after a short reading pause, <d>[Chinese] 提交后就不能再修改了。</d> Nothing on the page itself moves; the static frame with both callouts holds calmly to the end.

overall_soundscape:
Clean studio-quiet room tone throughout, with no ambience effects and no UI sounds.

non_diegetic_music:
N/A

---

## 第 5 段（15s）：管理员录入花名册

subject_definitions:
<Picture 1> is the administrator's web-based employee roster page (image133.png), shown as the video's opening frame, depicting the 花名册录入 interface on a desktop browser layout.

summary:
[keyframe completion + reference generation] The target video is a vertical 9:16 corporate product-demonstration clip. It opens on a slow pan-and-push over the administrator roster page <Picture 1>, narrated by a steady Chinese business voice (S1).

retention_analysis:
<Picture 1> ([Shot 1]): fully_preserved - the roster page layout and its form fields are retained throughout the pan-and-push.

detailed_description:
The target video is a vertical 9:16 corporate product-demonstration clip in a clean, formal business style: flat real UI screens, generous safe margins, large legible captions, no HUD, no exaggerated glow, and 交薪通 rendered as plain text only.
[Shot 1] The video opens on <Picture 1>, the administrator's web-based employee roster page shown in a desktop browser layout, framed within the vertical canvas with clear margins. The camera pans laterally and pushes in very slowly across the roster form, keeping the name, phone-number, and ID-number fields readable as it moves, and settles on the completed roster fields in the final seconds. A large caption "第一步：将员工录入花名册" is fixed near the top with wide margins. The narrator (S1), a steady Chinese business voice at a moderate pace, says, <d>[Chinese] 员工要登录，管理员先做准备。在网页花名册录入员工信息。姓名、手机号、身份证都要填。</d> Short reading pauses separate the sentences. The frame holds on the roster fields to the end.

overall_soundscape:
Clean studio-quiet room tone throughout, with no ambience effects and no UI sounds.

non_diegetic_music:
N/A

---

## 第 6 段（15s）：登录交薪通

subject_definitions:
<Picture 1> is the WeChat search page showing a search for the 交通银行 mini-program (image134.png), shown as the video's opening frame.
<Picture 2> is the mini-program page showing the 交薪通 entry (image135.png).
<Picture 3> is the 交薪通 login page with phone-number and verification-code fields (image1.png).
<Picture 4> is the 交薪通 home state after a successful employee login (image136.png).

summary:
[keyframe completion + reference generation] The target video is a vertical 9:16 corporate product-demonstration clip. It opens on the WeChat search page <Picture 1> and moves through a four-step login sequence — mini-program entry <Picture 2>, verification-code login <Picture 3>, and successful login <Picture 4> — narrated by a steady Chinese business voice (S1).

retention_analysis:
<Picture 1> ([Shot 1]): fully_preserved - the WeChat search page layout is retained during its hold.
<Picture 2> ([Shot 2]): fully_preserved - the mini-program entry layout is retained during its hold.
<Picture 3> ([Shot 3]): fully_preserved - the login page layout is retained during its hold.
<Picture 4> ([Shot 4]): fully_preserved - the post-login state is retained during the final hold.

detailed_description:
The target video is a vertical 9:16 corporate product-demonstration clip in a clean, formal business style: flat real UI screens, generous safe margins, large legible captions, no HUD, no exaggerated glow, and 交薪通 rendered as plain text only.
[Shot 1] The video opens on <Picture 1>, the WeChat search page with "交通银行" entered in the search box and the mini-program result visible. A large caption "登录交薪通" is fixed near the top with wide margins. The narrator (S1), a steady Chinese business voice at a moderate pace, says, <d>[Chinese] 录入完成后，员工打开微信。搜索交通银行小程序。</d>
[Shot 2] At 00:04.000, the shot cuts to <Picture 2>, the mini-program page showing the 交薪通 entry point. The narrator (S1) continues, <d>[Chinese] 找到交薪通入口。</d>
[Shot 3] At 00:08.000, the shot cuts to <Picture 3>, the 交薪通 login page with its phone-number and verification-code fields. The narrator (S1) continues, <d>[Chinese] 用手机号和验证码登录。</d>
[Shot 4] At 00:12.000, the shot cuts to <Picture 4>, the 交薪通 home state after a successful employee login. No narration over this hold; the frame rests quietly with the caption "登录交薪通" still in place to the end.

overall_soundscape:
Clean studio-quiet room tone throughout, with no ambience effects and no UI sounds.

non_diegetic_music:
N/A

---

## 第 7 段（15s）：协议更新需先阅读 + 首页

subject_definitions:
<Picture 1> is the 交薪通 login page (image1.png), shown as the video's opening frame, containing the agreement-update prompt which this segment magnifies locally.
<Picture 2> is the 交薪通 home page showing the application entry grid (image2.png).

summary:
[keyframe completion + reference generation] The target video is a vertical 9:16 corporate product-demonstration clip. It opens on the login page <Picture 1> and zooms in locally on the agreement-update prompt, then cuts to a slow push over the home page <Picture 2>, narrated by a steady Chinese business voice (S1).

retention_analysis:
<Picture 1> ([Shot 1]): fully_preserved - the login page and its agreement-update prompt are retained; the camera only magnifies the prompt region.
<Picture 2> ([Shot 2]): fully_preserved - the home page and its application entry grid are retained during the slow push.

detailed_description:
The target video is a vertical 9:16 corporate product-demonstration clip in a clean, formal business style: flat real UI screens, generous safe margins, large legible captions, no HUD, no exaggerated glow, and 交薪通 rendered as plain text only.
[Shot 1] The video opens on <Picture 1>, the 交薪通 login page shown full-frame. The camera zooms in locally and smoothly onto the agreement-update prompt area, magnifying it until the prompt text is the clear focal point while the rest of the page falls to the edges. A large caption "协议更新需先阅读" is fixed near the top with wide margins. The narrator (S1), a steady Chinese business voice at a moderate pace, says, <d>[Chinese] 如果协议有更新。要先阅读变更协议才能登录。</d> The magnified prompt holds briefly after the line.
[Shot 2] At 00:08.000, the shot cuts to <Picture 2>, the 交薪通 home page with its application entry grid. The camera pushes in slowly and evenly across the entry icons, keeping every label readable. The caption changes to "首页". The narrator (S1) continues, <d>[Chinese] 登录后进入首页。员工、假勤、协同办公都能用。</d> The slow push continues to the end of the clip.

overall_soundscape:
Clean studio-quiet room tone throughout, with no ambience effects and no UI sounds.

non_diegetic_music:
N/A

---

## 第 8 段（15s）：切换企业 + 下一集预告过渡

subject_definitions:
<Picture 1> is the top-of-screen enterprise switcher (image3.png), shown as the video's opening frame, depicting the multi-enterprise switching control.
<Picture 2> is the 交薪通 home page showing the application entry grid (image2.png), used as the transition source that scales away at the end.

summary:
[keyframe completion + reference generation] The target video is a vertical 9:16 corporate product-demonstration clip. It opens on the enterprise switcher <Picture 1>, then cuts to the home page <Picture 2> which scales away in a fade-out as the next-episode caption appears, narrated by a steady Chinese business voice (S1).

retention_analysis:
<Picture 1> ([Shot 1]): fully_preserved - the enterprise switcher layout is retained during the opening hold.
<Picture 2> ([Shot 2]): partially_preserved - the home page layout is retained as the transition source, then scaled and faded out before the ending.

detailed_description:
The target video is a vertical 9:16 corporate product-demonstration clip in a clean, formal business style: flat real UI screens, generous safe margins, large legible captions, no HUD, no exaggerated glow, and 交薪通 rendered as plain text only.
[Shot 1] The video opens on <Picture 1>, the top of the screen showing the enterprise switcher with the current enterprise name and the switching control. A large caption "切换企业" is fixed near the top with wide margins. The narrator (S1), a steady Chinese business voice at a moderate pace, says, <d>[Chinese] 身兼多企的，点顶部切换企业。</d> The frame holds on the switcher with a short reading pause.
[Shot 2] At 00:07.000, the shot cuts to <Picture 2>, the 交薪通 home page with its application entry grid. The narrator (S1) continues, <d>[Chinese] 后面我们逐个看，每个功能怎么用。</d> As the line finishes, the home page scales up gently and fades out in a soft transition, while a large caption "下一集：首页与个人中心" fades in and holds centered with wide margins; the closing caption remains on screen calmly to the final frame.

overall_soundscape:
Clean studio-quiet room tone throughout, with no ambience effects and no UI sounds.

non_diegetic_music:
N/A
