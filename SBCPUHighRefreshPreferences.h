#ifndef SBCPU_HIGH_REFRESH_PREFERENCES_H
#define SBCPU_HIGH_REFRESH_PREFERENCES_H
#import <CoreFoundation/CoreFoundation.h>
#define SBHR_DOMAIN CFSTR("com.yourname.sbcpufloating.highrefresh")
#define SBHR_KEY CFSTR("springBoard120HzEnabled")
#define SBHR_NOTIFY "com.yourname.sbcpufloating.highrefresh/changed"
static inline BOOL SBHRReadEnabled(void) {
    if (!CFPreferencesSynchronize(SBHR_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)) return NO;
    CFPropertyListRef value = CFPreferencesCopyValue(SBHR_KEY, SBHR_DOMAIN,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL enabled = value && CFGetTypeID(value) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)value);
    if (value) CFRelease(value);
    return enabled;
}
static inline BOOL SBHRWriteEnabled(BOOL enabled) {
    CFPreferencesSetValue(SBHR_KEY, enabled ? kCFBooleanTrue : kCFBooleanFalse,
        SBHR_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    return CFPreferencesSynchronize(SBHR_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}
#endif
