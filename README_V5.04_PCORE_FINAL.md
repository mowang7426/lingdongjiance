# 5.04 正式版：大核窗口活跃驻留加权频率

本版只更改频率模块、必要测试/fixtures、工作流测试步骤和版本元数据。CPU占用、FPS、网速、温控充电、浮窗2锁定ON穿透/OFF拖动及双行布局未改。正式分支独立于main、5.03和原5.04诊断worktree。

## 支持边界
新增二进制表映射只支持 iPhone15,3（iPhone 14 Pro Max / A16），iOS 17.0 build 21A329。硬件标识与系统版本/build均严格匹配，不扩展到其他A16设备或OS。其他平台原有显式Hz/kHz/MHz/GHz状态名路径保留；未确认的二进制表不猜测、不推广。

IORegistry只读枚举AppleARMIODevice服务；候选表必须唯一且节点名为pmgr。只读取voltage-states5-sram及voltage-states5，不依赖固定driver对象ID。两表必须为CFData、长度可被8整除、各17条/136字节。SRAM每条为LE uint32 Hz和第二字段，频率只取首字段/1e6；第二字段不当作MHz或硬件电压实测。频率必须严格递增，范围636000000..3468000000Hz且端点相同；非SRAM首字段必须逐条等于floor(65536*1e9/Hz)，只作为校验而非显示频率来源。

真实Core通道必须为PCPU0/PCPU1，CPU Stats / CPU Core Performance States，两核同driver、24Mticks、18个状态且严格顺序IDLE,V0P16,...,V16P0。VkP(16-k)对应原始SRAM[k]；IDLE并不消耗原始表记录。Complex、PCPM_IDLE和E核不参与。缺失/重复/乱序/无效单位/来源/负驻留及未知映射均fail-closed显示--；无活跃驻留也是--，不回退E核、不使用占用率*最高频率。

## 语义与证据
采用明确自定义语义：sum(MHz * delta active ticks) / sum(delta active ticks)，跨PCPU0/1按活跃ticks权重合并。排除IDLE/OFF/DOWN，不使用两核简单平均。称为“窗口活跃驻留加权频率”，不是硬件瞬时频率。

Hello CPU的静态证据闭合了实际IORegistry属性读取、LE记录解析、MHz转换、先添加IDLE零占位、PCPU选表5、状态正向索引到表的输入计算链。这不是本机Hello CPU动态实测，也不表示其显示输出端和全部归一化分支已恢复。本版实现和归一化语义独立。

真实delta fixtures保存在tests/fixtures/a16；独立Python整数/Fraction复算并用原生测试调用生产PComputeMapped/PA16Table/PCompute验收：

| 场景 | PCPU0活跃ticks / MHz | PCPU1活跃ticks / MHz | 合计ticks | 合并MHz |
|---|---|---|---|---|
| 空闲 | 2900925 / 1500.823926161483 | 2471769 / 1384.244901525992 | 5372694 | 1447.190419554883 |
| 负载 | 6917228 / 2016.568273302543 | 6684900 / 2134.546554772697 | 13602128 | 2074.549863668391 |

## 刷新、只读验证与真机验收
沿用原串行队列、原刷新触发、0.5..5秒delta窗口、缓存时效/息屏失效处理。无新增timer、无主线程sleep、无硬件写入。表在订阅建立时读取并在reset时失效。

正式版不周期性写驻留/二进制大表。/var/mobile/Library/Logs/LingdongPcore-5.04-status.plist只在状态变化时写简短状态、窗口、映射说明和频率，最多每300秒一次；不含channels或rawTables。因限流可能暂时保留上个状态，不作为精确时序记录。需要完整只读快照时使用保留且未修改的独立诊断版本，不将持续大表诊断混入正式包。

CI涵盖生产原生函数、真实fixtures、未知机型/build、坏节点/重复表/缺表/长度错误/非SRAM不匹配/非单调频率、单位/来源/核缺失重复和状态乱序/负计数/全闲置等负向测试，并保留原全量回归与Rootless/RootHide构建、解包回归。CI/fixture通过不是安装后真机频率验证。仍需用户在目标越狱真机安装相应包，确认权限、首次--后更新、空闲/持续负载变化、全闲置--、息屏/唤醒缓存失效、浮窗2手势及其他指标未回归。
