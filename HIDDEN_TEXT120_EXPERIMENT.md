# 隐藏文本120资格实验 4.87.120text1

基线：dynamic-source120-experimental / 420e1f2ada0a488d97279630767f48dcfea5a311。独立分支 hidden-text120-experimental；保留文字模式、锁定提示、浮窗定位及原温控设置代码。不调用 _CADeviceDisableMinimumFrameDuration，其 ABI/极性未知。不是解限成功声明。

## 实际干预
默认 OFF 的 hiddenText120HzEnabled 开关。主线程枚举 UIApplication.windows 与公开 UIWindowScene.windows，只读识别已存在、非 hidden 的 UIStatusBarWindow 类对象。仅在硬件能力确认、解锁亮屏、非低电量、温度 nominal/fair 且旧 system120HzEnabled 和 dynamicSource120HzEnabled 均 OFF 时，创建 hidden CGRectZero UIView 子类（仅自身生命周期回调）和 hidden CGRectZero UITextView，用公开 addSubview 挂载。实际初始化尝试至多一次/进程。挂载后验证 superview/window，找不到目标明确 FAIL 且不初始化 UITextView，不偷偷替换成浮窗。

与原动态120二进制一致：SpringBoard 内，状态栏 window 下隐藏零尺寸 UIView 包含隐藏 UITextView 的对象树形状。不同：不 hook UIStatusBarWindow.initWithFrame，不抢初始化时机；只找已存在可验证非隐藏 window；附加安全 guard、禁交互和一次性生命周期管理；不实施未知 C 函数 hook。因此不是原包完整等价复刻。

不 firstResponder、不动画、不新建持续 link 或 dynamic source、不改 pause/reasons、不猜 reason、不伪造 UIScreen 能力、不扩全 App。旧范围 hooks 保留基线代码且 OFF 时透传；试验隔离不得打开旧开关。

关闭、锁屏/AOD、显示关闭/未知、低电量、高温/热状态未知立即事件驱动 remove/release；window 隐藏、移出、销毁同样释放。对系统 window 仅 weak ownership；通过自身 didMoveToWindow 及公开 Objective-C 关联销毁哨兵捕捉生命周期，没有全局 UIView hook，没有持续轮询。创建重入用 creating 标志拒绝，移除前清 callback。释放后本进程不再初始化，需注销重试；window 后续可见事件只为尚未找到目标的首次创建重试。

## 真机 A/B（iPhone15,3 / iOS17.0）
1. 安装对应越狱环境包。退出其他高刷插件；记录机型、低电量、热状态、显示设置、浮窗配置、温控配置。不要把温控改为去保护来促成结果。
2. A：旧 system120、dynamicSource120 和新隐藏文本全 OFF；注销 SpringBoard。解锁并在相同亮度、相同桌面、同样温度/电量和静置时长下，用设置的 120Hz诊断手动采样3秒。保存 pid、callbackHz、sampleSeconds、sampleFresh、各开关和 hiddenTextExperiment。
3. B：保持两个旧开关 OFF，仅隐藏文本 ON，再注销。解锁后按相同条件诊断。必须看到 textEnabled=1、createdCount=1、mounted=1、windowClass 为 UIStatusBarWindow 或其子类、guard 为空，才是有效干预组。ON 但 FAIL/保护拒绝/未挂载不能用来证明文本无效。
4. B 不要长期停留。测试锁屏/AOD、低电量或高温保护时，确认 mounted=0；恢复不会重新创建，需注销后再测。不要人为加热手机。
5. A2：新开关 OFF，再注销、解锁、同条件采样。每组重复2–3次并记录新 pid。ON/OFF 两组都注销是必要控制：UITextView 初始化可能有进程级全局副作用，remove不能保证撤销。

有效样本通常 sampleSeconds 约3秒、sampleFresh=true。记录Hz为 displayLink 回调，不是面板实际Hz/游戏FPS。此前动态源真机54.42Hz/3.03s即使 hooks 改写生效仍未达120；不能把创建或挂载成功当成高刷成功。本版本还没有真机结果。

## 验收/回退
正常有效 ON 创建/挂载一次，反复诊断不重复创建；关闭/保护/window失效应 mounted=0，guard/状态可读；不弹键盘、不抢焦点、不依赖浮窗是否开启。若没有 UIStatusBarWindow，本路线明确无法开展有效干预，先停止，不能以自有浮窗偷偷替代。

回退：新开关、旧两个开关均 OFF，然后注销。需要稳定包时安装 motionx120-experimental 的 fd4aaf5df4f0595283335c68dbb7cf259e7e440b 对应包并注销。main 不动。CI 进行原回归、新文本静态安全回归及真实 rootless/roothide 编译；这不替代 UIKit 真机生命周期和效果验收。
