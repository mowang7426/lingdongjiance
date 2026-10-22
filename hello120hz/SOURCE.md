# 来源与范围

上传：Hello120Hz源码_1.zip；SHA-256 `3ad126deaea3adfc3ca3ee1ac202ae554cae5a86547d64a9fe9d836794760290`。
上传 control 作者/维护者 zqbb，原版本3.3.3-3。上传未提供 LICENSE，不能虚构开源许可或再分发授权；版权归原权利人，按用户提供源码集成。

灵动集成版本5.09+full6；基于功能分支 full5 提交 `89104b65e15bacef2afbe07634b0bbcc6b28c468` 增量收尾，不改 main/5.08。

按原包架构收敛为单 Hello 模块：唯一构造函数分发客户端/replayd/backboardd安全入口，Recording.mm 单文件MRC，其余ARC。保留安全签名门控、TLS finally；按原可验证证据恢复 capture VSync120/CMTime1/120、writer源帧率及关键帧120、有条件码率翻倍，不使用VT强依赖或全局encoder hooks。仍未恢复目标ABI未证实的 backboard cadence。

保留来源 UI 分组、图标、中英文、AltList、总开关、帧率、屏蔽异常、模式切换、HUD、重置及确认注销。新增默认关闭录屏开关、诊断导出及原风格“应用录屏设置”说明入口。没有已验证的特权 replayd 重载服务，因此按钮不会尝试 mobile kill 或冒充成功，仅通知偏好并引导越狱管理器；注销不是 replayd 重载。没有自动重启行为。

两模式过滤器都保留 SpringBoard/backboardd/replayd，升级只原子迁移本插件过滤器且保留用户UIKit模式，只清理精确旧独立录屏文件。诊断自检使用单模块路径，真实 nonce 回执 build50906。生产路由/录屏实现/安装迁移的回归测试与原其他功能回归全部保留。完整能力及真机限制见 CAPABILITIES.md；未声称120Hz/120fps已实际生效。
