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


## 5.09+mem2：文字浮窗内存占用（RAM）

- 原 mem1 分支 `feature/text-free-memory-5.08` 保留不改；本分支以相同的两个配置键兼容既有开关，但语义更新为“内存占用（RAM）”。
- 两个文字浮窗各自独立开关、默认关闭，仍复用主刷新周期和至少 1 秒缓存，绝不为 label 新增采样、timer、daemon 或权限。
- 按 Inspector 0.6.7 的系统统计口径：`free = HOST_VM_INFO64.free_count × page_size`，`used = clamp(NSProcessInfo.physicalMemory - free, 0, physical)`；XNU 的 `free_count` 已含 speculative，不加入 inactive / purgeable。
- 显示为固定槽 `RAM已用/总量`：例如 `RAM5.19/5.49GB`；小于 1 GiB 时为 `RAM999MB/999MB`，读取失败 `RAM--`。GB 在总量小于 10 时保留两位小数，否则一位；固定宽度按最长已用/总量样例测量。
