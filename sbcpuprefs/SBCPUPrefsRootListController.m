#import <UIKit/UIKit.h>
#import <Preferences/PSSpecifier.h>
#import "SBCPUPrefsRootListController.h"
#import "../SBCPUChargeStore.h"
#import <notify.h>
#import <sys/file.h>
#import <fcntl.h>
#import <unistd.h>
#import <roothide.h>

static NSString * const InsulationPrefsPath = @"/var/mobile/Library/Preferences/com.be-huge.insulation-prefs.plist";
static NSString * const InsulationRuntimeNotify = @"com.be-huge.insulation.runtimeState";
static NSString * const PiPStatusPath = @"/var/mobile/Library/Preferences/com.sbcpu.pip-experiment.status.plist";
static const char *PiPChanged = "com.sbcpu.pip-experiment.changed";
static const char *PiPStartRequest = "com.sbcpu.pip-experiment.start";
static const char *PiPStopRequest = "com.sbcpu.pip-experiment.stop";
static const char *PiPQuery = "com.sbcpu.pip-experiment.query";
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
static NSString *InsulationModeTitle(NSString *mode) {
    NSDictionary *titles = @{@"off": @"苹果原生温控", @"lowPower": @"模拟低电频率",
        @"fullPower": @"防止温控降频"};
    return titles[mode];
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
    flock(fd, LOCK_UN);
    close(fd);
    return ok;
}

@interface SBCPUPrefsRootListController () {
    int _insulationNotifyToken;
    BOOL _insulationNotifyRegistered;
    int _pipNotifyToken;
    BOOL _pipNotifyRegistered;
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
    _pipNotifyRegistered = notify_register_dispatch(PiPChanged, &_pipNotifyToken,
        dispatch_get_main_queue(), ^(int token) { (void)token; });
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(insulationPrefsDidChange:) name:UIApplicationWillEnterForegroundNotification object:nil];
}
- (void)dealloc {
    if (_insulationNotifyRegistered) notify_cancel(_insulationNotifyToken);
    if (_pipNotifyRegistered) notify_cancel(_pipNotifyToken);
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
            return InsulationModeTitle(InsulationMode(prefs));
        }
        return prefs[key] ?: [specifier propertyForKey:@"default"];
    }
    if ([key isEqualToString:@"respringPreserveNativeUnlockEnabled"]) {
        CFPreferencesSynchronize(CFSTR("com.yourname.sbcpufloating"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPropertyListRef stored = CFPreferencesCopyValue((__bridge CFStringRef)key, CFSTR("com.yourname.sbcpufloating"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        id value = stored ? CFBridgingRelease(stored) : nil;
        return [value isKindOfClass:[NSNumber class]] ? @([value boolValue]) : @NO;
    }
    if ([key isEqualToString:@"pipVideoCallExperimentEnabled"]) {
        CFPreferencesSynchronize(CFSTR("com.yourname.sbcpufloating"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPropertyListRef stored = CFPreferencesCopyValue((__bridge CFStringRef)key, CFSTR("com.yourname.sbcpufloating"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        id value = stored ? CFBridgingRelease(stored) : nil;
        return [value isKindOfClass:[NSNumber class]] ? @([value boolValue]) : @NO;
    }

    return nil;
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
    if ([key isEqualToString:@"pipVideoCallExperimentEnabled"]) {
        BOOL enabled = [value boolValue];
        CFPreferencesSetValue((__bridge CFStringRef)key, enabled ? kCFBooleanTrue : kCFBooleanFalse, CFSTR("com.yourname.sbcpufloating"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        if (!CFPreferencesSynchronize(CFSTR("com.yourname.sbcpufloating"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost)) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"PiP 设置失败" message:@"偏好写入失败，开关状态未确认。" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
        notify_post("com.yourname.sbcpufloating/settingsChanged");
        if (!enabled) notify_post(PiPStopRequest);
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

- (void)startPiPExperiment {
    CFPreferencesSynchronize(CFSTR("com.yourname.sbcpufloating"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPropertyListRef stored = CFPreferencesCopyValue(CFSTR("pipVideoCallExperimentEnabled"), CFSTR("com.yourname.sbcpufloating"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL enabled = stored && CFGetTypeID(stored) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)stored);
    if (stored) CFRelease(stored);
    if (!enabled) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"PiP 未启用" message:@"请先打开“启用 PiP 实验”开关。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    notify_post(PiPStartRequest);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self showPiPExperimentStatus]; });
}

- (void)stopPiPExperiment {
    notify_post(PiPStopRequest);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self showPiPExperimentStatus]; });
}

- (void)showPiPExperimentStatus {
    notify_post(PiPQuery);
    NSDictionary *status = [NSDictionary dictionaryWithContentsOfFile:PiPStatusPath];
    NSString *message = [status[@"message"] isKindOfClass:NSString.class] ? status[@"message"] : @"SpringBoard 插件未加载或尚未发布状态";
    BOOL active = [status[@"active"] boolValue];
    NSString *text = [NSString stringWithFormat:@"%@\n\n公开回调确认 active：%@\n更新时间：%@", message, active ? @"是" : @"否", status[@"updated"] ?: @"未知"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"PiP 真实状态 / 错误" message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)openMoWangSource {
	NSURL *url = [NSURL URLWithString:@"sileo://source/https://mowang7426.github.io/mowang/"];
	if ([[UIApplication sharedApplication] canOpenURL:url]) {
		[[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
	}
}

@end

