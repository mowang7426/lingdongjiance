#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "../PeachDock/SBCPUPeachDockPolicy.h"

@interface SBCPUPeachDockController : PSListController
@end
@implementation SBCPUPeachDockController
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    self.title = @"滚动 Dock（实验性）";
    NSMutableArray *items = [NSMutableArray array];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"兼容性保护：当前不可启用"];
    [group setProperty:@"5.09+peach1 开发快照。源为 INFINIDock16-Reborn，不是锁帧模块，不改变屏幕刷新率。现有材料仅说明 iOS 16.2 坐标语义，尚无已核实的 Dock 模型身份、完整 ABI 和无损恢复适配；16.2、17.0 及其他系统均不安装 Hook。不能与原版 INFINIDock 同时启用。" forKey:@"footerText"];
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
    [recovery setProperty:@"当前快照不会扩容，也不会改写图标数据库。未来适配启用前必须完成迁移验收：先保持滚动可访问，将超过原容量的图标逐一移回主屏，核对 Dock 不超过原容量后再关闭/卸载；不能直接卸载来恢复布局。不得抹除图标数据库或依赖系统自动丢弃超额图标。设置采用进程启动快照；未来可用版本修改后需要手动注销。本面板不会执行注销、kill 或重启。低电量、严重热状态、减少动态效果或降低透明度会关闭视觉增强，不改原温控。" forKey:@"footerText"];
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
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    (void)value; (void)specifier;
    // Deliberately no persistence or restart while there is no approved profile.
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"尚未通过兼容性验证"
        message:@"本开发快照禁用 Dock Hook；不接受启用请求，不会改变原有布局。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
