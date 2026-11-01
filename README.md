# SBCPUFloating V4.12.0（自适应屏幕版）源码包

## 目录结构

```
SBCPUFloating_V4.12.0_Source/
├── Tweak.xm                # 核心源码（7257 行，单文件）
├── SBCPUFloating.plist     # 注入过滤器（SpringBoard / Preferences / BatteryUsageUI）
├── Makefile                # THEOS 工程文件（含 roothide 支持）
├── control                 # 打包信息（com.yourname.sbcpufloating v4.12.0）
└── include/
    ├── roothide.h          # roothide 路径辅助
    ├── SBCPUThermalPaths.h # 偏好读写 / 路径工具
    └── SBCPUThermalPressure.h # 温控压力等级 API
```

## 编译方法

```bash
# 普通越狱（rootful）
make package

# roothide 越狱
make package THEOS_PACKAGE_SCHEME=roothide

# 产物在 .theos/_/... 或 packages/ 目录
```

## 本版本包含的功能

- 液态玻璃悬浮窗（透明度 / 磨砂 / 反色文字可调）
- 横屏迷你胶囊（四段：CPU / FPS / 电量 / 温度）
- 智能停充（80% 停止充电，可选涓流模式）
- 满血快充 / 充电保护
- 插件冲突检测（进程扫描 + 插件列表 + 崩溃日志）
- 双击打开设置（非全屏 + 动画）
- 横屏状态栏时间显示（HH:mm:ss）
- 深浅色自适应

## 注意事项

- 偏好键：`com.yourname.sbcpufloating`（CFPreferences）
- 依赖：mobilesubstrate、preferenceloader
- 最低 iOS 14.0


## 5.09+mem3：剩余内存（RAM）和电流间距

- 沿 feature/text-memory-used-5.08 增量修复，两个 ShowMemory 键保留原状态、独立生效，新安装默认关闭。
- 剩余 RAM = min(HOST_VM_INFO64.free_count × host_page_size, NSProcessInfo.physicalMemory)，溢出先饱和再封顶；不额外加入 inactive、purgeable 或 speculative。不是存储空间，也不是进程内存限额。
- 只显示 RAM256MB、RAM1.25GB 等空闲量；1024 进制，低于 1 GiB 显示整数 MB，较大单位小于 10 时两位小数，否则一位。阈值按未舍入数值选择单位，因此边界可能显示 RAM1024MB / RAM1024.0GB；读取失败 RAM--。绝不从截图的已舍入数字估计。
- 保留详情面板 used_bytes / total_bytes / page_size 接口；free = total - used 为整数精确值。共享至少 1 秒缓存和既有 1–2 秒刷新，不新增轮询。
- 根因：电流旧槽按 9×字号×0.65 粗估宽度，左对齐短读数，未用的符号/位数预算出现在 mA 与后续分隔点之间。RAM 原槽尾宽不导致其左侧空白，分隔点原为独立的统一间隔，并无 RAM 特有前置 padding。
- 电流改用 UIFont/CoreText 配置预算并右对齐固定槽，让 mA 固定贴近后续分隔点；覆盖 -10000..10000mA 与 --mA，不负偏移、不缩字、不按读数改框。RAM 用剩余量格式重算固定预算。字体缓存按 UIFont 区分字号/粗体，采样只查缓存；FPS120 原修复、CPU/充电/温控未改。
- tests/text_memory_uikit.sh 使用真实 iOS Simulator UIKit：8–24 普通/粗体，1–3×，电流完整格式域、RAM单位边界、固定槽/分隔点、字形遮罩一致性；样图明确为模拟器固定测试数据，非真机截图。
