#!/usr/bin/env python3
"""120Hz UI/runtime persistence contract; emit native CFPreferences round-trip test."""
from pathlib import Path
import plistlib
import re
import sys
import uuid

root = Path(__file__).resolve().parents[1]
prefs = (root / 'sbcpuprefs/SBCPUPrefsRootListController.m').read_text()
runtime = (root / 'MotionXPort.xm').read_text()


def block(source, signature):
    start = source.index('{', source.index(signature)) + 1
    depth = 1
    for i in range(start, len(source)):
        depth += (source[i] == '{') - (source[i] == '}')
        if not depth:
            return source[start:i]
    raise AssertionError(signature)


key = 'system120HzEnabled'
domain = 'com.yourname.sbcpufloating'
items = plistlib.loads((root / 'sbcpuprefs/Resources/Root.plist').read_bytes())['items']
item, = [item for item in items if item.get('key') == key]
assert item.get('defaults') is None and item['default'] is False
assert item['get'] == 'getPreferenceValue:'
assert item['set'] == 'setPreferenceValue:specifier:'
selector = f'if (([key isEqualToString:@"{key}"]'
getter = block(block(prefs, '- (id)getPreferenceValue:'), selector)
setter = block(block(prefs, '- (void)setPreferenceValue:'), selector)
reader = block(runtime, 'static BOOL SBCPURefreshEnabledForKey(NSString *key)')
assert f'kSBCPURefreshDomain = @"{domain}"' in runtime
assert f'kSBCPURefreshKey = @"{key}"' in runtime
for code in (getter, setter, reader):
    assert 'CFPreferencesSynchronize' in code
    assert 'CFPreferencesCopyValue' in code
    assert 'kCFPreferencesCurrentUser' in code and 'kCFPreferencesAnyHost' in code
    assert 'CFPreferencesCopyAppValue' not in code
    assert 'CFPreferencesAppSynchronize' not in code
    assert not re.search(r'\bjbroot\s*\(|\bwriteToFile\s*:', code)
assert domain in getter and domain in setter
assert '[value isKindOfClass:[NSNumber class]]' in getter and ': @NO' in getter
assert '[value isKindOfClass:[NSNumber class]]' in setter
assert 'CFBooleanGetTypeID()' in reader and 'CFNumberGetTypeID()' in reader
assert 'BOOL enabled = NO;' in reader and 'if (value) CFRelease(value);' in reader
assert '[value boolValue] ? kCFBooleanTrue : kCFBooleanFalse' in setter
assert setter.index('CFPreferencesSetValue') < setter.index('saved = CFPreferencesSynchronize')
success = block(setter, 'if (saved)')
assert 'settingsChanged' in success and 'prefschanged' in success
failure = block(setter, 'if (!saved)')
assert 'CFPreferencesSetValue(preferenceKey, previous,' in failure
assert 'CFPreferencesSynchronize' in failure and 'notify_' not in failure
assert 'reloadSpecifier:specifier' in setter and '保存失败' in setter
assert 'preferredStyle:UIAlertControllerStyleAlert' in setter
print('MotionX preference static contract: PASS')

if len(sys.argv) == 3 and sys.argv[1] == '--emit-native':
    # Compile the ACTUAL production getter/runtime and setter persistence portion
    # against Foundation, not a Python model or a duplicated preference helper.
    isolated = domain + '.tests.' + uuid.uuid4().hex
    save = setter[:setter.index('        if (saved)')]
    prelude = f'''#import <Foundation/Foundation.h>
#include <assert.h>
static NSString * const kSBCPURefreshDomain = @"{domain}";
static NSString * const kSBCPURefreshKey = @"{key}";
static id Read(void) {{ NSString *key = kSBCPURefreshKey; {getter} }}
static BOOL Runtime(void) {{ NSString *key = kSBCPURefreshKey; {reader} }}
static BOOL Save(id value) {{ NSString *key = kSBCPURefreshKey; {save} return saved; }}
'''
    harness = '''
static void Check(BOOL expected) {
    assert([Read() boolValue] == expected);
    assert(Runtime() == expected);
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc == 3) { Check(atoi(argv[2]) != 0); return 0; }
        CFStringRef domain = (__bridge CFStringRef)kSBCPURefreshDomain;
        CFStringRef key = (__bridge CFStringRef)kSBCPURefreshKey;
        CFPreferencesSetValue(key, NULL, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        assert(CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
        Check(NO);
        for (NSNumber *value in @[@YES, @NO, @YES, @NO]) {
            assert(Save(value));
            Check(value.boolValue);
            NSTask *task = [NSTask new];
            task.launchPath = [[NSProcessInfo processInfo] arguments][0];
            task.arguments = @[@"--read", value.boolValue ? @"1" : @"0"];
            [task launch]; [task waitUntilExit];
            assert(task.terminationStatus == 0);
        }
        assert(!Save(@"invalid")); Check(NO);
        for (id value in @[@2, @0, @"invalid", @[]]) {
            CFPreferencesSetValue(key, (__bridge CFPropertyListRef)value, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            assert(CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
            Check([value isKindOfClass:[NSNumber class]] && [value boolValue]);
        }
        CFPreferencesSetValue(key, NULL, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        assert(CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
        Check(NO);
        puts("MotionX native on/off, fresh-process, missing/malformed/NSNumber contract: PASS");
    }
    return 0;
}
'''
    Path(sys.argv[2]).write_text((prelude + harness).replace(domain, isolated))
