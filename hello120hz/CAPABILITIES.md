# 最终功能矩阵（5.09+full3 录屏修复测试版）

|截图项目|实现/偏好|验证和边界|
|---|---|---|
|启用调整|原 wantsEnable；缺省关闭；关闭和黑名单客户端全部透传|生产策略、模拟器原 controller 回归；目标越狱真机未验证|
|优选帧率|原 10/30/60/80/120；wantsFPS；QuartzCore 六个范围 trampoline 和两个 arbitration/restriction hooks 独立模块|HFA ABI/寄存器不改变其余参数；符号缺失日志并跳过，不保证设备实际120fps|
|屏蔽异常|selectedApps；原 AltList 动态子类、搜索、标识符、可见应用多选；排除当前 bundle hooks|依赖 com.opa334.altlist 已声明；真机实际应用枚举需 AltList/越狱环境验证；不是绕过越狱检测或防封|
|恢复默认|原注入配置只注入 SpringBoard/Preferences；UI 回到“全局注入”以便再次开启原模式|过滤器链接 mobile 所有的原配置文件；只影响新启动进程，原驻留模块需用户确认注销/重开应用；不修改其他插件|
|打开/关闭调试|原 CARenderServerGetDebugOption/SetDebugOption/SetDebugValue 手动动作|符号存在才调用；缺失提示；系统权限/真实 HUD 须真机验证，安装不会自动打开|
|重置|原 wantsEnable=false,wantsFPS=120,selectedApps=[]，不等同切换注入模式|偏好持久化与通知一致性测试|
|注销/点我生效|用户主动点击并二次确认后原 sbreload 路径调用；失败提示越狱管理器|没有执行实际注销；安装无新增自动注销|
|来源版本说明|来源3.3.3-3、灵动5.09+full3 分开显示|非声称灵动3.3.3-3|

## 明确不包含/未证实

## 录屏120：默认关闭的诊断测试版（重新授权新增）

原设置第一组只增加一行“录屏 120 帧”，原分组/其余七项保留。必须“启用调整”和“录屏 120 帧”同时开启；优选帧率仅控制原客户端范围，不取代录屏独立开关；重置同时关闭录屏。仅控制系统录屏请求，不自动开始录屏。

- 独立 `0hello120hzRecording.dylib` 静态过滤器仅 `Executables=[replayd]`，与原 UI 全局/系统过滤器文件分离。任何原模式切换/恢复默认/黑名单编辑都不会改它；录屏模块不读取 selectedApps。桌面客户端 Hook 不进入 replayd。
- replayd/root 通过与设置相同的 Rootless/RootHide 显式 jailbreak mobile 文件读偏好，不使用 root 用户 CFPreferences 缓存；写入精确偏好文件设0644，父目录不改权限。Darwin 通知动态重读；即使构造时开关关闭，也安装门控透传 Hook，之后可动态开启；dyld新增镜像事件在主队列重试晚加载类，无轮询 timer。
- 直接审计上传 Core/H120Recording.mm，每个私有方法均 NSMethodSignature 分参数检查（不按含offset整串比较）。BOOL c/B 使用各自原型；核对 CGSize double-double、CMTime qiIq、block @?、返回类型，错误/缺失拒绝并日志。不恢复或整包复制旧分支。
- 仅 `RPScreenCaptureManagerIOS` 的 systemRecording 真值同步调用域内把真实采样请求间隔改为 `CMTime(1,120)`。只有 `RPMovieWriter.systemRecording` 通过签名检查且真值的同步 setup 内修改视频 writer 参数；音频/第三方/嵌套非系统/域外原样。
- VTCompressionSessionCreate/VTSessionSetProperty/Invalidate 使用公共头精确ABI；仅在上述系统 writer 同步域内成功创建的编码器被标记，再调用真实 VTSessionSetProperty 请求120，保存真实 create/set OSStatus。标记随 session 身份延续到异步 property 调用，而非全进程TLS；最多持有8个会话防止裸指针复用，失效/关闭清理。非录屏编码器不改。
- **限制**：异步“创建”capture/encoder 的来源上下文没有可证实的目标 iOS 私有符号/对象链，不能用全局“正在录屏”冒充系统会话。此时失败关闭，日志 systemContext=false。上传 VSync setter 是类级全局且返回void，没有已证实可恢复/会话级API，故不写它，日志 `class-wide-setter-not-session-safe` / statusAvailable=false，不能伪称VSync成功。当前无法保证源端120，不能保证真120帧；只写编码元数据也不算达成。

- **full3 已按原包可验证证据恢复采集端请求**：系统录屏同步 capture factory 且目标 setter 精确匹配 `void(id,id,id)`、VSync key 存在且为 CFString 时，实际发送 `setFigVirtualDisplayOption:@120 forKey:key`；记录调用完成但不伪造接受状态。缺 key、类型、方法签名、异常均 fail-closed 并记录原因；关闭/非录屏/异步路径不调用。
- 该 setter 是类级且没有已证实 getter/恢复 key；full3 不猜 nil/60，不自动 kill/注销/重启。成功请求后关闭开关或结束录屏仍可能影响同 replayd 后续捕获，必须用户主动用越狱管理器重载 replayd；注销 SpringBoard 不等于重载 replayd。
- full3 恢复了 `usr/libexec/hello120hz-install` 实际最终 stage 落包，并在包解包测试中验证 postinst 调用、权限和独立过滤器隔离。

安装匹配越狱环境的包，打开 设置→灵动监测→Hello 120Hz，开启上述两个开关。首次安装独立模块需要 **replayd 的一个新进程**加载；注销 SpringBoard 不保证重载 replayd。本包不会杀进程、注销或重启；请使用越狱管理器明确支持的手动守护进程重载方式，或自行选择重启并重新越狱。已载入模块后的开关变化无需再次重载；停止当前录屏，下一段录屏验收关闭/开启（不会改写正在录制会话已接受的源参数）。原桌面注入变化仍按原说明注销/重开应用。

事件文件逻辑路径 `/var/mobile/Library/Logs/Hello120Hz/recording.jsonl`，与偏好一样经 jailbreak-root 解析：Rootless 通常为 `/var/jb/var/mobile/Library/Logs/Hello120Hz/recording.jsonl`；RootHide 从其当前 jbroot 的 `var/mobile/Library/Logs/Hello120Hz/recording.jsonl` 打开，不猜随机根目录。文件0644/mobile可读，目录可由文件管理器访问。没有日志首先排查 replayd是否重载/注入策略/沙箱写权限（无法写时系统日志有错误）；不是立即认定“源60”。日志仅载入、偏好布尔、方法签名匹配、会话布尔、请求间隔、编码返回码与事件时间；不采集画面/视频/音频/账户/应用内容。变化事件去重，每类最多24条，文件上限128KiB，无高频定时器；测试前可手动删除旧文件并重新加载模块，避免旧日志满额。

需提供开启与关闭各5–10秒 **未经聊天平台转码的原始录屏文件**及事件日志、机型/iOS build/越狱环境。分别检查编码请求、输出PTS间隔/帧数和独立画面帧（重复画面不算真实120），截图58.78FPS/5s只能证明旧输出约60，不能定位采集源/编码器。CI仅验证替身链路、ABI编译/签名与包结构，不能替代目标机实测。

上传 backboardd preferred_frame_duration/hardware_minimum_frame_duration 的 uint32_t 返回 ABI 仅凭 mangled 符号无法证实。已有本地公开 QuartzCore 头/符号和 CADisplayLink/DynamicFrameRateSource 反编译证据支持客户端 CAFrameRateRange 输入，但没有后台两个函数的返回约定证据。因此未安装后台 Hook、不注入 backboardd；这是显式未实现的后台 cadence，不宣称完整版120或所有硬件生效。需目标 iOS build 的这两个方法反汇编/调用点与量纲、真机符号解析和帧率轨迹后方可补齐，不冒猜 ABI 风险。

## 集成隔离与安装

仅原灵动根页新增一条 Hello 原 controller 入口；原浮窗/充电/温控/CPU 源码和反色未修改。新核心作为独立子工程；缺省配置只系统进程，开启全局由用户主动操作。两种包使用各自 Rootless/RootHide 路径解析。新过滤器安装脚本只操作自己的精确文件，不更改现有父目录权限/所有者，不覆盖用户已有注入配置或 wantsEnable，不自行安装到设备。包版本 5.09+full3 比旧5.10/5.11低，包管理器可能要求允许降级。

CI 通过仅说明编译、生产策略/控制器测试与打包检查通过，不等于越狱设备实测。真机验收：安装AltList→缺省总开关关闭→选择帧率→启用→验证 UI 动画轨迹；全局切换后用户确认注销并重开第三方；黑名单进程恢复原策略；关闭总开关透传；手动 HUD 打开/关闭；最后用户确认注销。勿用浮窗请求FPS替代面板真实刷新率证据。
