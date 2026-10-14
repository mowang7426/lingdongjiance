# 灵动监测5.05 大核频率兼容报告

## 结论和分级

5.05从正式5.04提交`5c4756cc6bdf0979c9716112a39070cb34bf4b88`建立独立分支`compat/5.05-dynamic-pcore`、worktree `/var/minis/workspace/lingdong-5.05`，不改main或5.04旧树。

不是全机型实测版。A14/A15/A16/A17 Pro增加**结构满足时的算法放行**；A13二进制状态仍拒绝，状态`unverified-chip-mapping`。所有机型现有明确Hz/MHz/GHz单位的P核状态通道算法不变。唯一真实输入验证仍为iPhone14 Pro Max（iPhone15,3）iOS17.0 build21A329两份用户上传快照；新增机型、其他系统、实际越狱权限没有真机验证。CI编译和合成测试不能变成真机支持结论。

## 全系列身份矩阵

以下每一型号都是2P+4E的产品CPU拓扑，但**产品核数不证明IOReport通道拼写**；本实现拒绝未知拼写，不按CPU4/CPU5推断P核。不存在11 mini/Plus、12/13 Plus、14/15 mini或单独名为Max的型号。

|产品|hw.machine|芯片|二进制映射状态|
|---|---|---|---|
|11|iPhone12,1|A13|未放行，需芯片表归属/通道证据|
|11 Pro|iPhone12,3|A13|未放行|
|11 Pro Max|iPhone12,5|A13|未放行|
|12 mini|iPhone13,1|A14|条件算法放行，待真机|
|12|iPhone13,2|A14|条件算法放行，待真机|
|12 Pro|iPhone13,3|A14|条件算法放行，待真机|
|12 Pro Max|iPhone13,4|A14|条件算法放行，待真机|
|13 mini|iPhone14,4|A15|条件算法放行，待真机|
|13|iPhone14,5|A15|条件算法放行，待真机|
|13 Pro|iPhone14,2|A15|条件算法放行，待真机|
|13 Pro Max|iPhone14,3|A15|条件算法放行，待真机|
|14|iPhone14,7|A15|条件算法放行，待真机|
|14 Plus|iPhone14,8|A15|条件算法放行，待真机|
|14 Pro|iPhone15,2|A16|条件算法放行，待真机|
|14 Pro Max|iPhone15,3|A16|17.0/21A329真实快照回归；其他系统待真机|
|15|iPhone15,4|A16|条件算法放行，待真机|
|15 Plus|iPhone15,5|A16|条件算法放行，待真机|
|15 Pro|iPhone16,1|A17 Pro|条件算法放行，待真机|
|15 Pro Max|iPhone16,2|A17 Pro|条件算法放行，待真机|

## 证据与放行边界

1. Hello CPU原deb SHA256 `8da1866839216c87a62b64e0547f97cc73f8016586570bf4295114172c51b8c7`；采用已有只读反汇编研究`hello-cpu-reverse/report.md`和`a16-mapping-followup.md`，没有执行/安装其温控工具。后续报告确认真实IORegistry属性参数、table5-sram、8字节LE、首uint32 Hz乘1e-6、运行时头部[0,0] IDLE占位、正向状态索引、PCPU使用表5。containsString:E筛选过宽，未照搬。没有恢复全部SoC分支，不能作为每一代独立真机证明。
2. macmon固定提交[afdd572b12c9c301183569230a476bd4267b638b sources.rs](https://github.com/vladkens/macmon/blob/afdd572b12c9c301183569230a476bd4267b638b/src/sources.rs)：579-595 LE双uint32 DVFS；631-648 A1x按Hz、首选表1/5、备用acc-clusters；900-926 pmgr和P表5读取。注释明确A14–A18，A13缺少针对性佐证，因此不把字符串包含A1等同A13支持。macmon是macOS实现，不能证明iOS版本和权限。其M4+ kHz、M5+不同tier、M6 pmgr-child差异说明不应机械泛化。本次保守拒绝pmgr-child，不复制任意acc-clusters备用表选择。
3. 机型身份核对公开[ipsw.me设备目录](https://api.ipsw.me/v4/devices)；芯片分代与Apple公开产品规格对应，特别14/14Plus=A15，15/15Plus=A16，而15Pro/Max=A17Pro。营销芯片身份用于门控，绝不用于频率值。
4. 真实A16 fixtures：idle SHA256 `5f28a4c95e56e059a628f5aaf102d7b72a4c14e7a47f213ead96c05df1893dcc`；load `6f6bdb1d333d596a220711cb5b32072c832d2d904b17f9677aca3343cc038bfe`。独立Fraction重算得到1447.190419554883、2074.549863668391 MHz。

## 实现规则

不固定17记录、636/3468端点，不套用A16频率值。每台设备读自己的唯一pmgr table5-sram及table5，长度必须一致、8*N、2<=N<=255；首字段严格递增、Hz维度合理，非SRAM首字段每条等于floor(65536000000000/Hz)。倒数表仅交叉验证，输出来自SRAM Hz，第二字段不冒充当前频率/电压。

完整P核必须恰为PCPU0和PCPU1，同CPU Stats/Core子组、24Mticks单位、同非零driver；全部状态恰为IDLE,V0P(N-1),...,V(N-1)P0且顺序完整。表数量、单调性、倒数一致本身都不能证明任意未知拓扑的P归属；因此芯片门控及精确P通道门控仍保留。前缀PACC/DIE未知iPhone拓扑不在二进制放行边界内。若acc-clusters存在，必须为两条8字节且E type0/table1与P type1/table5；未知tier/表键拒绝，不临时改选E表。

结果=sum(MHz*deltaResidency)/sum(active deltaResidency)。IDLE排除，负计数、重复/缺失核、未知状态、零活动fail closed；不利用率乘最高频率、不读标称最大冒充当前、不P失败回E。

保留原串行队列、0.9秒请求合并、0.5–5秒窗口、3秒缓存、息屏清空与失败替换缓存。无新增timer/sleep/硬件写入。Tweak.xm及其他功能源文件不修改。

## 最小诊断路径

`/var/mobile/Library/Logs/LingdongPcore-5.05-status.plist`：版本、型号、OS、芯片、状态、窗口及加权MHz；最多8通道的名称/单位/状态数/首尾标签、最多4节点的属性长度，无驻留大表或原始CFData。状态变化才写，至少300秒限频。包括unsupported-model、unverified-chip-mapping、invalid-or-ambiguous-pmgr-table5、unverified-pcore-topology、incomplete-or-unverified-state-map、missing-pcore，以及原有libIOReport/订阅/样本/delta失败与零活动状态。API失败单列，不伪装芯片不支持。

A13下一步需只读诊断收集明确CPU Core通道全名、完整状态名字/正向序号、driver/unit、pmgr候选属性及原始CFData、两次采样delta、hw.machine/OS/build；先验证表P归属及记录单位，不靠核序号。其他芯片若状态文件拒绝，同样补完整空闲/负载快照。正式版仅短摘要，不常驻导出大表。

## 回归和构建

真实A16 native测试直接包含生产.m，保持两个真实数值、重复节点/核、表缺失/长度、倒数破坏、频率重复、单位/driver不一致、状态重排/缺失、负计数、零活动等异常。

新增`pcore_structural.m`明确标为SYNTHETIC：N=2/7/19/31/255，全16个条件放行型号、A13三型号/未知型号拒绝、未知PCPU拓扑/CPU4、缺核、acc-clusters未知、kHz单位、缺状态。它测试算法和身份表，不代表新真机样本。原有接线/触摸/双行网速/FPS/电池等全部CI回归保留，双制式workflow379364365另见构建结果附录。
