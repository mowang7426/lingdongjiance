#import <UIKit/UIKit.h>
#import <Preferences/PSSpecifier.h>
#import "SBCPUPrefsRootListController.h"
#import "../SBCPUChargeStore.h"
#import <notify.h>

@implementation SBCPUPrefsRootListController

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
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
    NSSet *insulationKeys = [NSSet setWithArray:@[@"thermalPowerMode",
        @"thermalPreventDimmingEnabled", @"thermalSuppressNotificationsEnabled",
        @"thermalDisablePocketSunlightEnabled", @"thermalSunlightLockedEnabled",
        @"cpuMinPowerValue", @"thermalPuppetValue"]];
    if ([insulationKeys containsObject:key]) {
        CFPreferencesSynchronize(CFSTR("com.be-huge.insulation-prefs"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPropertyListRef stored = CFPreferencesCopyValue((__bridge CFStringRef)key,
            CFSTR("com.be-huge.insulation-prefs"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        id value = stored ? CFBridgingRelease(stored) : nil;
        if ([key isEqualToString:@"thermalPowerMode"]) {
            NSString *mode = [value isKindOfClass:[NSString class]] ? value : @"off";
            NSDictionary *titles = @{@"off": @"苹果原生温控",
                @"lowPower": @"模拟低电频率", @"fullPower": @"防止温控降频"};
            return titles[mode] ?: @"苹果原生温控";
        }
        return value ?: [specifier propertyForKey:@"default"];
    }
    if ([key isEqualToString:@"respringPreserveNativeUnlockEnabled"]) {
        CFPreferencesSynchronize(CFSTR("com.yourname.sbcpufloating"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPropertyListRef stored = CFPreferencesCopyValue((__bridge CFStringRef)key, CFSTR("com.yourname.sbcpufloating"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        id value = stored ? CFBridgingRelease(stored) : nil;
        return [value isKindOfClass:[NSNumber class]] ? @([value boolValue]) : @NO;
    }
    if ([key isEqualToString:@"screenRecordingHighFrameRateEnabled"])
        return SBChargeRead()[key] ?: @NO;

    return nil;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    NSSet *insulationKeys = [NSSet setWithArray:@[@"thermalPowerMode",
        @"thermalPreventDimmingEnabled", @"thermalSuppressNotificationsEnabled",
        @"thermalDisablePocketSunlightEnabled", @"thermalSunlightLockedEnabled",
        @"cpuMinPowerValue", @"thermalPuppetValue"]];
    if ([insulationKeys containsObject:key]) {
        CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value,
            CFSTR("com.be-huge.insulation-prefs"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSynchronize(CFSTR("com.be-huge.insulation-prefs"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFSTR("com.be-huge.insulation-executePuppetEvent"), NULL, NULL, YES);
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
        CFPropertyListRef currentRef = CFPreferencesCopyValue(CFSTR("thermalPowerMode"),
            CFSTR("com.be-huge.insulation-prefs"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        NSString *current = currentRef ? CFBridgingRelease(currentRef) : @"off";
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

- (void)openMoWangSource {
	NSURL *url = [NSURL URLWithString:@"sileo://source/https://mowang7426.github.io/mowang/"];
	if ([[UIApplication sharedApplication] canOpenURL:url]) {
		[[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
	}
}

@end

