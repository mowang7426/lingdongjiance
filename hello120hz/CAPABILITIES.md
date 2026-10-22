# 功能与边界（5.09+full6）

## 单模块集成

只构建 `0hello120hz.dylib`，由唯一构造入口按真实进程名分发：replayd 仅录屏运行时、backboardd 仅安全空入口、其他客户端才进入范围与仲裁 Hook。Recording.mm 单文件使用 MRC，其余仍 ARC；偏好和诊断实现各编译一份。未使用 VideoToolbox 链接依赖或 VT 全局 hooks。

系统模式与全局模式的同一过滤器均保留 Executables=[SpringBoard,backboardd,replayd] 和 Preferences；全局另有 UIKit。backboardd 被列入过滤器不代表已安装物理显示 cadence Hook。UI 模式切换同步此单模块过滤器；黑名单仍仅控制客户端，不阻断 replayd 录屏入口。

升级 helper 原子迁移本插件的持久过滤器，保留既有 UIKit 全局模式，不更改 wantsEnable/recordingEnabled/selectedApps；只清理两个精确旧独立 Recording 文件，不清理其他插件。不修改既有共享父目录的权限/所有者；helper 是 root 所有的普通 0755 安装脚本，不是 setuid 程序，不提供执行任意命令/杀进程服务。

## 原 UI 与客户端

保留启用调整、10/30/60/80/120 优选帧率、屏蔽异常/AltList、系统模式恢复、HUD、重置、用户确认注销及原风格图标/布局。缺省总开关与录屏开关关闭。客户端六个范围 trampoline 和两个仲裁/限制 hooks 仅在符号存在时安装；黑名单或关闭透传。缺符号跳过，不把目标 FPS 当实测物理 Hz。

## 系统录屏请求链

只有总开关与录屏开关均开启、私有方法逐参数签名验证成功且 systemRecording 为真才修改系统录屏同步链。capture 请求 `CMTime(1,120)`；验证 VSync setter 与 CFString key 后调用类级 `setFigVirtualDisplayOption:@120 forKey:key`。writer 在验证的系统录屏同步 setup 域内请求源帧率/关键帧间隔120，原期望源帧率低于120且码率有效时按原版条件加倍。音频、第三方、非系统、异步来源不明与签名不匹配路径透传。TLS 使用 finally 恢复，异常不会污染后续调用。

VSync setter 返回 void，只证明完成调用，不证明系统接受120；没有已验证 getter/恢复 key。不能猜 nil/60 恢复。关闭只停止新修改，不能复原已请求的类级状态。录屏结束/关闭后若需恢复，须用户在越狱管理器重载 replayd 或用户空间。本版本未提供已验证的跨越狱特权重载服务，所以原风格“应用录屏设置”按钮只发送偏好通知并诚实提示操作路径，不执行 kill、不声称已重载或成功应用；已做过重载则直接诊断，不要求重复。原“注销”仅 SpringBoard，不等于 replayd 重载。安装不自动重启、不录屏、不改设备偏好。

## 诊断与验证

Self-check 5.09+full6 检查当前单模块/过滤器/helper，不再要求旧独立 Recording 文件。Settings 的 lstat/readlink/follow-open 只代表自身权限；合法 substrate→ellekit 链接不能因 O_NOFOLLOW ELOOP 判为加载失败。replayd 与 SpringBoard 独立 nonce 握手回执 build=50906；只有该次真实回执才代表相应进程应答。超时只显示可能未加载/通信受限；模块文件存在不证明 loaded。

日志仍为真实 `/var/mobile/Library/Logs/Hello120Hz/recording.jsonl`，受控大小与去重，不采集画面/音频/账户。支持导出握手、真实/旧映射日志及实际 errno。CI 编译执行生产路由、录屏实现与原 controller，并保留触摸、频率、字体、充电等原回归；不能替代 iOS replayd 沙箱与输出测试。

## 未恢复的物理 cadence 与待真机验证

原包 preferred_frame_duration 替换函数 w0 返回32位整数证据存在，但目标 iOS 方法 receiver/量纲/调用约定仍未确认；未安装 backboard cadence Hook，安全整数 fallback 不冒充挂钩。此单模块收敛参考原版架构，是修复尝试，不是已经证明唯一根因。

仍需目标设备真实回执与开关前后未经转码的5–10秒原始系统录屏，检查输出PTS、帧数及独立画面帧；重复画面不算120。客户端请求120、编码元数据、HUD/dirty-frame FPS均不能代替物理屏幕120Hz或真实录屏120fps证据。本版本不保证锁物理120或录屏实际120。

两包仅针对对应 Rootless/RootHide 环境；保留原浮窗、充电、温控等代码。5.09+full6 比旧5.10/5.11低，包管理器可能需要允许降级。
