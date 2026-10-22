// Public VideoToolbox ABI only. Never tag an encoder from process-wide activity:
// the creation itself must occur inside a verified system RPMovieWriter call.
namespace {
using CreateFn = decltype(&VTCompressionSessionCreate);
using SetFn = decltype(&VTSessionSetProperty);
using InvalidateFn = decltype(&VTCompressionSessionInvalidate);
CreateFn originalVTCreate;
SetFn originalVTSet;
InvalidateFn originalVTInvalidate;
NSMutableSet *recordingEncoders;

OSStatus RecordingVTSet(VTSessionRef session, CFStringRef key, CFTypeRef value) {
    bool tagged;
    @synchronized ([NSMethodSignature class]) {
        tagged = [recordingEncoders containsObject:[NSValue valueWithPointer:session]];
    }
    bool override = H120RecordingActive() && tagged && key && CFEqual(key, kVTCompressionPropertyKey_ExpectedFrameRate);
    OSStatus status = originalVTSet(session, key, override ? (CFTypeRef)@120 : value);
    if (tagged) Event(@"vt-property", @{@"expectedFPSOverridden":@(override), @"status":@(status)});
    return status;
}
OSStatus RecordingVTCreate(CFAllocatorRef allocator, int32_t width, int32_t height,
    CMVideoCodecType codecType, CFDictionaryRef encoderSpecification,
    CFDictionaryRef sourceImageBufferAttributes, CFAllocatorRef compressedDataAllocator,
    VTCompressionOutputCallback callback, void *refcon, VTCompressionSessionRef *result) {
    bool active = ActiveRecordingContext(writerContextKey);
    OSStatus status = originalVTCreate(allocator, width, height, codecType, encoderSpecification,
        sourceImageBufferAttributes, compressedDataAllocator, callback, refcon, result);
    bool tagged = active && status == noErr && result && *result;
    if (tagged) {
        @synchronized ([NSMethodSignature class]) {
            if (!recordingEncoders) recordingEncoders = [NSMutableSet new];
            if (recordingEncoders.count < 8) {
                CFRetain(*result); // prevent stale pointer reuse before explicit invalidation
                [recordingEncoders addObject:[NSValue valueWithPointer:*result]];
            } else tagged = false;
        }
        if (!tagged) { Event(@"vt-capacity", @{@"reason":@"session-limit-fail-closed"}); return status; }
        OSStatus setStatus = originalVTSet(*result, kVTCompressionPropertyKey_ExpectedFrameRate, (CFTypeRef)@120);
        Event(@"vt-request", @{@"requestedFPS":@120, @"setStatus":@(setStatus)});
    }
    Event(@"vt-create", @{@"systemContext":@(active), @"tagged":@(tagged), @"status":@(status)});
    return status;
}
void RecordingVTInvalidate(VTCompressionSessionRef session) {
    bool owned;
    @synchronized ([NSMethodSignature class]) {
        owned = [recordingEncoders containsObject:[NSValue valueWithPointer:session]];
        [recordingEncoders removeObject:[NSValue valueWithPointer:session]];
    }
    originalVTInvalidate(session);
    if (owned) CFRelease(session);
}
void InstallVT(void) {
    if (originalVTCreate) return;
    void *create = dlsym(RTLD_DEFAULT, "VTCompressionSessionCreate");
    void *set = dlsym(RTLD_DEFAULT, "VTSessionSetProperty");
    void *invalidate = dlsym(RTLD_DEFAULT, "VTCompressionSessionInvalidate");
    if (!create || !set || !invalidate) {
        Event(@"vt-hook", @{@"installed":@NO, @"reason":@"public-symbol-missing"}); return;
    }
    // Install property/invalidate first so creation can never leave an untracked tag.
    MSHookFunction(set, (void *)RecordingVTSet, (void **)&originalVTSet);
    MSHookFunction(invalidate, (void *)RecordingVTInvalidate, (void **)&originalVTInvalidate);
    if (!originalVTSet || !originalVTInvalidate) {
        Event(@"vt-hook", @{@"installed":@NO, @"reason":@"hook-original-unavailable"}); return;
    }
    MSHookFunction(create, (void *)RecordingVTCreate, (void **)&originalVTCreate);
    Event(@"vt-hook", @{@"installed":@(originalVTCreate != nullptr), @"asyncPropagationSupported":@NO});
}
void ReloadRecording(void) {
    NSDictionary *preferences = H120ReadPreferences();
    bool master = [preferences[@"wantsEnable"] boolValue];
    bool toggle = [preferences[@"recordingEnabled"] boolValue];
    recordingActive.store(master && toggle, std::memory_order_release);
    if (!(master && toggle)) {
        NSArray *old;
        @synchronized ([NSMethodSignature class]) {
            old = [recordingEncoders.allObjects copy];
            [recordingEncoders removeAllObjects];
        }
        for (NSValue *value in old) CFRelease(value.pointerValue);
        [old release];
    }
    Event(@"configuration-read", @{@"master":@(master), @"recording":@(toggle),
        @"enabled":@(master && toggle), @"filePresent":@([[NSFileManager defaultManager] fileExistsAtPath:H120PreferencesPath() ?: @""]),
        @"source":@"explicit-jailbreak-mobile-file-no-CFPreferences-user-cache",
        @"reloadRequired":@(vsyncReloadRequired.load(std::memory_order_acquire)),
        @"restorePolicy":@"manual-replayd-reload-no-verified-reset",
        @"blacklistApplied":@NO, @"asyncPropagationSupported":@NO});
    H120InstallRecordingHooks();
    InstallVT();
}
std::atomic<bool> installPending(false);
void RecordingImageAdded(const struct mach_header *, intptr_t) {
    if (installPending.exchange(true)) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        installPending.store(false);
        H120InstallRecordingHooks(); InstallVT();
    });
}
void ObserveRecordingPreferences(void) {
    static int token;
    int status = notify_register_dispatch(H120PreferencesNotification.UTF8String, &token,
        dispatch_get_main_queue(), ^(int value) { (void)value; ReloadRecording(); });
    Event(@"preferences-observer", @{@"status":@(status)});
}
}
__attribute__((constructor)) static void InitializeRecording(void) {
    @autoreleasepool {
        if (![NSProcessInfo.processInfo.processName isEqualToString:@"replayd"]) return;
        Event(@"module-load", @{@"version":@"5.09+full3", @"process":@"replayd", @"uid":@(geteuid()),
            @"cadenceInstalled":@NO, @"cadenceReason":@"original-w0-ABI-proven-target-system-ABI-unverified"});
        ReloadRecording();
        ObserveRecordingPreferences();
        _dyld_register_func_for_add_image(RecordingImageAdded);
    }
}
