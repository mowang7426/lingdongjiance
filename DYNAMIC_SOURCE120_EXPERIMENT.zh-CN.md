# 动态源120实验（4.87.120ds1）

基于 motionx120-experimental 的 fd4aaf5。main、调查分支、独立UI120分支不变。

## 干预路线

仅 SpringBoard：严格验证实际 CADynamicFrameRateSource 和 CADisplayLink 的 setPreferredFrameRateRange: 为 void / id / SEL / CAFrameRateRange，随后 MSHookMessageEx。先读取原 UIScreen 能力并核对真实硬件白名单，非120设备不安装hook，不伪造能力。

新增独立 dynamicSource120HzEnabled，默认 OFF。合格主线程新请求（有限数值、0<=min<=max<=120、max>0、preferred为0或位于[min,max]）在真实120设备、解锁亮屏、非低电量、热状态nominal/fair、状态已知且ABI有效时改为120/120/120。默认0/0/0、非法值、超过120、非主线程及受保护请求原样透传。

不hook setPaused:/isPaused、reason setters、init、UIScreen、未知CADeviceDisableMinimumFrameDuration；不借用reason、不新建动态源、不禁止系统暂停、不扩展全App。未加隐藏UITextView路径。与旧range-only实验的区别是确实进入宿主已有动态源的请求入口，而非只修改公开DisplayLink或只调查ABI。

## 线程/恢复边界

原setter始终在原调用线程运行一次。只对主线程新请求改写；后台请求只统计、透传。生产锁只包围弱记录和统计，不在锁内调用原setter，不dispatch_sync、不猜私有对象队列。

弱key记录最多512个活对象，保留最近外部range；对象不会因实验存活。关闭/保护后后续外部请求原样透传并覆盖之前改写、移除对应待恢复记录。**不跨线程重放私有setter，不承诺所有存量range即时还原**。如果对象再无新请求，旧range可能仍在；关闭开关后respring（重启SpringBoard用户空间）是彻底回退路径。pause/reason全部由系统继续控制。

## 测量与解释

旧system120HzEnabled维持既有功能，隔离测试请关闭。动态实验单独开启时不创建持续keepalive。点击「120Hz诊断」按需创建公开API DisplayLink，请求120、累计约3秒回调，invalidate/release；5秒一次性watchdog处理暂停无回调。关闭态也可执行同样公开请求作range-only基线。低电量/锁屏/熄屏/未知状态/高温拒绝或取消探针。诊断窗约5.5秒返回。

诊断包含 dynamicHookInstalled/displayLinkHookInstalled、分开calls/rewrites/changedRanges计数、实际input/output、保护原因、offMainPassThrough、supersededByExternalRequest、弱待恢复对象及最近外部备份。rewrites包含原本已120请求；**changedRanges增加才表示数值真的改变**。动态calls增加才证明私有入口被调用；安装成功不等于触发，触发不等于调度120。callbackHz仅是当前公开探针回调，非面板扫描率或游戏FPS。默认范围可能从未触发、源可能暂停、仲裁可能继续60，均是本实验的有效负结果。

## 安装与测试

1. 禁用其他高刷插件，移除 standalone-ui120，备份当前deb和偏好；匹配越狱制式安装rootless或roothide包，不混装。此包仍为 com.sbcpu.floating，替换灵动监测而非安装第二份；RootHide确认SBCPURefreshRate对SpringBoard允许注入。
2. respring。旧120开关OFF，新动态开关OFF，解锁亮屏、关闭低电量、等设备降温；手动诊断记录基线。
3. 新动态开关ON；返回主屏，连续滑动主屏/控制中心等系统UI触发新的range请求，再诊断。核对dynamic.calls及dynamic.changedRanges、lastRanges；仅displayLink计数增加不能证明动态源路径已触发。记录callbackHz与3秒sampleSeconds。
4. 同样手势重复3次。开低电量、锁屏再解锁、正常保护后验证保护原因及新请求透传；不要故意加热设备。关闭新开关、respring后重复基线：PID应改变，累计计数重新开始。
5. 同时回归文字锁的保存反馈、旋转定位、顶部文字位置与原温控设置。本次Tweak.xm无改动。

## 卸载/救援

关闭动态开关与旧120开关，respring；在Sileo/Zebra等卸载「灵动监测」（com.sbcpu.floating），或安装备份稳定版并respring。若SpringBoard循环崩溃，进入越狱安全模式/禁用插件注入，在插件管理器禁用SBCPURefreshRate后卸载或回装稳定包。RootHide使用其插件管理器和映射路径；不要照抄rootless绝对路径。其他设备/制式不得混装。

本分支完成真实干预、范围/生命周期原生回归及双制式CI包；iPhone15,3 / iOS17.0是否真正120必须用上述真机数据判定，开发/CI环境不能替代该验证。
