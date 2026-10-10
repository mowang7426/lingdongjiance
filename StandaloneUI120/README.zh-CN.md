# UI120 独立系统界面强刷（实验版 0.1.0）

这是独立包 `com.mowang.ui120`，不是灵动监测重新打包，不包含其悬浮窗、充电、温控等模块。根据用户提供的 MotionX 2.0 逆向报告独立实现，未复制或分发 MotionX 原动态库。

## 功能和边界

- 仅注入 MotionX 的三个宿主：`com.apple.springboard`、`com.apple.UserNotificationsUIServer`、`com.apple.springboard.SpringBoardOutofCallUI`。
- 唯一安装的 Hook 是公开的 `CADisplayLink setPreferredFrameRateRange:`。运行时严格核对参数个数及 void / id / SEL / CAFrameRateRange 类型编码，不符合则跳过。
- 原始 UIScreen 最大帧率在本插件安装 Hook 前读取；小于120则不安装。完全不 Hook UIScreen getter、不假报120。其他插件若先篡改 getter，读数仍可能被污染，所以必须停止其他刷新模块。
- 默认关闭。仅解锁、锁状态查询成功、非低电量、温度 nominal、原始硬件≥120、主线程设置的有效范围请求才转换。全零默认范围，或 maximum/preferred≥60，转换为120/120/120。非法范围/NaN/无穷不修改，低于60请求保留。
- 不 Hook 未验证的私有策略，不调用 CADynamicFrameRateSource，不使用硬编码地址。不设置 CADisableMinimumFrameDurationOnPhone；系统宿主可能仍限制在60左右。
- 不注入所有App、不覆盖游戏或面板全链路、不绕过热保护、不保证面板扫描率或始终120Hz。

## 关闭与保护

保存每个实际改写link的最近外部请求，关联值不持有link，弱集合不延长生命周期。仅在主线程操作集合；setter和恢复用同一link对象锁串行，TLS防止递归再改写。后台setter不改写并取消该link旧备份，避免之后恢复盖掉新的后台请求。

关闭、锁屏（包括锁屏AOD）、低电量或温度离开nominal时，在主线程对仍存活且备份有效的已改写link尽力调用原setter恢复。不创建持续保活link、不枚举全部系统link；解除保护不批量重新强刷，仅等宿主下次请求。

这不是“绝对可逆”：link若迁移所属线程、宿主/其他插件再次操作、系统通知延迟或未送达，动态恢复效果不能保证；原setter也可能受其他插件Hook链影响。这里限定主线程新请求，但无法保证所有宿主永远保持link在同一线程。最彻底回退是关开关后重新加载三个宿主，通常用越狱工具的重新启动用户空间。未在用户iOS17实机验证通知、恢复或稳定性。

## 使用

1. 卸载 MotionX（包元数据 Conflicts: com.hx.120），关闭灵动监测的刷新模块和其他强刷/动画帧率Hook；原模块若没有可确认完全关闭的方式，临时停用该插件注入。不要混装测试。
2. 按越狱环境安装 **rootless 或 roothide 之一**。rootless包路径 `/var/jb/Library/...`；roothide包由RootHide Theos构建，归档路径 `/Library/...`，须用对应包管理器安装，不要当rootful包手工复制。
3. 用越狱工具重新加载SpringBoard/用户空间。打开 设置 → UI120 独立强刷，确认默认关闭；没有设置入口时先检查PreferenceLoader及环境依赖。
4. 保持解锁且温度正常、关闭低电量，打开开关。在正常系统UI操作中测试，不覆盖游戏。
5. 点“启动一次3秒探针”，等待5秒后“读取诊断”。仅SpringBoard按需创建一个CADisplayLink，3秒时间戳区间计数，5秒一次性watchdog兜底；结束invalidate释放。无常驻测量、无每帧文件写入，仅人工诊断结束写一次结果。

诊断报告原始硬件上限、range ABI、启用状态、样本数、回调Hz及最大间隔。该Hz只是独立探针回调率，不是系统各个视图FPS或物理面板扫描率。即使读到120也不能证明全局120；若仍59.95则说明该请求未获得120回调，不能宣称达成。

## 卸载和救援

- 正常：先关闭设置开关，等恢复通知，包管理器卸载 `com.mowang.ui120`，再重新启动用户空间。
- 终端（root，使用该越狱实际提供的dpkg）：`dpkg -r com.mowang.ui120`。rootless环境通常是 `/var/jb/usr/bin/dpkg -r com.mowang.ui120`，路径以设备为准。
- 若SpringBoard崩溃循环：用越狱工具安全模式/禁用tweak注入启动，再从包管理器卸载；不能进UI时用SSH卸载。RootHide走其管理工具，不猜测随机jbroot路径。
- 仅在rootless救援且无法卸载时，可将 `/var/jb/Library/MobileSubstrate/DynamicLibraries/StandaloneUI120.plist` 重命名为 `.plist.disabled` 后通过越狱工具重新加载用户空间，再卸载包；这会阻止新进程注入，已经运行的Hook不能靠改名卸载。
- 不提供自动重启脚本，安装不会自动开功能。用户空间重启可能丢失未保存数据，应先保存。

## 测试与构建

本地：

```sh
python3 StandaloneUI120/tests/contracts.py
clang -std=c11 -Wall -Wextra -Werror -pedantic StandaloneUI120/tests/policy.c -lm -o /tmp/ui120-test
/tmp/ui120-test
```

C/C++测试包含11个范围断言和128种安全开关组合。macOS CI另外提取实际SetRange/Restore函数体，结合Foundation及mock link测试最近请求恢复、关闭、低帧保留、后台新请求覆盖、弱生命周期、递归防护。mock不是iOS真机。

在独立分支使用已有 `build.yml` workflow_dispatch入口，复用 `ui120.yml`；原灵动监测job仅此分支skip。macos-14 + RootHide Theos + iPhoneOS16.5 SDK，矩阵rootless/roothide，只进入StandaloneUI120目录构建。包测试检查唯一动态库、三个宿主过滤器、PreferenceLoader、bundle Info、两份二进制arm64与arm64e切片。构建成功绝不是实机稳定性证据。

源码最小结构：`Tweak.m`、`Policy.h`、`Makefile`、`control`、过滤器、`prefs/`、`tests/`。可以在安装相应Theos的Mac上：

```sh
cd StandaloneUI120
THEOS_PACKAGE_SCHEME=rootless make package FINALPACKAGE=1
make clean
THEOS_PACKAGE_SCHEME=roothide make package FINALPACKAGE=1
```

## 必做实机验证

iPhone14 Pro Max / iPhone15,3 / iOS17尚未实测。安装后必须核实：默认关闭不影响UI；开关切换；原始120能力及ABI；解锁探针；通知/来电/横竖屏；锁屏与AOD立即停止改写；低电量和温度保护；退出保护不自动保活；开关关闭/卸载后重载恢复；长时间待机耗电和崩溃日志。不建议首次测试就连续跑高负载。设备热起来即停止，绝不为得到120而移除保护。
