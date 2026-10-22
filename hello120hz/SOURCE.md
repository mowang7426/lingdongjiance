# 来源与范围

上传：Hello120Hz源码_1.zip；SHA-256 `3ad126deaea3adfc3ca3ee1ac202ae554cae5a86547d64a9fe9d836794760290`。
上传 control 标注作者/维护者 zqbb，原版本 3.3.3-3。上传未提供 LICENSE，不能据此虚构开源许可或再分发授权；版权归原权利人。本次按用户提供源码集成。

灵动集成版本为 5.09+full2，直接父基线 `9eb7e4947e976da22a15c1945a598ce0f81afb63`（5.08），未 cherry-pick 旧移植。
最终范围以用户截图 photo_92FEC68F.png 为准：保留原设置 UI 与主开关、帧率、屏蔽异常/AltList、系统注入恢复、HUD、重置、手动确认注销。用户最新重新授权：只新增默认关闭的系统录屏120请求/诊断模块；原后台 cadence 仍不实现。录屏是真实采样/VT请求的诊断测试版，不宣称真机120已生效。

原 H120SettingsController 界面/分组/图标/中英文/AltList 控制器保持来源实现；修改仅来源/集成版本说明、排除 replayd/backboardd 的注入过滤器、注销确认。原系统模式/全局模式切换界面随模式变化，系统模式显示原“全局注入”，启用后显示截图“屏蔽异常/恢复默认”。默认系统进程注入且 wantsEnable 缺省为 false，不为贴截图擅自全局启用。

full2 在 full1 commit cb2e761c8dd53621b18d851c7f16c0a5b6a95af0 上直接增量提交，未修改 main/5.08；录屏以原上传模块逐函数审计新增，没有 cherry-pick 旧分支。原UI只增一行开关与诊断说明；独立 replayd 过滤器不受原全局/系统切换覆盖。详细边界、日志、原始录屏验收见 CAPABILITIES。
