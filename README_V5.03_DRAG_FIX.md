# 5.03 第二文字浮窗事件链修复

## 证据与诊断边界

5.01（281bc6a）第二文字宿主和 pan target 都是 cpuWindow.rootViewController；SBCPUWindow.hitTest 显式返回 textOnly2Label。5.02（abbbfc7）将其移到新 SBCPUSecondTextWindow，同时删掉主窗第二文字命中分支。新窗仅设置 frame/windowScene/windowLevel/rootViewController/hidden，没有额外 SpringBoard/BackBoard 跨 App 触摸托管或上下文注册，也没有验证这种新窗能收到真实 App 前台事件。windowScene 和可见性只能说明 UIKit 层级，不证明跨 App 触摸上下文已正确参与路由。

5.02 的 OFF 在局部布尔逻辑中会打开 window/label/pan；故旧策略测试通过不能推出事件已到该窗。新增 _ignoresHitTest 还在上游将 settingsShowing/detailShowing/presentedViewController 混合为整窗拒绝条件；状态残留/切换时机使局部 hitTest/pan 正确也可能完全没有入口。现有仓库无法证明某一私有接口在用户设备上的具体返回或缓存行为，因此不将“缺某个私有注册调用”或“_ignoresHitTest 永久返回 YES”当作已实测结论。能直接确认的回归根因是：移走已知可拖动的原事件宿主，撤掉原命中入口，却未验证替代事件链。

## 最小修复

* 删除独立第二 UIWindow 和私有 _ignoresHitTest，不猜测/新增私有 BackBoard 注册接口。
* 恢复 5.01 已验证的 cpuWindow/rootViewController/view 宿主、pan target 与主窗第二文字命中入口。
* ON 关闭第二 label 和其所有 recognizer，并重置拖动状态；主窗不返回该 label。不是仅禁用 pan，也不禁用主窗或根 view，因此第二文字及空白不成为触摸目标，浮窗1仍正常。
* OFF 在偏好变更更新中重新启用同一个 label 和 recognizer，按文字 label 的 bounds 命中，空白仍返回 nil。
* 命中额外核验 label.window==当前主窗、模式、可见性及交互性，避免失联 label 或禁用模式残留命中。
* pan 校验实际挂载 view/window，用 label.superview 坐标读取 translation（与 center 同坐标系）；旋转命中仍通过 convertPoint 转入 label 本地坐标。
* 保留主窗原有设置页/详情模态处理；不再使用这些标志把第二个独立窗口从事件路由中排除。即使旧标志残留，super 的真实根 view 层级仍可遍历第二 label，ON 由 label.userInteractionEnabled 保证不命中。
* 双行网速、字号/布局、逻辑坐标、拖动结束锚点持久化保持 5.01 原实现；浮窗1实现逐字比对不变，无新 timer、无120Hz实验。

## 回归层次

second_touch_wiring.py 检查生产宿主/target/坐标/锁定恢复接线，并生成原生 Objective-C 测试。second_touch_event_tree.m.in 用 Foundation/CoreGraphics 事件树替身执行从 Tweak.xm 提取的真实 syncSecondTextInteraction、宿主构建前段、SBCPUWindow.hitTest、pan Began/Changed 方法体，覆盖反复 ON→OFF→ON、同 recognizer 恢复、命中到 pan 位移、旋转转换、浮窗1不受影响、空白透传、旧模态标志残留、模式关闭/重建。拖动结束/布局尾部由原锚点及布局回归覆盖。CI 同时执行全部原回归并构建 Rootless/RootHide。

这些是原生事件树替身及构建回归，不能模拟 SpringBoard/BackBoard，也不是本机真机测试。不声称用户真机已修好。

## 必须真机验收

1. 安装对应越狱制式5.03并注销SpringBoard；确认显示版本5.03。
2. 前台第三方App中，第二窗 ON：从文字和四周空白点击/滑动，底下App接收且第二窗不动；浮窗1仍可按原规则操作。
3. 不重启/不等采样，OFF：从文字区域拖动应立即移动并保存；空白点击/滑动仍落到底下App。
4. 连续ON/OFF三轮，含拖动中切ON后再OFF；测试竖屏、横屏、网速双行。
5. 打开/关闭设置页、详情、切换App、锁屏解锁、关闭重开第二窗后再测OFF拖动及锚点。
6. 若仍失败，需收集真实触摸入口/上下文与手势状态日志；不能再用本地policy PASS代替设备证据。
