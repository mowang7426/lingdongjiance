# v5.09+mem5：实时反色重复渲染优化

## 观察到的负担与根因

“实时反色”是设置面板的 `realtimeInvertText`，消费键是 `floatingTextOnlyColor == 4`。该模式保留系统合成器对实际字形后背景的反色；本次没有改颜色语义、滤镜参数、采样间隔或文字槽策略。

mem4 的文字窗更新沿用原来的刷新节拍（本次未改）：每轮均重新遍历 slot 并向 UILabel/CALayer 写入文字、字体、属性文字、对齐、行数、截断模式和几何。反色标签虽有缓存，但只比对 plain text/font/bounds/screen scale；属性文字与字形排版属性未参与缓存键；同值的 `realtimeInvertEnabled` 仍同步 backdrop。文字窗每轮生成相同的属性字符串（温度/电流行还会生成附件图标）；这可能使标签失效后重绘遮罩。每个可反色字形仍使用独立背景合成层/遮罩和既有滤镜链，叠加起来有额外合成工作；实际 GPU 耗时与卡顿程度未在真机测量。

## 修复范围

- `SBCPUTextBackdropLabel.m`：增加完整的排版缓存键（plain/attributed text、font、bounds、screen scale、alignment、行数、line-break、fit/minimum scale、baseline、semantic attribute）。完整命中时不更新遮罩内容、不触发新字形绘制；所有 capsule typography setters、属性文字、反色开关和颜色 setter 做同值短路，真正变更仍使遮罩重算。隐藏/脱离窗口仍关闭和清理，后续可重新启用。
- `SBCPUTextBackdropLabel.m` / `.h`：文字 HUD 的 attachment-backed attributed row 由同一生产 `SBCPUTextOnlyAttributedRow` 生成器构建；按 plain text、font、color 及当前 attributed value 缓存，仅有输入变化时重新构建。
- `Tweak.xm`：布局保留原数据源和刷新周期；主/副窗分别缓存 slot 布局，key 包含可见 slot mask、字号、粗体、可用宽度、间隔、FPS/current/RAM/CPU 字体预算和双行网络布局。只有几何变化时重算布局；slot/separator frame、host 空文本和隐藏状态做同值门控。FPS/font budget 沿用 mem4 的 `NSCache<UIFont *, NSNumber *>` descriptor key；没有把每轮测量误报成 cache miss，也未重做扫描 1000 个 FPS 形式的冷缓存工作。
- `control`：版本 `5.09+mem5`。工作只在 `feature/text-invert-performance-from-mem4`，以 mem4 提交为基线，不改 `main` 或 FPS clipping 分支。
- 新增 iOS Simulator UIKit 测试：编译并调用实际 `SBCPUTextBackdropLabel` 生产类。测试编译宏仅将私有 `CABackdropLayer` 替换为普通 CALayer，以真实生产 `SBCPUTextAlphaMask`、UILabel 字形渲染和缓存逻辑计数；生产包没有测试注入代码。另加入 Rootless/RootHide DEB 架构、Mach-O slice、每个 CodeDirectory 逐页 hash、包 SHA256 检查。

## 测试含义和限制

UIKit 测试计划：1000 次同值 setter/layout 事件流应得到 1000 次 cache hit、0 次 mask refresh、0 次 backdrop create、0 次属性文字重建；真实文字、font/粗体、alignment、frame、screen scale 变化应按需刷新；开关/隐藏状态应清理/可再建；字体 8/13/18/24pt、regular/bold、left/center/right、1x/2x/3x，5 种普通/含附件文本对比生产 alpha-mask 与参考 UILabel 的像素数据，并覆盖双窗相同字形。测试记录模拟器 1000 轮的 wall-clock 时间，只用于同一 runner 上的 UI 操作对比，不能外推到 iPhone。

模拟器不具备 iOS SpringBoard 私有背景合成路径。本测试将测试图层作为 mask host，不验证 `CABackdropLayer` 或私有 CAFilter 支持，更不证明 GPU 合成提速。保留 blur/contrast/saturate/invert 配方与每指标背景层数量，避免改变实时效果；层数/滤镜的 GPU 成本仍是合理的剩余疑点，应在目标设备开关反色前后实测。模拟器和 CI 不能保证真机“完全不卡”；本次未安装、注销或重启设备。

CI 在 `macos-15`：先跑原有 UIKit 字体/slot/内存/CPU 电流测试和新增反色测试，再分别构建 Rootless、RootHide，检查偏好 bundle，运行包架构、Mach-O 双 slice、CodeDirectory 代码页 hash 和 DEB SHA256 验证。不得将测试通过解读为设备合成器或温控表现已验证。
