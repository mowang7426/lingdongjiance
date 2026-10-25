#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "../PeachDock/SBCPUPeachDockPolicy.h"
#import "../PeachDock/SBCPUPeachDockDisableIPC.h"

@interface SBCPUPeachDockController : PSListController
@property(nonatomic, copy) NSString *peachDisableNonce;
@property(nonatomic) BOOL peachDisableCancelled;
@end
@implementation SBCPUPeachDockController
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    self.title = @"滚动 Dock（实验性）";
    NSMutableArray *items = [NSMutableArray array];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"iOS 16.x · 运行时能力保护"];
    [group setProperty:@"5.09+peach2 实验功能，默认关闭。来自 INFINIDock16-Reborn，不是锁帧模块。仅 iOS 16.x 且完整 ABI、Dock 解档与关闭事务能力均匹配时安装；未知能力拒绝，iOS 17 暂不支持。替身测试不等于 16.2 真机验收，勿与原版 INFINIDock 同开。设置生效需要用户手动注销。" forKey:@"footerText"];
    [items addObject:group];
    NSArray *names = @[@"启用滚动 Dock（默认关）", @"分页（关为连续横滚）", @"分页弹簧吸附", @"边缘缩小与模糊（默认关）"];
    NSArray *keys = @[@"peachDockEnabled", @"peachDockPaging", @"peachDockSpring", @"peachDockEdge"];
    NSOperatingSystemVersion v = NSProcessInfo.processInfo.operatingSystemVersion;
    BOOL approved = SBCPUPeachDockProfileApproved((int)v.majorVersion, (int)v.minorVersion);
    for (NSUInteger i = 0; i < keys.count; ++i) {
        PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:names[i] target:self
            set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:)
            detail:nil cell:PSSwitchCell edit:nil];
        [s setProperty:keys[i] forKey:@"key"];
        [s setProperty:@(i == 1 || i == 2) forKey:@"default"];
        [s setProperty:@(approved) forKey:@"enabled"];
        [items addObject:s];
    }
    PSSpecifier *recovery = [PSSpecifier groupSpecifierWithName:@"关闭与卸载安全"];
    [recovery setProperty:@"卸载前必须先将多余图标移出 Dock，退出编辑与拖放，保持 Dock 可计数且不超过 4 个，再用本开关关闭并手动注销。关闭先向 SpringBoard 请求带 nonce 的许可；超额、未知、忙碌或超时均不写禁用。成功后保留当前滚动视图，并暂停图标拖动和 Dock 拖入，直到您明确手动注销；不拦整个屏幕，不自动注销或 kill。写失败/取消会请求释放未提交锁。外部强制卸载或其他软件直接改偏好无法保证安全，请勿直接卸载恢复布局。低电量、严重热状态、减少动态效果或降低透明度仅抑制视觉增强，不改原温控。" forKey:@"footerText"];
    [items addObject:recovery];
    _specifiers = items;
    return _specifiers;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    id value = CFBridgingRelease(CFPreferencesCopyValue((__bridge CFStringRef)key,
        CFSTR("com.yourname.sbcpufloating"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    return [value isKindOfClass:NSNumber.class] ? value : [specifier propertyForKey:@"default"];
}
- (void)peachNotice:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"滚动 Dock" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    if (self.view.window) [self presentViewController:alert animated:YES completion:nil];
}
- (BOOL)peachWrite:(id)value key:(NSString *)key {
    CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value,
        CFSTR("com.yourname.sbcpufloating"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    return CFPreferencesSynchronize(CFSTR("com.yourname.sbcpufloating"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.peachDisableCancelled = YES;
}
- (void)peachDisable:(PSSpecifier *)specifier {
    if (self.peachDisableNonce) return;
    NSString *nonce = NSUUID.UUID.UUIDString;
    self.peachDisableNonce = nonce;
    self.peachDisableCancelled = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *reply = SBCPUPeachDockDisableMessage(@"prepare", nonce);
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL prepared = [reply[@"status"] isEqual:@"prepared"];
            if (!prepared || self.peachDisableCancelled) {
                // A timed-out request may still reach SB; cancel is nonce-scoped
                // and tombstoned there, so a delayed prepare cannot lock later.
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                    NSDictionary *cancel = SBCPUPeachDockDisableMessage(@"cancel", nonce);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.peachDisableNonce = nil;
                        [self reloadSpecifier:specifier];
                        [self peachNotice:[cancel[@"status"] isEqual:@"cancelled"] ? @"未关闭。请确认 Dock 不超过 4 个、已退出编辑与拖放，再重试。" : @"未写禁用，撤销锁状态尚未确认。如果图标拖动暂停，请手动注销恢复；勿直接卸载。"];
                    });
                });
                return;
            }
            if (![self peachWrite:@NO key:@"peachDockEnabled"]) {
                // Restore the user's enabled preference before asking SB to
                // release. If rollback cannot sync, SB keeps the lock safely.
                BOOL restored = [self peachWrite:@YES key:@"peachDockEnabled"];
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                    NSDictionary *cancel = restored ? SBCPUPeachDockDisableMessage(@"cancel", nonce) : nil;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.peachDisableNonce = nil;
                        [self reloadSpecifier:specifier];
                        [self peachNotice:[cancel[@"status"] isEqual:@"cancelled"] ? @"写入失败，已撤销关闭并释放拖动锁。" : @"写入、回滚或撤销尚未确认，为安全保留拖动锁。请检查设置并手动注销，不要直接卸载。"];
                    });
                });
                return;
            }
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                NSDictionary *commit = SBCPUPeachDockDisableMessage(@"commit", nonce);
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.peachDisableNonce = nil;
                    [self reloadSpecifier:specifier];
                    [self peachNotice:[commit[@"status"] isEqual:@"committed"] ? @"已关闭并锁存。当前滚动视图保留，图标拖动和 Dock 拖入暂停。请手动注销后再卸载。" : @"禁用已写入；确认应答未收到，安全锁仍保留。请手动注销后核对，不要直接卸载。"];
                });
            });
        });
    });
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    if (self.peachDisableNonce) { [self reloadSpecifier:specifier]; return; }
    NSOperatingSystemVersion version = NSProcessInfo.processInfo.operatingSystemVersion;
    if (!SBCPUPeachDockProfileApproved((int)version.majorVersion, (int)version.minorVersion)) {
        [self reloadSpecifier:specifier];
        [self peachNotice:@"仅支持 iOS 16.x，并需要 SpringBoard 完整运行时能力门禁通过。"];
        return;
    }
    NSString *key = [specifier propertyForKey:@"key"];
    if ([key isEqual:@"peachDockEnabled"] && ![value boolValue] && [[self readPreferenceValue:specifier] boolValue]) {
        [self reloadSpecifier:specifier];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"关闭前确认"
            message:@"请先移出多余图标并退出编辑/拖放。允许关闭后将暂停图标拖动和 Dock 拖入，保留滚动视图直到您手动注销。卸载前必须完成此流程。"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"检查并关闭" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [self peachDisable:specifier]; }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    id previous = [self readPreferenceValue:specifier];
    if (![self peachWrite:@([value boolValue]) key:key]) {
        [self peachWrite:previous key:key];
        [self peachNotice:@"设置写入失败，未确认生效。"];
    } else [self peachNotice:@"设置已保存，下次手动注销后生效。能力不匹配时保持系统原行为。"];
    [self reloadSpecifier:specifier];
}
@end
