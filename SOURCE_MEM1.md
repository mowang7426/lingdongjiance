# 5.09+mem1 · 双文字浮窗剩余内存

基线 `9eb7e4947e976da22a15c1945a598ce0f81afb63`（5.08）；不移植 Hello120Hz、Peach Dock。设置 → 纯文字浮窗 → 窗口1/窗口2 剩余内存（RAM），各自独立开关，默认关闭。开时 RAM 指标追加在已有指标末尾；旧开关、顺序、网速双行与反色、粗体、字号、负间距保留。无内存数据时 `RAM--`。

**定义**：`(vm_statistics64.free_count + vm_statistics64.inactive_count) × host_page_size`，超过物理容量时封顶。Mach `HOST_VM_INFO64` 的 free 已包括 speculative；purgeable 可与其他队列重叠，两项都不另加。inactive 可回收但不是即时/保证可供某进程分配；指标是全机空闲加可回收非活跃页的估计，不是进程限额、进程已用内存或存储空间。MB/GB 使用 1024 进制（即 MiB/GiB 数值）；>= 1 GB 显示一位小数，前缀 `RAM`。与既有“内存可用”详情共用采样，内核/页大小/完整 HOST_VM_INFO64 返回计数错误时标记无效，不伪造零。参考 Apple 开源 XNU `osfmk/kern/host.c` 的 `host_statistics64` 与 `osfmk/mach/vm_statistics.h` 的队列及 HOST_VM_INFO64_COUNT 定义；不可把 free 中的 speculative 重复加总，purgeable 也不是独立页队列。

两个浮窗仅从原 1–2 秒主线程刷新周期共享同一快照；采样结果保留至下一周期，缓存上限 1 秒且失败覆盖旧样本。关闭双指标时文字浮窗不触发采样；详情仍可自行读取。固定槽宽只在 font/weight 变化时计算并缓存，不随显示数值改变。保留 FPS120 5.08 定宽算法；没有设备安装、注销、温控或充电策略调整。CI iOS 模拟器可检查 UIKit 真实像素和原生 Mach 查询错误处理，但不能替代越狱设备上的 BackBoard、反色合成以及内存压力下运行验收。
