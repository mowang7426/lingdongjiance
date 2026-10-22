# full5 诊断窄修

版本：5.09+full5，回执 build=50905；保持 v4 notify 名称与位布局，不更换 Hook provider 或加载机制。

- Settings 的 O_NOFOLLOW 遇到末级合法软链也会返回 ELOOP。现在列出 lstat/readlink 和单独只读 follow-open 结果，不再仅凭 errno=62 判为循环或 replayd 未加载。
- replayd 与 SpringBoard 两个通道独立并发请求，各自保存 pending/completed/timeout/transport-failure、开始/结束/截止时间与原始回执，2 秒 UI watchdog 防止等待态遗漏结束。晚到回执不能改写终态。
- 自检及两通道均完成后才能导出，按钮与 action 都检查状态；每次转换生成不可变快照，导出明确含 exportStatus=final。
- 按 H120_DIAGNOSTIC_VERSION 识别版本；client 的 [23:12] 为 requested targetFPS，不是 errno；回执不是安装 Hook、输出 120fps 或面板 120Hz 的证明。

测试保留所有原用例，新增生产 C/C++ 状态机实执行与真实 controller 导出、合法软链/真正循环回归。macOS CI 的真实 notifyd 跨 UID 测试不替代目标 iOS 设备的 notify/sandbox 实证。

用户操作：按越狱类型安装相应包，打开 Hello → 录屏诊断，等待导出按钮可用后导出并上传文本。无需为了诊断反复重启、手动杀 replayd 或新录屏。本版本不声称已修复 120fps/120Hz。

本次不主动安装、注销、录屏、杀 replayd 或改真实设备偏好；原浮窗/充电/温控与 5.08/main 不变。
