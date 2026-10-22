# full4 录屏加载诊断与路径审计

本版不承诺已解决真实120帧；不修改编码、VSync、显示节拍、浮窗、充电、温控或双开关门控。用户已注销并重启用户空间，不能再把无日志归因于“没有重启”。

## 已确认的问题

- full3 的 Event 在第一次日志前就把 `/var/mobile/Library/Logs/Hello120Hz` 当作越狱载荷路径交给 H120JailbreakPath，Rootless 映射到 `/var/jb/var/mobile/...`，RootHide 交给 jbroot。它不是明确的真实 mobile 数据路径；daemon 对该映射目录的权限/沙箱访问没有证据保证。
- 同一 Event 丢弃 mkdir 的 NSError；路径 resolver 为 nil 静默 return，open 失败只有 NSLog，没有设置页可见信息。constructor 的 module-load 也使用这个 Event，所以“目录不存在”本来不能区分未加载、路径失败和沙箱拒绝。
- constructor 在发布任何独立状态之前进入 Foundation、日志路径解析和 Hook 初始化。full4 改为 C executable gate + 立即注册 C Darwin notify 应答，后续 Foundation/Hook/dyld 注册异步主队列执行。
- full4 日志明确使用真实 `/var/mobile/Library/Logs/Hello120Hz/recording.jsonl`，只创建最终专属目录，不创建/更改共享父目录权限，不绕沙箱；父目录不存在/无权限也保留 errno。读不到日志时仍可通过握手回传数值状态。

## 实际 full3 安装包核查（不是仅源码）

两包 recording dylib 与 plist 文件名大小写匹配，独立 Filter.Executables=[replayd]，ARM64/ARM64e 两切片，代码签名 SHA1/SHA256 页面哈希全部通过既有实包核验。RootHide dylib 的 substrate 与 libroothide 使用 @loader_path/.jbroot/usr/lib；Rootless 使用 @rpath/CydiaSubstrate.framework/CydiaSubstrate 并携带 /var/jb/Library/Frameworks 等 rpath。VideoToolbox 等均为系统 framework。LC_DYLD_CHAINED_FIXUPS 实际导入包含 MSHookFunction/MSHookMessageEx/jbroot 与系统 ObjC 类，不是 bind 表为空就无导入。

原可生效包也通过 .jbroot 导入 substrate/libroothide；它的录屏路径与过滤器组合方式不同，不能把此差异独自作为未加载证据。full3 实际 postinst/hello120hz-install helper 只改客户端 0hello120hz.plist 的链接，不改独立 Recording.plist。并未在包中发现 Recording 大小写遗漏或安装脚本覆盖它。

系统和越狱管理器提供的 dylib 不随本 DEB 分发；静态路径正确不等于目标机器必可解析，代码签名页面哈希正确不等于设备信任/注入策略接受，arm64e 元数据存在不等于全部 PAC 调用已在目标执行验证。没有设备 dyld/系统日志时不能宣称唯一根因。

## 设置端可见诊断

保留原设置主体与七项，另增一个“录屏诊断 / 导出诊断”小入口。报告分开标注 Settings self-check 与 daemon real acknowledgement：版本、设置端 uid/PID、偏好实际路径与门控布尔、独立模块/过滤器存在可读性、实际 load commands/rpaths 和非系统依赖候选逐一可读检查、权限允许的 replayd PID 枚举、真实与 legacy 映射日志位置/读取 errno。不会通过 dlopen 去执行录屏模块做假自检。

每次检查生成随机 nonce，先注册独立 reply 名再发送 ping；应答数值含 build50904、replayd PID、四 Hook 掩码、双开关实际 enabled、实际偏好路径可读性、日志 errno。仅成功获取该次随机回复名的非零 state 才报收到。1.5秒超时不会阻塞主线程，报“未收到应答：可能未加载/通信受限”，不是“必然未加载”。register/set/get/post 失败显示实际 transport status。旧模块无 full4 协议不能冒充 full4 加载成功。

导出通过系统分享面板合并设置自检、握手回执与可读取的最多128KiB日志；不包含媒体、账户或应用内容，不自动启动录屏、kill、注销或改偏好。

## “120锁不住”：必须区分的三种量

1. Settings 的 wantsFPS=120 只是请求目标，不代表客户端已加载或显示硬件正在120Hz。系统模式的实际主过滤器只针对 SpringBoard/Preferences；全局 UI 模式增加 com.apple.UIKit 客户端，仍不是全部守护进程，且黑名单中的客户端透传。安装 helper 只把精确主过滤器链接到 mobile 可写注入配置；不更改独立录屏过滤器。既有驻留应用的注入情况不能由 Settings 文件存在推出。
2. 客户端只在目标 QuartzCore 符号存在时安装六个范围 trampoline 与 arbitration/restriction hooks；缺符号会跳过。偏好通过 Darwin 与可用的 Distributed notification 更新，但只影响已经加载的客户端。诊断新增独立的 SpringBoard 主模块随机nonce握手，回传真实 build/PID、实际装上的 Hook 数量0–8、当前 enabled/偏好可读性、当前已生效的请求目标FPS。这个回执不冒充第三方应用全部已加载，也不把目标值当作物理Hz。
3. dirty-frame/合成器FPS会随静止画面和内容变化下降，不能单独证明物理刷新没有锁住；录屏输出FPS又是另一条 capture/writer/encoder 链。当前没有恢复 backboard cadence，且不绕开热保护、低电量或系统硬件调度，因此本版原本就不具备保证全局物理锁120的能力。

下一步需要同一机型/iOS build/越狱环境、前台应用/系统或全局模式/黑名单、动态运动场景下可验证的物理面板刷新时序或可信系统轨迹，加独立客户端/录屏回执；录屏另外验原始PTS与独立画面。仅看到设置120、浮窗 dirty-frame FPS或视频容器120都不够。不为回应“锁不住”而猜测 backboard 私有ABI或扩大Hook到全部进程。

## 验证边界

新增原生测试编译并执行同一生产 C IO/notify 实现：没有父目录、权限拒绝、符号链接拒绝和 errno；两个真正进程经 macOS notifyd 的 nonce 应答/超时、状态版本辨别、模块关闭仍可应答，另测 sudo/root responder 与普通 UID client。该测试不使用假的 notify stub；结果以最终CI为准。它不能替代 iOS replayd 沙箱现场回执，故设置页保留通信受限分支。原UIKit/录屏ABI/VSync、字体、触摸、频率、充电等回归全部保留。

用户只需打开 Hello120Hz → 录屏诊断，等页面回执完成 → 导出诊断并上传；无需再找目录或重复注销/重启。若无应答，先依据依赖/路径/权限报告继续调查，不扩大 Hook 范围。
