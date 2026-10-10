#ifndef SBCPU_REFRESH_DIAGNOSTICS_H
#define SBCPU_REFRESH_DIAGNOSTICS_H
#import <Foundation/Foundation.h>
#import <roothide.h>
static inline NSString *SBCPURefreshDiagnosticPath(void) {
    const char *p = jbroot("/var/mobile/Library/Preferences/com.yourname.sbcpufloating.120diagnostic.plist");
    return p ? [NSString stringWithUTF8String:p] : nil;
}
#define SBCPU_REFRESH_DIAGNOSTIC_REQUEST "com.yourname.sbcpufloating.120diagnostic.request"
#endif
