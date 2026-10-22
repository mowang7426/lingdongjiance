# 最终功能矩阵（5.09+full1 验证版）

|截图项目|实现/偏好|验证和边界|
|---|---|---|
|启用调整|原 wantsEnable；缺省关闭；关闭和黑名单客户端全部透传|生产策略、模拟器原 controller 回归；目标越狱真机未验证|
|优选帧率|原 10/30/60/80/120；wantsFPS；QuartzCore 六个范围 trampoline 和两个 arbitration/restriction hooks 独立模块|HFA ABI/寄存器不改变其余参数；符号缺失日志并跳过，不保证设备实际120fps|
|屏蔽异常|selectedApps；原 AltList 动态子类、搜索、标识符、可见应用多选；排除当前 bundle hooks|依赖 com.opa334.altlist 已声明；真机实际应用枚举需 AltList/越狱环境验证；不是绕过越狱检测或防封|
|恢复默认|原注入配置只注入 SpringBoard/Preferences；UI 回到“全局注入”以便再次开启原模式|过滤器链接 mobile 所有的原配置文件；只影响新启动进程，原驻留模块需用户确认注销/重开应用；不修改其他插件|
|打开/关闭调试|原 CARenderServerGetDebugOption/SetDebugOption/SetDebugValue 手动动作|符号存在才调用；缺失提示；系统权限/真实 HUD 须真机验证，安装不会自动打开|
|重置|原 wantsEnable=false,wantsFPS=120,selectedApps=[]，不等同切换注入模式|偏好持久化与通知一致性测试|
|注销/点我生效|用户主动点击并二次确认后原 sbreload 路径调用；失败提示越狱管理器|没有执行实际注销；安装无新增自动注销|
|来源版本说明|来源3.3.3-3、灵动5.09+full1 分开显示|非声称灵动3.3.3-3|

## 明确不包含/未证实

最终用户取消录屏需求：不编译、不安装录屏源文件，不注入 replayd，也没有录屏入口。
上传 backboardd preferred_frame_duration/hardware_minimum_frame_duration 的 uint32_t 返回 ABI 仅凭 mangled 符号无法证实。已有本地公开 QuartzCore 头/符号和 CADisplayLink/DynamicFrameRateSource 反编译证据支持客户端 CAFrameRateRange 输入，但没有后台两个函数的返回约定证据。因此未安装后台 Hook、不注入 backboardd；这是显式未实现的后台 cadence，不宣称完整版120或所有硬件生效。需目标 iOS build 的这两个方法反汇编/调用点与量纲、真机符号解析和帧率轨迹后方可补齐，不冒猜 ABI 风险。

## 集成隔离与安装

仅原灵动根页新增一条 Hello 原 controller 入口；原浮窗/充电/温控/CPU 源码和反色未修改。新核心作为独立子工程；缺省配置只系统进程，开启全局由用户主动操作。两种包使用各自 Rootless/RootHide 路径解析。新过滤器安装脚本只操作自己的精确文件，不更改现有父目录权限/所有者，不覆盖用户已有注入配置或 wantsEnable，不自行安装到设备。包版本 5.09+full1 比旧5.10/5.11低，包管理器可能要求允许降级。

CI 通过仅说明编译、生产策略/控制器测试与打包检查通过，不等于越狱设备实测。真机验收：安装AltList→缺省总开关关闭→选择帧率→启用→验证 UI 动画轨迹；全局切换后用户确认注销并重开第三方；黑名单进程恢复原策略；关闭总开关透传；手动 HUD 打开/关闭；最后用户确认注销。勿用浮窗请求FPS替代面板真实刷新率证据。
