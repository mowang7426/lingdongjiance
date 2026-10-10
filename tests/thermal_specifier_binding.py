#!/usr/bin/env python3
"""Static binding checks + emitted native selector dispatch of production thermal branches.
The native harness mocks file I/O/UIKit only; it is not an iOS Preferences runtime test.
"""
import argparse
import pathlib
import plistlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
src = (ROOT / 'sbcpuprefs/SBCPUPrefsRootListController.m').read_text()
rows = plistlib.loads((ROOT / 'sbcpuprefs/Resources/Root.plist').read_bytes())['items']

def body(signature):
    start = src.index('{', src.index(signature)) + 1
    depth = 1
    for i in range(start, len(src)):
        depth += (src[i] == '{') - (src[i] == '}')
        if not depth:
            return src[start:i]
    raise AssertionError(signature)

keys = set(re.findall(r'@"([^"]+)"', body('static BOOL InsulationKey')))
thermal = [r for r in rows if r.get('key') in keys]
assert len(thermal) >= 5
for row in rows:
    if row.get('key') and row.get('cell') and not row.get('defaults'):
        assert row.get('get') == 'getPreferenceValue:', row
        assert row.get('set') == 'setPreferenceValue:specifier:', row
for row in thermal:
    assert 'defaults' not in row
getter = body('- (id)getPreferenceValue:').split('    if ([key isEqualToString:@"respringPreserveNativeUnlockEnabled"])')[0]
setter = body('- (void)setPreferenceValue:').split('    if ([key isEqualToString:@"respringPreserveNativeUnlockEnabled"])')[0]
assert 'return InsulationMode(prefs);' in getter
assert 'InsulationModeTitle' not in getter
assert '温控设置保存失败' in setter and '[self reloadSpecifier:specifier]' in setter
popup = body('- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:')
mode = next(r for r in thermal if r['key'] == 'thermalPowerMode')
for value in mode['validValues']:
    assert '@"' + value + '"' in popup
assert '[self setPreferenceValue:value specifier:specifier]' in popup

parser = argparse.ArgumentParser()
parser.add_argument('--emit-native', type=pathlib.Path)
args = parser.parse_args()
if args.emit_native:
    harness = r'''
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <assert.h>
static NSMutableDictionary *store;
static BOOL saveOK = YES;
static NSUInteger posts, reloads, alerts;
static NSString * const InsulationRuntimeNotify = @"com.be-huge.insulation.runtimeState";
static NSDictionary *InsulationReadPrefs(void) { return store; }
static BOOL InsulationWritePref(NSString *key, id value) {
    if (!saveOK) return NO;
    store[key] = value; return YES;
}
#define CFNotificationCenterPostNotification(center, name, object, info, immediately) (++posts)
#define dispatch_async(queue, block) block()
#define UIAlertControllerStyleAlert 0
#define UIAlertActionStyleDefault 0
@interface UIAlertAction : NSObject
+ (instancetype)actionWithTitle:(NSString *)title style:(NSInteger)style handler:(id)handler;
@end
@implementation UIAlertAction
+ (instancetype)actionWithTitle:(NSString *)title style:(NSInteger)style handler:(id)handler {
    (void)title; (void)style; (void)handler; return [self new];
}
@end
@interface UIAlertController : NSObject
+ (instancetype)alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(NSInteger)style;
- (void)addAction:(UIAlertAction *)action;
@end
@implementation UIAlertController
+ (instancetype)alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(NSInteger)style {
    assert([title isEqual:@"温控设置保存失败"]); assert(message.length); (void)style; return [self new];
}
- (void)addAction:(UIAlertAction *)action { (void)action; }
@end
@interface PSSpecifier : NSObject
@property(nonatomic, strong) NSDictionary *properties;
@property(nonatomic) SEL getter;
@property(nonatomic) SEL setter;
- (id)propertyForKey:(NSString *)key;
@end
@implementation PSSpecifier
- (id)propertyForKey:(NSString *)key { return self.properties[key]; }
@end
@interface Controller : NSObject
- (id)getPreferenceValue:(PSSpecifier *)specifier;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
- (void)reloadSpecifier:(PSSpecifier *)specifier;
- (void)presentViewController:(id)alert animated:(BOOL)animated completion:(id)completion;
@end
'''
    harness += '\nstatic BOOL InsulationKey(NSString *key) {' + body('static BOOL InsulationKey') + '}\n'
    harness += '\nstatic NSString *InsulationMode(NSDictionary *prefs) {' + body('static NSString *InsulationMode') + '}\n'
    harness += '\n@implementation Controller\n- (id)getPreferenceValue:(PSSpecifier *)specifier {' + getter + 'return nil; }\n'
    harness += '- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {' + setter + '}\n'
    harness += r'''
- (void)reloadSpecifier:(PSSpecifier *)specifier { (void)specifier; ++reloads; }
- (void)presentViewController:(id)alert animated:(BOOL)animated completion:(id)completion {
    (void)alert; (void)animated; (void)completion; ++alerts;
}
@end
static id readValue(Controller *target, PSSpecifier *s) {
    assert([target respondsToSelector:s.getter]);
    return ((id (*)(id, SEL, id))[target methodForSelector:s.getter])(target, s.getter, s);
}
static void writeValue(Controller *target, PSSpecifier *s, id value) {
    assert([target respondsToSelector:s.setter]);
    ((void (*)(id, SEL, id, id))[target methodForSelector:s.setter])(target, s.setter, value, s);
}
int main(int argc, const char **argv) { @autoreleasepool {
    assert(argc == 2);
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
    assert(plist);
    Controller *target = [Controller new]; store = [NSMutableDictionary new];
    NSUInteger tested = 0;
    for (NSDictionary *row in plist[@"items"]) {
        NSString *key = row[@"key"];
        if (!InsulationKey(key)) continue;
        ++tested;
        PSSpecifier *s = [PSSpecifier new]; s.properties = row;
        s.getter = NSSelectorFromString(row[@"get"]);
        s.setter = NSSelectorFromString(row[@"set"]);
        assert([readValue(target, s) isEqual:row[@"default"]]);
        NSArray *values = [key isEqual:@"thermalPowerMode"] ? row[@"validValues"] : @[@YES, @NO];
        for (id value in values) {
            NSUInteger before = posts;
            writeValue(target, s, value);
            assert([store[key] isEqual:value]);
            id actual = readValue(target, s); assert([actual isEqual:value]);
            assert(posts - before == ([key isEqual:@"thermalPowerMode"] ? 3 : 2));
            if ([key isEqual:@"thermalPowerMode"]) {
                NSUInteger index = [row[@"validValues"] indexOfObject:actual];
                assert(index != NSNotFound);
                assert([row[@"validTitles"][index] length] > 0);
            }
        }
        id previous = readValue(target, s);
        NSUInteger before = posts, oldReloads = reloads, oldAlerts = alerts;
        saveOK = NO; writeValue(target, s, @"cannot-save"); saveOK = YES;
        assert([readValue(target, s) isEqual:previous]);
        assert(posts == before && reloads == oldReloads + 1 && alerts == oldAlerts + 1);
        if ([key isEqual:@"thermalPowerMode"]) {
            store[key] = @"invalid"; assert([readValue(target, s) isEqual:@"off"]);
        }
        // Simulated external CC update must be read immediately through the selector.
        store[key] = row[@"default"]; assert([readValue(target, s) isEqual:row[@"default"]]);
    }
    assert(tested >= 5);
    puts("PASS: native plist selector dispatch, raw mode title mapping, switches, external update, failure reload/alert");
} return 0; }
'''
    args.emit_native.write_text(harness)
print('PASS: all non-defaults keyed cells bound; thermal getter/popup/render/failure contracts')
