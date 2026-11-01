# 灵动监测 5.02：浮窗2锁定整窗触摸穿透

基线：5.01 `281bc6adeadcfebf1c2a2cbd56845f8a66d9031e`。
仅使用现有 `floatingTextOnly2Locked` 开关，无新增开关。

## 实现
- 浮窗2由独立透明 `SBCPUSecondTextWindow` 承载；浮窗1与设置/详情仍使用原窗口，不关闭原窗口交互。
- 锁定时文字保留显示，但第二窗口 `userInteractionEnabled=NO`；UIKit `_ignoresHitTest` 返回 YES，`pointInside:withEvent:` 对所有点返回 NO，`hitTest:withEvent:` 返回 nil。不只是禁用 pan。
- 关闭锁定后整窗交互与原 pan 立即恢复，只在浮窗2文字区域接收触摸，空白继续透传。锁定取消在途 pan，解锁后新 pan 清零位移，不沿用旧拖动。
- 设置/详情弹出时第二窗口放弃命中，让原窗口的全屏交互保持正常；锁定浮窗2不会阻断浮窗1或其他浮窗。
- 原偏好写入/同步/Darwin 通知链保留；第二窗更新在主线程执行，无需等待采样 timer。
- 保留5.01窗口2网速双行 `floatingTextOnly2NetworkDualLine` 默认 OFF、槽位、方向/锚点、网速采样、FPS、温控、电池及充电逻辑。没有新增 timer，没有恢复120实验。

## 自动回归
新增 `tests/second_touch_policy.c`（16种状态、锁定/解锁），C/C++ 双模式；`tests/second_touch_wiring.py` 检查独立窗口、全点拒绝、取消手势、现有偏好即时链、浮窗1实现逐字不变及不新增timer。
现有槽位/网速双行测试仅适配独立第二窗口名称。全部本地Python、C/C++ policy与memory tests执行；Apple Foundation原生测试由macOS手动CI执行。
workflow仅 `workflow_dispatch`，增加上述回归后继续原Rootless/RootHide双构建与deb包内容验证。

## 真机验收（自动测试/CI不能代替）
1. 浮窗2覆盖App按钮/列表，打开锁定：文字继续更新；点击、长按、滑动均交给底层App，整窗空白也不得挡触摸。
2. 将浮窗2与浮窗1及第三方浮窗重叠：锁定后下层浮窗仍能点击/拖动。
3. 关闭锁定：立即能拖动浮窗2，保存位置正常；拖动中锁定再解锁，不跳位、不续接旧手势。
4. 两种横屏、竖屏、旋转、锁屏/唤醒、重启SpringBoard后复验可见性、锚点、锁定持久化与透传。
5. 浮窗1锁定/解锁、长按详情及设置页面维持5.01行为；全局开关关闭无残留浮窗2。
6. 分别在Rootless/RootHide目标系统验证UIKit私有`_ignoresHitTest`和跨进程事件路由；如目标系统路由不同，不能仅凭CI成功认定触摸穿透已真机通过。
