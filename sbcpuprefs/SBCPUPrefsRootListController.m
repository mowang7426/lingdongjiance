#import <UIKit/UIKit.h>
#import <Preferences/PSSpecifier.h>
#import "SBCPUPrefsRootListController.h"
#import "../SBCPUChargeStore.h"
#import "../SBCPURefreshDiagnostics.h"
#import <notify.h>
#import <sys/file.h>
#import <fcntl.h>
#import <unistd.h>
#import <roothide.h>

static NSString * const InsulationPrefsPath = @"/var/mobile/Library/Preferences/com.be-huge.insulation-prefs.plist";
static NSString * const InsulationRuntimeNotify = @"com.be-huge.insulation.runtimeState";
static BOOL InsulationKey(NSString *key) {
    return [@[@"thermalPowerMode", @"thermalPreventDimmingEnabled",
        @"thermalSuppressNotificationsEnabled", @"thermalDisablePocketSunlightEnabled",
        @"thermalSunlightLockedEnabled", @"cpuMinPowerValue", @"thermalPuppetValue"] containsObject:key];
}
static NSString *InsulationPrefsFilePath(void) {
    const char *path = jbroot([InsulationPrefsPath UTF8String]);
    return path ? [NSString stringWithUTF8String:path] : nil;
}
// The bundled CC writes this jbroot file directly, not via cfprefsd. Never synchronize
// CFPreferences here: its cached domain may write stale keys back over the CC file.
static NSDictionary *InsulationReadPrefs(void) {
    NSString *path = InsulationPrefsFilePath();
    NSDictionary *prefs = path ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
    return [prefs isKindOfClass:[NSDictionary class]] ? prefs : @{};
}
static NSString *InsulationMode(NSDictionary *prefs) {
    NSString *mode = prefs[@"thermalPowerMode"];
    return [mode isKindOfClass:[NSString class]] &&
        [@[@"off", @"lowPower", @"fullPower"] containsObject:mode] ? mode : @"off";
}
static BOOL InsulationWritePref(NSString *key, id value) {
    NSString *path = InsulationPrefsFilePath();
    if (!path || !key || !value) return NO;
    int fd = open([[path stringByAppendingString:@".lock"] fileSystemRepresentation], O_CREAT | O_RDWR, 0666);
    if (fd < 0) return NO;
    if (flock(fd, LOCK_EX) != 0) { close(fd); return NO; }
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path];
    NSMutableDictionary *prefs = exists ? [NSMutableDictionary dictionaryWithContentsOfFile:path] : [NSMutableDictionary dictionary];
    BOOL ok = prefs != nil; // Do not replace an existing unreadable/corrupt plist.
    if (ok) {
        prefs[key] = value;
        ok = [prefs writeToFile:path atomically:YES];
        if (ok && geteuid() == 0) {
            // Settings may run as root; the CC and thermal daemon must still read it.
            ok = chown(path.fileSystemRepresentation, 501, 501) == 0 &&
                chmod(path.fileSystemRepresentation, 0644) == 0;
        }
    }
    NSDictionary *verified = [NSDictionary dictionaryWithContentsOfFile:path];
    ok = ok && [verified isKindOfClass:[NSDictionary class]] && [verified[key] isEqual:value];
    flock(fd, LOCK_UN);
    close(fd);
    return ok;
}

@interface SBCPUPrefsRootListController () {
    int _insulationNotifyToken;
    BOOL _insulationNotifyRegistered;
}
@end

@implementation SBCPUPrefsRootListController

- (void)insulationPrefsDidChange:(NSNotification *)notification {
    (void)notification;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf.isViewLoaded && strongSelf.view.window) [strongSelf reloadSpecifiers];
    });
}
- (void)viewDidLoad {
    [super viewDidLoad];
    __weak typeof(self) weakSelf = self;
    _insulationNotifyRegistered = notify_register_dispatch(InsulationRuntimeNotify.UTF8String,
        &_insulationNotifyToken, dispatch_get_main_queue(), ^(int token) {
            (void)token;
            typeof(self) strongSelf = weakSelf;
            if (strongSelf.isViewLoaded && strongSelf.view.window) [strongSelf reloadSpecifiers];
        }) == NOTIFY_STATUS_OK;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(insulationPrefsDidChange:) name:UIApplicationWillEnterForegroundNotification object:nil];
}
- (void)dealloc {
    if (_insulationNotifyRegistered) notify_cancel(_insulationNotifyToken);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];

    // Restore the root title when returning from a detail or host-restored page.
    self.title = @"灵动监测";
    self.navigationItem.title = @"灵动监测";
}



- (NSArray *)specifiers {
	if (!_specifiers) {
		_specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
	}
	return _specifiers;
}

// 录屏增强使用独立权威 store，避免 PreferenceLoader/cfprefsd 重进页面时
// 把旧缓存写回并把开关恢复为关闭。
- (id)getPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    // Insulation settings are displayed inside SBCPU but intentionally retain
    // Insulation's original preference domain so its original thermal daemon hook
    // reads exactly the same keys. This does not touch SBCPU charging preferences.
    if (InsulationKey(key)) {
        NSDictionary *prefs = InsulationReadPrefs();
        if ([key isEqualToString:@"thermalPowerMode"]) {
            return InsulationMode(prefs);
        }
        return prefs[key] ?: [specifier propertyForKey:@"default"];
    }
    if ([key isEqualToString:@"respringPreserveNativeUnlockEnabled"]) {
        CFPreferencesSynchronize(CFSTR("com.yourname.sbcpufloating"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPropertyListRef stored = CFPreferencesCopyValue((__bridge CFStringRef)key, CFSTR("com.yourname.sbcpufloating"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        id value = stored ? CFBridgingRelease(stored) : nil;
        return [value isKindOfClass:[NSNumber class]] ? @([value boolValue]) : @NO;
    }
    if (([key isEqualToString:@"system120HzEnabled"] || [key isEqualToString:@"dynamicSource120HzEnabled"] || [key isEqualToString:@"hiddenText120HzEnabled"])) {
        // Use the same explicit scope as MotionX; no direct jbroot plist writes
        // or PreferenceLoader/AppValue fallback domains can shadow this value.
        CFPreferencesSynchronize(CFSTR("com.yourname.sbcpufloating"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPropertyListRef stored = CFPreferencesCopyValue((__bridge CFStringRef)key, CFSTR("com.yourname.sbcpufloating"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        id value = stored ? CFBridgingRelease(stored) : nil;
        return [value isKindOfClass:[NSNumber class]] ? @([value boolValue]) : @NO;
    }
    if ([key isEqualToString:@"screenRecordingHighFrameRateEnabled"])
        return SBChargeRead()[key] ?: @NO;

    return [specifier propertyForKey:@"default"] ?: @NO;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (InsulationKey(key)) {
        if (InsulationWritePref(key, value)) {
            CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
            CFNotificationCenterPostNotification(center, (__bridge CFStringRef)InsulationRuntimeNotify, NULL, NULL, YES);
            CFNotificationCenterPostNotification(center, CFSTR("com.be-huge.insulation-executePuppetEvent"), NULL, NULL, YES);
            if ([key isEqualToString:@"thermalPowerMode"]) {
                CFNotificationCenterPostNotification(center, CFSTR("com.be-huge.insulation-restartThermalMonitor"), NULL, NULL, YES);
            }
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self reloadSpecifier:specifier];
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"温控设置保存失败"
                    message:@"未能确认偏好文件写入成功，已重新读取当前状态。请检查偏好文件访问权限后重试。"
                    preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            });
        }
        return;
    }
    if ([key isEqualToString:@"respringPreserveNativeUnlockEnabled"]) {
        CFPreferencesSetValue((__bridge CFStringRef)key, [value boolValue] ? kCFBooleanTrue : kCFBooleanFalse, CFSTR("com.yourname.sbcpufloating"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        if (CFPreferencesSynchronize(CFSTR("com.yourname.sbcpufloating"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost)) {
            notify_post("com.yourname.sbcpufloating/settingsChanged");
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.yourname.sbcpufloating.prefschanged"), NULL, NULL, YES);
        }
        return;
    }
    if (([key isEqualToString:@"system120HzEnabled"] || [key isEqualToString:@"dynamicSource120HzEnabled"] || [key isEqualToString:@"hiddenText120HzEnabled"])) {
        CFStringRef domain = CFSTR("com.yourname.sbcpufloating");
        CFStringRef preferenceKey = (__bridge CFStringRef)key;
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPropertyListRef previous = CFPreferencesCopyValue(preferenceKey, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        BOOL valid = [value isKindOfClass:[NSNumber class]];
        BOOL saved = NO;
        if (valid) {
            CFPreferencesSetValue(preferenceKey, [value boolValue] ? kCFBooleanTrue : kCFBooleanFalse, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            saved = CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            if (!saved) {
                // A failed sync can leave the attempted value in this process's
                // cache. Restore it before the getter refreshes the switch.
                CFPreferencesSetValue(preferenceKey, previous, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
                CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            }
        }
        if (previous) CFRelease(previous);
        if (saved) {
            notify_post("com.yourname.sbcpufloating/settingsChanged");
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.yourname.sbcpufloating.prefschanged"), NULL, NULL, YES);
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self reloadSpecifier:specifier];
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"120Hz 设置保存失败"
                    message:@"未能确认偏好设置写入成功，开关已重新读取当前状态。请检查偏好设置访问权限后重试。"
                    preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            });
        }
        return;
    }
    if ([key isEqualToString:@"screenRecordingHighFrameRateEnabled"]) {
        if (SBChargePatch(@{key: @([value boolValue])})) {
            notify_post("com.yourname.sbcpufloating/settingsChanged");
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.yourname.sbcpufloating.prefschanged"), NULL, NULL, YES);
        }
        return;
    }

}


// Insulation CPU 模式使用原生弹出选择器，避免 PSLinkListCell 在部分 iOS 17
// Preferences 环境中点击后进入空白页面。选项值保持 Insulation 原版键值。
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    NSString *key = [specifier propertyForKey:@"key"];
    if ([key isEqualToString:@"thermalPowerMode"]) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"CPU 模式"
            message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        NSArray<NSString *> *values = @[@"off", @"lowPower", @"fullPower"];
        NSArray<NSString *> *titles = @[@"苹果原生温控", @"模拟低电频率", @"防止温控降频"];
        NSString *current = InsulationMode(InsulationReadPrefs());
        for (NSUInteger i = 0; i < values.count; i++) {
            NSString *value = values[i];
            NSString *title = titles[i];
            NSString *actionTitle = [current isEqualToString:value]
                ? [NSString stringWithFormat:@"✓  %@", title] : title;
            [alert addAction:[UIAlertAction actionWithTitle:actionTitle style:UIAlertActionStyleDefault
                handler:^(__unused UIAlertAction *action) {
                    [self setPreferenceValue:value specifier:specifier];
                    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                }]];
        }
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        // iPad/部分偏好设置容器要求 actionSheet 提供锚点。
        alert.popoverPresentationController.sourceView = [tableView cellForRowAtIndexPath:indexPath];
        alert.popoverPresentationController.sourceRect = [tableView cellForRowAtIndexPath:indexPath].bounds;
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

- (void)show120HzDiagnostics {
    NSTimeInterval requestedAt = NSDate.date.timeIntervalSince1970;
    notify_post(SBCPU_REFRESH_DIAGNOSTIC_REQUEST);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.5*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:SBCPURefreshDiagnosticPath()];
        NSString *message;
        if (![d isKindOfClass:NSDictionary.class] || [d[@"generatedAt"] doubleValue] < requestedAt) {
            message = @"SpringBoard 未返回新诊断；不能确认模块已加载。请检查 SBCPURefreshRate 注入过滤、RootHide 插件启用名单及 respring 后装载状态。旧文件不作为已加载证据。";
        } else {
            NSMutableString *m = [NSMutableString stringWithFormat:@"宿主 SpringBoard pid: %@\n已加载: %@ / 开关: %@\n原始 UIScreen 能力: %@Hz\n请求: %@Hz\n%@\n暂停: %@\n实测回调: %.2fHz（采样 %.2fs）\nHook: %@\n",
                d[@"pid"], [d[@"loaded"] boolValue] ? @"是" : @"否", [d[@"enabled"] boolValue] ? @"开" : @"关",
                d[@"originalCapability"],d[@"requestedHz"],d[@"requestSelector"],
                [d[@"pauseReason"] length] ? d[@"pauseReason"] : @"无（请求中）",
                [d[@"callbackHz"] doubleValue],[d[@"sampleSeconds"] doubleValue],d[@"installedHooks"]];
            NSDictionary *text = d[@"hiddenTextExperiment"];
            [m appendFormat:@"隐藏文本开关: %@ / 已挂载: %@ / 创建次数: %@\nwindow: %@\n状态: %@\nguard: %@\n初始化尝试: %@（关闭后必须注销隔离）\n",
                [d[@"textEnabled"] boolValue] ? @"ON" : @"OFF", text[@"mounted"], text[@"createdCount"],
                text[@"windowClass"], text[@"status"], text[@"guard"], text[@"initializationAttempted"]];
            [m appendFormat:@"机型: %@ / 真实120硬件核对: %@\n",d[@"hardwareModel"], [d[@"hardware120"] boolValue] ? @"是" : @"否/未知（拒绝请求）"];
            [m appendFormat:@"宿主bundle: %@\nCADisableMinimumFrameDurationOnPhone: %@（只读，不改系统plist）\n调度限制: %@\n低电量: %@ / 热状态: %@\n私有策略: %@\n", d[@"hostBundle"] ?: @"未提供", d[@"phoneHighFrameRateGate"] ?: @"未提供", d[@"limitation"] ?: @"旧诊断未提供", d[@"lowPowerMode"], d[@"thermalState"], d[@"privatePolicy"] ?: @"未提供"];
            NSDictionary *audit = d[@"selectorABI"];
            for (NSString *key in [[audit allKeys] sortedArrayUsingSelector:@selector(compare:)])
                [m appendFormat:@"%@ = %@\n",key,audit[key]];
            [m appendFormat:@"\n动态实验: %@ / 保护: %@ / 探针: %@\n%@\n",d[@"dynamicEnabled"],d[@"dynamicGuard"],d[@"probeStatus"],d[@"dynamicExperiment"]];
            [m appendString:@"\n动态源/DisplayLink范围实验仅对SpringBoard主线程新请求生效；pause/reasons保留原行为。动态开关本身不持续keepalive；诊断按需3秒探针。关闭/保护不跨线程重放私有对象，尚无新请求的旧范围需关闭后respring彻底清除。hook安装成功≠触发≠真实120；回调Hz不是面板Hz或游戏FPS。基线测试请关闭旧120开关与其他高刷插件。"];
            message = m;
        }
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"120Hz 诊断" message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"刷新" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [self show120HzDiagnostics]; }]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)openMoWangSource {
	NSURL *url = [NSURL URLWithString:@"sileo://source/https://mowang7426.github.io/mowang/"];
	if ([[UIApplication sharedApplication] canOpenURL:url]) {
		[[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
	}
}

@end

