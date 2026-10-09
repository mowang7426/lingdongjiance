# 纯文字浮窗

设置 → 灵动监测 → 纯文字浮窗；默认关闭，根页面与 Info.plist 主类不变。

- 仅改变呈现：隐藏原浮窗背景、边框、阴影及装饰；沿用现有监测更新，将 CPU、频率、FPS、电量、温度、电流及 SIM 信号文本单行显示在透明 UILabel。八个独立指标开关初始全部开启，不继承普通浮窗开关，不显示温控或充电状态，不新建监测计时器。
- 左上角、顶部居中、右上角三种锚点；四向按钮每次 8 pt；可编辑 X/Y 偏移并直接拖动。预设清零偏移。字体 8–24 pt，独立于普通浮窗字号/缩放。
- 仅启用时绕过灵动岛顶部避让，仍限制在屏幕矩形边缘；顶部居中可能被硬件遮挡，不声称在灵动岛下方。
- 仅启用时状态栏吸附、自动折叠和键盘避让不生效；普通配置不被覆写。关闭恢复原浮窗可见性、边框阴影、透明度、普通位置、折叠状态及通常的避让/吸附策略。模式内拖动不会覆盖普通 LastFrame。
- 自动模式（0）：系统浅色外观黑字、深色外观白字；从 SpringBoard 主屏幕外观读取，未指定时回退其自有浮窗窗口外观，均未指定按浅色处理。不跟随前台 App 独立主题，不读取背景像素、不截图、不新增计时器。现有 traitCollectionDidChange 回调立即更新，不依赖液态玻璃开关或下一次采样。旧差值合成已移除；非实时反色模式及关闭时移除专用背景滤镜层。
- 颜色按钮顺序为自动（0）、实时反色（4）、自定义（3）、固定白字（1）、固定黑字（2），保留原编号、位置字号字段及其他布局。「自定义文字颜色」（3），使用原生 UIColorPickerViewController，禁用透明度，默认不透明蓝色 #007AFF。点击完成保存并启用自定义；选色后下滑关闭也保存，拖动选色时不反复发送通知。RGBA 独立存储于 com.yourname.sbcpufloating / floatingTextOnlyRGBA，严格校验类型、完整性和有限值，RGB 钳制 0–1，alpha 强制 1。模式 1/2 继续兼容固定白字/黑字；设置行显示当前模式勾选与自定义颜色预览。
- 温控核心、充电核心及其配置未修改。构建测试不能替代真机系统外观切换、选色面板、旋转、拖动及开关恢复验收。

## 实时反色（4）与来源

- 参考 [Lessica/TrollSpeed](https://github.com/lessica/TrollSpeed/tree/a609be260c8261ead36509c3bc4ded8479da9c40)，固定审计提交 `a609be260c8261ead36509c3bc4ded8479da9c40` 的 `sources/HUDBackdropLabel.mm`、`sources/HUDBackdropView.mm`。完整 Lessica MIT 声明在 `LICENSE.TrollSpeed`，与本文一同随包安装到 `usr/share/doc/sbcpufloating`。
- `SBCPUTextBackdropLabel` 仅替代 `textOnlyLabel`，仍为浮窗直接子视图。其内部 `CABackdropLayer` 按顺序应用 `gaussianBlur`（radius 50、normalizeEdges）、brightness -0.285、contrast 1000、saturate 0、invert；再用 `CATextLayer` 子类的白色 alpha 文字遮罩裁出字形，不绘制背景矩形。不是差值混合，不是截图采样。
- 遮罩用 CoreText 明确单行水平居中，按 ascent/descent 垂直居中基线，超宽整行等比缩字。开启立即同步 text/font/bounds；仅文本、字体、几何或屏幕 scale 改变时更新遮罩，所有层变更禁用隐式动画，布局调用 super。不每次监测 tick 重建滤镜；没有新增计时器、CADisplayLink 或全局 hook，实时背景来自系统合成器。
- 类/工厂探测、nil 返回及 KVC 异常均进入自动色后备，失败在进程内缓存，避免每次刷新重试；重新启动 SpringBoard 后可重试。原 UILabel 的 textColor 始终是有效后备色，不设置透明字。切到其他颜色、退出模式、全关指标均清理背景层与遮罩；隐藏随原标签及父视图生命周期。
- 当前输出仅有 `◉`、`▰`、数值、单位等单色文本，无彩色 Emoji 需求；TrollSpeed 原实现也无 Emoji 豁免逻辑，因此没有新增 Emoji 开关。
- 私有合成 API 在不同系统或层级下可能不可用或静默不生效；能力探测只能防可检测的失败，不能证明真机像素结果。须真机检查纯黑/白/灰背景、滚动内容、明暗分界、旋转/拖动、8–24 pt、超长行、全关再开、系统外观切换、退出恢复以及休眠/锁屏。模糊及反色有 GPU 合成成本，不声称零 GPU 开销。

验证：`tests/text_only_realtime.py` 检查滤镜顺序、参数、白色遮罩、立即同步、缓存、回退、清理、许可与构建接线，并在宿主编译执行颜色模式策略。源码测试不能替代 iOS SDK 编译及真机合成测试。
`tests/text_only_policy.c` 为可执行位置/避让/吸附/范围策略测试；tests/text_only_mode.py 检查控制器、默认值、无新增采样与打包资源；既有导航测试仍逐项保护全部原根页面行及 Info 主类，仅允许新增详情入口。
