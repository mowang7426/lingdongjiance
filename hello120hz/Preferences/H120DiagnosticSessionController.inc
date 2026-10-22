// Stateful UI; main-queue-only mutation, no cached mutable partial exports.
#include "../Shared/H120DiagnosticSession.h"
@interface H120RecordingDiagnosticController : UIViewController {
    H120ProbeChannel _recordingChannel, _clientChannel;
}
@property(nonatomic, strong) UITextView *output;
@property(nonatomic, copy) NSString *report;
@property(nonatomic, copy) NSString *selfCheck;
@end
@implementation H120RecordingDiagnosticController
- (void)refreshDiagnostic {
    NSMutableString *result = [NSMutableString stringWithString:self.selfCheck ?: @"设置端自检 pending；尚不能导出。\n"];
    H120ProbeChannel channels[] = {_recordingChannel, _clientChannel};
    for (unsigned i = 0; i < 2; ++i) {
        H120ProbeChannel channel = channels[i]; uint64_t state = channel.receipt;
        NSString *name = i ? @"SpringBoard client" : @"replayd recording";
        [result appendFormat:@"\nchannel=%@ status=%s startedAt=%.3f finishedAt=%.3f deadline=%.3f (Unix seconds)\ntransport=%u rawState=%016llx\n", name, H120ProbeStatusName(channel.status), channel.startedAt, channel.finishedAt, channel.deadline, channel.transport, (unsigned long long)state];
        if (channel.status == H120ProbePending) {
            [result appendString:@"等待该通道回执；尚未结束，未证明加载，也未判定超时。\n"]; continue;
        }
        if (channel.status == H120ProbeFailure) {
            [result appendString:@"通信注册/状态读写失败；version=unknown PID=unknown hooks=unknown error=transport-failure；不能据此判断是否加载。\n"]; continue;
        }
        if (channel.status == H120ProbeTimeout) {
            [result appendString:@"截止时间内未收到应答；version=unknown PID=unknown hooks=unknown error=no-receipt。可能未加载/通信受限；超时不是模块加载失败的证明。\n"]; continue;
        }
        unsigned version = (unsigned)(state >> 48), detail = (unsigned)((state >> 12) & 4095);
        [result appendFormat:@"真实回执 version=%u (%@) PID=%llu hooks=%llu%@ enabled=%d preferencesReadable=%d\n", version,
            version == H120_DIAGNOSTIC_VERSION ? @"current build" : @"版本不匹配", (state >> 24) & 0xffffff,
            (state >> 6) & 15, i ? @"/8" : @" (bitmask)", (int)((state >> 10) & 1), (int)((state >> 11) & 1)];
        if (i) [result appendFormat:@"current requested targetFPS=%u; error=not-encoded-in-client-v4\n该回执仅验证SpringBoard响应，不证明第三方应用注入或面板物理Hz。\n", detail];
        else [result appendFormat:@"log errno=%u (%s)\n收到回执不等于hooks已安装，也不证明系统接受120或真实输出120。\n", detail, strerror(detail)];
    }
    BOOL ready = H120ProbeCanExport(self.selfCheck != nil, &_recordingChannel, &_clientChannel);
    [result appendFormat:@"\nexportStatus=%@; Settings路径检查仅代表Settings自身，ELOOP不能直接证明replayd解析同一路径失败。\n", ready ? @"final" : @"pending (export disabled)"];
    // Assign an immutable snapshot on EVERY channel transition, including timeout/failure.
    self.report = [result copy]; self.output.text = self.report;
    self.navigationItem.rightBarButtonItem.enabled = ready;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = H120Text(@"Recording Diagnostics", @"录屏诊断");
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.output = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.output.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.output.editable = NO; self.output.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    [self.view addSubview:self.output];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:H120Text(@"Export", @"导出诊断")
        style:UIBarButtonItemStylePlain target:self action:@selector(exportDiagnostic)];
    double now = NSDate.date.timeIntervalSince1970;
    _recordingChannel = H120ProbeBegin(now, 1.5); _clientChannel = H120ProbeBegin(now, 1.5);
    [self refreshDiagnostic];
    __weak H120RecordingDiagnosticController *weakSelf = self;
    // Independent nonces/channels start together, not chained after replayd finishes.
    H120DiagnosticProbe(1.5, ^(uint64_t state, unsigned status) {
        H120RecordingDiagnosticController *page = weakSelf; if (!page) return;
        H120ProbeFinish(&page->_recordingChannel, state, status, NSDate.date.timeIntervalSince1970);
        [page refreshDiagnostic];
    });
    H120DiagnosticProbeNamed(H120_CLIENT_DIAGNOSTIC_PING, 1.5, ^(uint64_t state, unsigned status) {
        H120RecordingDiagnosticController *page = weakSelf; if (!page) return;
        H120ProbeFinish(&page->_clientChannel, state, status, NSDate.date.timeIntervalSince1970);
        [page refreshDiagnostic];
    });
    // Defensive UI deadline, even if a transport implementation misses completion.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        H120RecordingDiagnosticController *page = weakSelf; if (!page) return;
        double end = NSDate.date.timeIntervalSince1970;
        H120ProbeExpire(&page->_recordingChannel, end); H120ProbeExpire(&page->_clientChannel, end);
        [page refreshDiagnostic];
    });
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSMutableString *check = [H120RecordingSelfCheck() mutableCopy];
        for (NSString *path in @[@H120_RECORDING_LOG_PATH, H120JailbreakPath(@"/var/mobile/Library/Logs/Hello120Hz/recording.jsonl") ?: @""]) {
            if (!path.length) continue;
            int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
            if (fd < 0) { int error = errno; [check appendFormat:@"\nlog read %@: errno=%d %s\n", path, error, strerror(error)]; continue; }
            char buffer[131073]; ssize_t count = read(fd, buffer, 131072); int error = count < 0 ? errno : 0; close(fd);
            NSString *logs = count >= 0 ? [[NSString alloc] initWithBytes:buffer length:count encoding:NSUTF8StringEncoding] : nil;
            [check appendFormat:@"\n--- %@ (max128KiB, read errno=%d) ---\n%@\n", path, error, logs ?: @"unavailable/non-UTF8"];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            H120RecordingDiagnosticController *page = weakSelf; if (!page) return;
            page.selfCheck = check; [page refreshDiagnostic];
        });
    });
}
- (void)exportDiagnostic {
    // Guard the action too: programmatic invocation cannot bypass the disabled button.
    [self refreshDiagnostic];
    if (!H120ProbeCanExport(self.selfCheck != nil, &_recordingChannel, &_clientChannel)) {
        H120Alert(self, @"诊断尚未结束，请等待两通道完成/超时后再导出；无需重启或重新录屏。"); return;
    }
    NSString *name = [NSString stringWithFormat:@"Hello120Hz-diagnostic-%@.txt", NSUUID.UUID.UUIDString];
    NSURL *file = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    NSError *error = nil;
    if (![self.report writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        H120Alert(self, [NSString stringWithFormat:@"导出失败：%@", error.localizedDescription]); return;
    }
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[file] applicationActivities:nil];
    share.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:share animated:YES completion:nil];
}
@end
