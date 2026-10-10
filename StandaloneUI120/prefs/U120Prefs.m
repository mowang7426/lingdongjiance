#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <CoreFoundation/CoreFoundation.h>
#import <notify.h>
@interface U120Prefs : PSListController
@end
@implementation U120Prefs
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    CFStringRef domain = CFSTR("com.mowang.ui120");
    CFPreferencesAppSynchronize(domain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)[specifier propertyForKey:@"key"], domain);
    return value ? CFBridgingRelease(value) : [specifier propertyForKey:@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    CFStringRef domain = CFSTR("com.mowang.ui120");
    CFPreferencesSetAppValue((__bridge CFStringRef)[specifier propertyForKey:@"key"], (__bridge CFPropertyListRef)value, domain);
    CFPreferencesAppSynchronize(domain);
    notify_post("com.mowang.ui120.changed");
}
- (void)diagnose {
    notify_post("com.mowang.ui120.diagnose");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"按需短时测量"
        message:@"请保持解锁，等待5秒后点“读取诊断”。只测SpringBoard独立探针回调，不是屏幕扫描率；禁用/低电量/热状态/锁屏将拒绝或取消测量。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)result {
    CFPreferencesAppSynchronize(CFSTR("com.mowang.ui120"));
    CFPropertyListRef data = CFPreferencesCopyAppValue(CFSTR("Diagnostic"), CFSTR("com.mowang.ui120"));
    id value = CFBridgingRelease(data);
    NSString *message = [value isKindOfClass:NSString.class] ? value : @"没有结果：确认已重新加载SpringBoard、解锁并启动诊断。";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"UI120 实测诊断" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
