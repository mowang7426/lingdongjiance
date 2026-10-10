# 动态120HZ Rootless 1.1：实际逆向与灵动监测适配边界

## 结论
新上传包**确实不是 range-only 路线，也不是 CADynamicFrameRateSource 路线**。它仅注入 SpringBoard，安装两个 hook：QuartzCore 私有 C 符号 `CADeviceDisableMinimumFrameDuration` 的替代函数直接返回整数寄存器零；`UIStatusBarWindow -initWithFrame:` 的替代实现调用原 initializer，然后首次创建并挂入一个隐藏、零尺寸的自定义 UIView，其内部持有隐藏 UITextView。

不能据此断言“已解除60Hz”或“动态120已生效”。原 C 函数的完整签名、参数、返回类型与真假语义未由这个替代实现证明；隐藏 UITextView 是否触发高刷资格也未证明。未复制原作者 dylib，未移植这两个私有 hook。本分支仅把**手动只读调查**接入已有灵动监测 refresh 模块与原诊断面板，明确标记 blocked，不制造有效修复。

## 样本与方法
- 输入：`动态120HZ刷新率-Rootless-1.1-iphoneos-arm64.deb`，4534 bytes。
- deb SHA256：`f92c89a35c7f344bc8a32a24788726ef4ae8c8a3f6c3b1c7aaf9a28083684091`。
- Package `byg.iosios.net.fix120hz.rootless`；Version 1.1；Maintainer 搬运工；Author zqbb；声明依赖 substrate、firmware>=15.0；无设置项。
- 实际文件：`var/jb/Library/MobileSubstrate/DynamicLibraries/0fix120hz.dylib` 与同名 plist；没有 prefs bundle、daemon 或脚本。
- dylib 84576 bytes，SHA256 `b114bf7923f87d3dd6b4516c8d3bc246349d3d81bbc45f212825fb713f2d5a6c`。
- plist 实际解析为 `{'Filter': {'Bundles': ['com.apple.springboard']}}`。不是全App注入，包描述“不生效App不支持”也不构成能力证明。
- FAT容器只有 arm64e 切片，offset 0x4000，size 68192；虽然 deb 架构名称 arm64，MachO 实际 subtype ARM64E，含 PAC 指令与 ARM64E_USERLAND24 chained fixups。
- UUID `D335C4DB-FF9E-301A-9362-AB3236D3F2D6`；minOS15.0、SDK14.5、cryptid0；__text 0x7960..0x7c30 共0x2d0 bytes。
- 使用 dpkg-deb 实际解包，LLVM19 strings/符号表/段表/chained-fixups/完整反汇编，并自行解码相对 ObjC 方法表与链式 selrefs。地址均为**未加载切片虚拟地址**，不是运行时绝对地址；本样本这些段文件偏移等于切片地址，容器偏移再加0x4000。代码中没有硬编码地址。

## 证据地址与置信度
### 1. 构造器和 C hook：高置信度
`__init_offsets @0x7da0 = 0x7ab0`。构造器从0x7ab0开始：
- 0x7abc/0x7ac4：MSGetImageByName，参数 QuartzCore framework 完整路径。
- 0x7ac8/0x7ad0：MSFindSymbol，符号字符串 `_CADeviceDisableMinimumFrameDuration`。
- 0x7ad8：查找结果存到全局0xc178。符号表中这个同名符号是 `__DATA,__common` 的全局变量，不是其函数实现。
- 0x7adc：x2=0xc180（原函数保存槽）；0x7ae4：替代实现0x7b3c，PAC签名后x1；0x7af4 调 MSHookFunction(x0,x1,x2)。
- 0x7b3c `mov w0,#0`；0x7b40 `ret`。不调用原函数，不读参数，不检查低电量、锁屏/AOD、高温、机型或开关。
- 构造器未见 symbol NULL/类不存在分支，直接送给 substrate。不存在性如何被 substrate 处理不由样本保证。

**C ABI 阻塞：**可确认的是替代函数把W0写零（因此X0也清零），并直接返回；不能确认原函数是 `BOOL(void)`、`int(void)`、有参数的函数或 void 函数。浮点/结构返回并不能用这个实现推断正确。MSHookFunction 三参数调用形式明确，不等于被 hook 的函数签名明确。无 ObjC method encoding 可用于 C 函数验证；仅看到名字不能推断“disable”的真假极性。禁止把它直接写成 `bool (*)(void)` 并调用或 hook。这个包甚至没有可观察的原调用用于反推签名。

### 2. UIStatusBarWindow initializer hook：高置信度
0x7af8/0x7b00 objc_getClass("UIStatusBarWindow")；0x7b08 x1来自selref0xc0e0，解码为 `initWithFrame:`；0x7b0c x3=0xc188 原IMP保存槽；0x7b14 x2=0x7b44 替代IMP；0x7b38 跳 MSHookMessageEx。

0x7b44起：保存d0..d3（CGRect的四个double，HFA传参）以及self/_cmd；0x7b98 `blraaz x21` 调原IMP；返回对象保存在x20。0x7ba4读全局0xc170，0x7ba8已有对象则跳到0x7be8；否则：
- 0x7bb0 classref0xc108 => Fix120View；0x7bb4 objc_alloc。
- 0x7bb8..0x7bc4 清零d0..d3；0x7bc8调 initWithFrame:（CGRectZero）。
- 0x7bd0 将对象保存在0xc170；0x7bd8 release旧值；0x7bdc取新对象。
- 0x7be0 将**原 self x19**作为 addSubview: 接收者（不是原 initializer 返回对象x20）；0x7be4 addSubview:。
- 0x7bf0 返回原 initializer 的结果x20。

替代IMP相当于 `id hook(id self, SEL cmd, CGRect frame)` 的调用方式；对UIKit通常的initializer ABI支持证据强，但目标系统实际 method encoding 仍须现场读。原包没有核对类型、原返回nil或self被替换等场景，也没有随后 status bar 重建时重新挂载的路径。

### 3. 自定义 UIView 与隐藏 UITextView：高置信度；高刷作用：未证明
相对 method list0x7da8，flags0x8000000c、count4：
- initWithFrame: IMP0x7960，encoding `@48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16`。
- textView getter IMP0x7a78，encoding `@16@0:8`。
- setTextView: IMP0x7a88，encoding `v24@0:8@16`。
- .cxx_destruct IMP0x7a9c，encoding `v16@0:8`。

0x7994 objc_msgSendSuper2 原 UIView initializer；0x799c若nil跳过子视图初始化；0x79ac setHidden:YES；0x79b4 classref0xc100（chained bind import15）=> UITextView；0x79bc alloc_init；0x79cc setTextView:；0x79f4 textView setHidden:YES；0x7a20 addSubview:textView。没有文本、firstResponder、显示激活、动画、displaylink或 preferredFrameRateRange 设置。

selrefs：0xc0d8=addSubview:，0xc0e0=initWithFrame:，0xc0e8=setHidden:，0xc0f0=setTextView:，0xc0f8=textView。

对象所有权：属性metadata为 `T@"UITextView",&,N,V_textView`；0x7a98 setter用objc_storeStrong；0x7aac destructor用objc_storeStrong(...,nil)；0xc170长期持有全局Fix120View。没有removeFromSuperview、锁屏解除、温度恢复、停止hook或dealloc hook。可证明“首次挂载且长期持有”，不能凭空假设“每帧续租动态源”或“重建时安全恢复”。

## 和此前路线的严格对照
| 路线 | 实际机制 | 已证明/未证明 |
|---|---|---|
| motionx120-experimental fd4aaf5 | 独立拥有SpringBoard CADisplayLink，验证公开setter ABI，请求120/120/120；不改其他对象 | 保护条件与请求路径可审计；前次约59.95Hz，未证实120 |
| standalone-ui120 4a3fc52 | 独立range hook与手动短探针 | 用户真机3秒60.20Hz/181 samples/max interval33.36ms；能力120、ABI通过、启用=是仍非生效 |
| 新动态120 1.1 | C符号返回零 + 隐藏零尺寸UITextView | 与range-only有实质区别；原C ABI/语义及隐藏视图资格作用未证明 |
| 旧 ProMotion120 样本 | 旧strings含CADynamicFrameRateSource、initWithDisplay:、setHighFrameRateReasons:count:、CAHighFrameRateRestrictionEnabled等 | 是另一个复杂样本，不能把它的动态源方案归给新包 |

旧 `/tmp/promotion-disasm.txt` 共6865行，新包反汇编仅182行；旧 ProMotion120.dylib SHA256 `ed0d0d483735bf0157cc848f5704a3925f2206c40a5ecea4f9b70b96611dddeb` 与新包不同。新包全量strings及完整__text中没有 CADynamicFrameRateSource、setHighFrameRateReasons:count:、initWithDisplay:、setPreferredFrameRateRange:、CADisplayLink、thermal或lowPower等机制。完整代码规模和调用解析支持“未实施动态源调用”的高置信度结论，而不仅是字符串缺失猜测。

目标设备是 iPhone15,3 / iOS17.0。已知 phone plist gate absent、两个SB getter absent，动态源类的三个selector存在。这些事实**不验证新包 C 函数签名或隐藏UITextView的语义**；也不意味着不存在的SB getter应补造。动态源 initWithDisplay: 需要何种display、reason编号的意义/所有权/撤销协议仍不明确，不能创建对象并瞎猜reason count。

## 本次实际适配：仅调查，不是高刷修复
从 motionx120-experimental 的精确基线 fd4aaf5df4f0595283335c68dbb7cf259e7e440b 建立 `dynamic120-investigation`，原工作树仍保留 standalone-ui120；main与standalone refs不改。

新增 SBCPURefreshDynamic120Audit.h：只在用户点击原“120Hz诊断”请求快照时运行；用 `dlsym(RTLD_DEFAULT,"CADeviceDisableMinimumFrameDuration")` 查已加载导出，再用dladdr记映像来源。**不dlopen、不转换函数指针、不调用、不hook。** dlsym名字没有MachO前导下划线；MSFindSymbol需要的MachO名字包含下划线，二者不要混用。RTLD_DEFAULT未找到仅是导出不可见，不代表shared cache/local symbol不存在；查到也不证明签名、真假语义或现有hook链。

SBCPURefreshRuntime.h 在已有手动快照中增加 dynamic120Investigation；现有SBCPUPrefsRootListController诊断面板显示调查结果与blocked状态；ObjC initializer encoding只读记录，不据此调用私有对象。新增调查回归，接入原 macOS rootless/roothide CI。未添加高刷开关、未将默认值改ON、未改变注入范围、未引入原作者库。

文字位置锁定、横竖屏/文字anchor、温控与其他功能均未改；低电量、锁屏/AOD、熄屏、高温及未知状态的既有fail-closed策略保留。本次没有新计时器、持续测量、displaylink或温控绕过。注意基线原有开关ON时的keepalive displaylink及内存回调计数仍原样保留，本次**没有把它改成新的短探针**；默认OFF则无该link。只进行本次调查时保持开关OFF，仍可查看新增证据，不需要开启持续请求。

## 继续实施前必须满足的阻塞条件
1. 针对iOS17.0实际QuartzCore/shared-cache函数与调用点，确定 C 函数原型、返回寄存器类别、参数、是否副作用、真假语义；记录系统版本与映像UUID。函数存在不是通过。
2. 分离试验隐藏 UITextView、C hook、二者组合对SpringBoard调度的作用，使用每次仅3秒的手动短探针；回调与面板应分开表述。不能拿“屏幕流畅”或设置开关表示成功。
3. 若需动态源路线，必须另证 display对象取得方式、reason值定义、注册/撤销、生命周期与线程约束；现有三个selector存在不是可调用许可。
4. 可逆策略必须在低电量/锁屏AOD/熄屏/高温/未知状态下恢复原始行为、释放自有对象；不能复制原包永久全局hook且无保护的行为。还需处理initializer返回nil、self替换、状态栏重建、多窗口及其他tweak hook链。

## 回归与真机验收
本地已执行所有 tests/*.py（20项）与7个C策略测试，均通过；本地Linux无UIKit，原生ObjC/UI运行、arm64e装载与系统兼容依赖CI和真机，不能由文本回归证明。CI复用原流程构建完整灵动监测rootless/roothide而非独立包；CI结果及下载真实deb校验在交付中单独记录。

真机验收步骤：
1. 卸载/禁用 standalone-ui120 与原动态120/其他强刷tweak，避免双hook和污染；记录插件名单与设备/系统/jailbreak。新分支覆盖同包名 com.sbcpu.floating，先备份基线deb与prefs，切勿同时安装两种架构产物。
2. 根据越狱实际选rootless或roothide；respring后检查灵动文字锁定、温控、设置导航保持原状；RootHide确认SBCPURefreshRate的SpringBoard注入许可。
3. 保持高刷开关OFF，点击灵动设置原“120Hz诊断”：generatedAt必须新于本次请求，dynamic120Investigation存在，implementation=blocked，installedHooks=none。记录C可见性、来源、UIStatusBarWindow encoding；这是加载/调查验收，不是120验收。
4. 若比较已有range请求，仅短暂开启并在解锁、非低电量、常温时读取请求/回调及样本新鲜度；完成后关闭。此前约60Hz的数据继续作为失败/未达标基线，不能覆盖为成功。
5. 测试锁屏/AOD、熄屏、低电量、系统自然高温通知与未知状态应暂停。不要人为加热设备或禁用温控。文字锁定横竖屏、重启持久化、温控菜单/其他修改做独立回归。
6. 回退到 fd4aaf5 对应的灵动包并respring可撤销本次诊断改动；没有私有hook/隐藏视图需要另行回收。构建成功不等于真机稳定，也不等于120Hz。
