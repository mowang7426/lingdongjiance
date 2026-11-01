# 5.04 P-core 只读诊断（非正式实测频率发布）

版本：`5.04~pcore-diagnostic.1`，基线：`35886cf95936787b8d98ea5bce0a4964f0a0cc8d`。
独立分支/worktree；5.03/main 不变。包 ID 和其余组件不变，本诊断包用于替换测试，不可与5.03并装。

## 为什么没有猜测发布正式 5.04

Hello CPU 静态报告能证明 CPU Stats → IOReport subscription → samples delta → state name/residency 的只读路径，却未证明 iPhone 的 P/E 状态表后缀、状态索引及单位映射。5.03 原实现固定 states1/states5、跳过状态0、按包含 E 分类、混用 Core/Complex、在 P 失败时回退 E，并永久约0.37秒循环，还保留最后成功值。以上均已从频率模块移除。

参考可验证开源 macmon，固定提交 `afdd572b12c9c301183569230a476bd4267b638b`：
- https://github.com/vladkens/macmon/blob/afdd572b12c9c301183569230a476bd4267b638b/src/sources.rs
- https://github.com/vladkens/macmon/blob/afdd572b12c9c301183569230a476bd4267b638b/src/metrics.rs
其签名佐证 CFString 返回、signed int64 residency、CFRelease subscription/sample；其实际测试列出 PCPU、DIE_N_PCPUx_CPUy、PACCx_PCPUy 和 IDLE/OFF/DOWN。其 Mac DVFS 代码说明表为小端 freq/voltage 8字节对，但 Hz/kHz随芯片改变，且较新机型有acc-clusters、pmgr-child差异。不能把 Mac 机型表直接当作 iPhone 证据。本实现未移植该表解码或映射，代码独立实现，不使用其推测频率常量。

## 显示算法与边界

只统计 CPU Stats / CPU Core Performance States 的明确 PCPU 通道，不把 Complex 重复相加。支持完整匹配 PCPU数字、DIE_数字_PCPU数字_CPU数字、PACC数字_PCPU数字等；未知核心名使结果不可用，E/M 核不参与。要求相同非空驻留单位和同驱动来源；所有 P-core 非闲置状态名必须能直接解析 `Hz/kHz/MHz/GHz`，V0P1/P1/裸数字不能解析；即使未知状态驻留为0也拒绝。表仅原样采集，不参与计算。

有效窗口：`F = Σ_core,state(MHz_state × deltaResidency) / Σ_core,state(active deltaResidency)`。
IDLE/OFF/DOWN 分子分母均排除，表示整个采样窗口内、按活跃驻留时间加权的 P-core 频率，而不是瞬时时钟、全CPU频率、利用率乘最大频率或包含idle的有效吞吐频率。全部idle、不完整映射、负delta、重复通道、异源/异单位时显示 `--`。这条条件算法不代表当前真机一定有带单位的状态名；常见 VnPm 状态预期显示不可用。

普通浮窗、浮窗1/2文字行共用原cpuFreqLabel；顶部和详情也来自同一 getter，失败不显示0G/0MHz。没有新设置，没有修改FPS、CPU占用、网速、温控充电、触控/拖动、双行布局或120相关逻辑。

## 调度与生命周期

沿用现有1–2秒数据刷新；没有新timer、sleep或永久循环。主线程只读缓存并派发请求；串行队列负责所有私有API/CF对象/注册表/诊断文件。多视图请求合并，最多1项在途、0.9秒内不重复取样。相邻真实样本求delta，mach_continuous_time覆盖睡眠；窗口小于0.5秒、大于5秒、拓扑变化先重建基线。黑屏通知清空订阅/基线/缓存；读取失败清空或重建，API/订阅失败有限退避。3秒过期缓存不可用，失败覆盖最后成功值。CF样本/delta/订阅/通道和IOKit对象按生命周期释放；singleton、dylib句柄和单次通知注册为进程生命周期资源。

## 真机反馈步骤（仍需验证，不由CI代替）

1. 选择匹配越狱的rootless或roothide诊断deb，保留5.03安装包用于回退。
2. 打开浮窗及频率显示，保持亮屏40秒；空闲和受控CPU负载分别运行40秒，复制下面文件（下一场景会覆盖）。
3. `/var/mobile/Library/Logs/LingdongPcore-5.04-diagnostic.plist` 包含机型/OS、状态、窗口秒数、Core/Complex通道名、driver/unit、状态名/signed驻留，以及AppleARMIODevice节点的原始voltage-states*/acc-clusters NSData。状态baseline-cumulative-not-delta表示累计基线；其他采样状态记录delta。每30秒最多覆盖一份，原始表总量不超过1MB。不采集设备序列号/账号/网络内容。
4. 测试熄屏/唤醒、停用再启用、1秒/2秒刷新、普通/顶部/文字1/2/详情频率一致性。首样本和唤醒允许--，无权限/未知表必须--，不能保留旧值。
5. 回归浮窗2 ON穿透、OFF可拖动及双行网速、FPS和CPU占用、温控充电。真机反馈需同时提供机型/iOS/越狱框架和上述原始plist；仅截图数字无法证明状态映射正确。

下一步必须核对 iPhone 实际 P-core 通道、状态顺序、表对应关系、频率字段和单位，才可增加有证据的只读表映射并发布正式5.04。本诊断包不宣称已完成真机大核实测验证。
