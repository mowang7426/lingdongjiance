// Original capture + writer request chain only. No process-wide encoder hooks.
namespace {
void ReloadRecording(void) {
    NSDictionary *preferences = H120ReadPreferences();
    bool master = [preferences[@"wantsEnable"] boolValue];
    bool toggle = [preferences[@"recordingEnabled"] boolValue];
    recordingActive.store(master && toggle, std::memory_order_release);
    Event(@"configuration-read", @{@"master":@(master), @"recording":@(toggle),
        @"enabled":@(master && toggle), @"filePresent":@([[NSFileManager defaultManager] fileExistsAtPath:H120PreferencesPath() ?: @""]),
        @"source":@"explicit-jailbreak-mobile-file-no-CFPreferences-user-cache",
        @"reloadRequired":@(vsyncReloadRequired.load(std::memory_order_acquire)),
        @"restorePolicy":@"explicit-user-confirmed-replayd-reload-no-verified-reset",
        @"blacklistApplied":@NO, @"asyncPropagationSupported":@NO});
    H120InstallRecordingHooks();
    NSString *path = H120PreferencesPath();
    H120DiagnosticUpdate(installedHooks, master && toggle,
        path && access(path.fileSystemRepresentation, R_OK) == 0);
}
std::atomic<bool> installPending(false);
void RecordingImageAdded(const struct mach_header *, intptr_t) {
    if (installPending.exchange(true)) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            installPending.store(false);
            H120InstallRecordingHooks();
            NSString *path = H120PreferencesPath();
            H120DiagnosticUpdate(installedHooks, H120RecordingActive(),
                path && access(path.fileSystemRepresentation, R_OK) == 0);
        }
    });
}
void ObserveRecordingPreferences(void) {
    static int token;
    int status = notify_register_dispatch(H120PreferencesNotification.UTF8String, &token,
        dispatch_get_main_queue(), ^(int value) { (void)value; ReloadRecording(); });
    Event(@"preferences-observer", @{@"status":@(status)});
}
}
// Explicit entry from the ONLY constructor in H120Hooks.mm. Keep the responder
// before Foundation/dyld work, but never interpret it as evidence of actual FPS.
void H120StartRecordingRuntime(void) {
    if (!getprogname() || strcmp(getprogname(), "replayd") != 0) return;
    static std::atomic<bool> started(false);
    if (started.exchange(true)) return;
    H120DiagnosticStart();
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            Event(@"module-load", @{@"version":@"5.09+full6", @"process":@"replayd", @"uid":@(geteuid()),
                @"module":@"0hello120hz", @"cadenceInstalled":@NO,
                @"cadenceReason":@"target-system-ABI-not-yet-verified"});
            ReloadRecording();
            ObserveRecordingPreferences();
            _dyld_register_func_for_add_image(RecordingImageAdded);
        }
    });
}
