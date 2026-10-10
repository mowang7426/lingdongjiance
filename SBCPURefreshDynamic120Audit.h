#ifndef SBCPU_REFRESH_DYNAMIC120_AUDIT_H
#define SBCPU_REFRESH_DYNAMIC120_AUDIT_H
#import <Foundation/Foundation.h>
#include <dlfcn.h>

// User-triggered evidence only: C symbols have no Objective-C type encoding.
// Never cast/call/hook the result. RTLD_DEFAULT does not load a new image;
// absence here does not prove absence in the device's dyld shared cache.
static inline NSDictionary *SBCPURefreshDynamic120Audit(void) {
    void *symbol = dlsym(RTLD_DEFAULT, "CADeviceDisableMinimumFrameDuration");
    Dl_info info = {0};
    BOOL located = symbol != NULL;
    BOOL ownerKnown = located && dladdr(symbol, &info) != 0 && info.dli_fname != NULL;
    NSString *image = ownerKnown ? [NSString stringWithUTF8String:info.dli_fname] : @"unknown";
    return @{
        @"sourcePackageSHA256": @"f92c89a35c7f344bc8a32a24788726ef4ae8c8a3f6c3b1c7aaf9a28083684091",
        @"strategy": @"C return-zero hook + hidden zero-frame UITextView in UIStatusBarWindow; NOT CADynamicFrameRateSource",
        @"cSymbolLookup": located ? @"export visible via RTLD_DEFAULT (not called)" : @"not visible via RTLD_DEFAULT; local/shared-cache symbol absence NOT established",
        @"cSymbolImage": image ?: @"unknown",
        @"cABI": @"unknown: replacement writes w0=0, original arguments/return type/semantics not established",
        @"statusBarInitializerABI": SBCPURefreshMethodABI(NSClassFromString(@"UIStatusBarWindow"), NSSelectorFromString(@"initWithFrame:")),
        @"textViewInitializerABI": SBCPURefreshMethodABI(UITextView.class, @selector(init)),
        @"implementation": @"blocked; no C invocation/hook, no hidden view, no dynamic source creation",
        @"safety": @"read-only on explicit diagnostic request; no timer, sampling, settings or thermal changes"
    };
}
#endif
