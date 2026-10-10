# 开关持久化真机修复报告

分支：`motionx120-experimental`。基线：`b3ddf24`。

## 证据

- Root.plist 为温控键声明 `defaults=com.be-huge.insulation-prefs`，而控制器实际直接写 jbroot 映射后的 `/var/mobile/Library/Preferences/com.be-huge.insulation-prefs.plist`；PreferenceLoader 在重载时可能按 defaults 域把旧缓存写回。
- `getPreferenceValue:` 对未处理键返回 `nil`，会使 PSSwitch 在重载时退回默认假状态。
- 120Hz UI 与 MotionX runtime 已使用同一 domain/key 和 `kCFPreferencesCurrentUser/kCFPreferencesAnyHost`，但 Root.plist 的 defaults 元数据仍可引入旧值覆盖。
- 温控 payload 中的静态 insulation.dylib 无法在此环境运行验证；写路径通过 `jbroot()` 与 payload 的越狱路径保持一致。

## 修复

1. 移除 120Hz 及温控项的 Root.plist `defaults` 元数据，避免 view reload/default domain 回写覆盖权威存储；保留非目标 respring 项配置。
2. 温控写入继续使用锁文件、原子 plist 写入，并立即重新读取校验目标 key/value；校验失败视为保存失败，通知不会发送。
3. Root controller 未处理键 getter 改为返回 specifier default 或 `@NO`，不再返回 nil。
4. 保持 120Hz UI/runtime 的明确 CFPreferences scope；失败路径恢复 previous 值并提示用户。
5. 新增 `tests/switch_persistence.py`，检查每个目标键映射、无 defaults 覆盖、原子回读和非 nil getter；更新 motionx 静态测试适配无 defaults 设计。

## 验证

- `python3 tests/switch_persistence.py`：PASS
- `python3 tests/motionx_preferences.py`：PASS
- `git diff --check`：PASS
- 未能在 iSH 上运行 Apple Foundation/Theos 原生编译；CI build.yml 需在 macOS Actions 上完成 Rootless/RootHide 构建。

## 真机诊断

关闭温控后退出设置再进入，读取 `jbroot /var/mobile/Library/Preferences/com.be-huge.insulation-prefs.plist`，确认 `thermalPowerMode=off`；若仍恢复，收集写入后立即读取值、文件 owner/mode、路径以及 Darwin 通知接收方日志，重点确认运行中的 insulation 版本是否另有写回。120Hz 则分别在设置进程和 SpringBoard 用 CFPreferences 同一 current-user/any-host scope 读取 `system120HzEnabled`；若设置值为 true 而 runtime 为 false，检查 cfprefsd/domain host 及 SpringBoard reload 日志。此环境无法确认具体设备 daemon 是否覆盖文件，也无法运行静态 payload 的动态行为。
