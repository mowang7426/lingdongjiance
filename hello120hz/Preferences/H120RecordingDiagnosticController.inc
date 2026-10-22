// Included by the original settings controller; adds one action, not a replacement UI.
#include "../Shared/H120RecordingDiagnostics.h"
#include <errno.h>
#include <string.h>
#include <fcntl.h>
#include <mach-o/loader.h>
#include <mach-o/fat.h>

static NSString *H120FileCheck(NSString *path) {
    if (!path) return @"path resolver returned nil";
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    int error = fd < 0 ? errno : 0;
    if (fd >= 0) close(fd);
    return [NSString stringWithFormat:@"%@ : %@ (errno=%d %s)", path,
        error ? @"unreadable/missing" : @"readable", error, strerror(error)];
}
static void H120AppendMachO(NSMutableString *text, NSString *path) {
    NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
    if (data.length < sizeof(struct mach_header_64)) { [text appendString:@"Mach-O unavailable to Settings; cannot infer daemon loading\n"]; return; }
    const uint8_t *base = (const uint8_t *)data.bytes;
    uint64_t offset = 0, length = data.length;
    if (*(const uint32_t *)base == FAT_CIGAM && length >= sizeof(struct fat_header) + sizeof(struct fat_arch)) {
        const struct fat_arch *arch = (const struct fat_arch *)(base + sizeof(struct fat_header));
        offset = CFSwapInt32BigToHost(arch->offset); length = CFSwapInt32BigToHost(arch->size);
    }
    if (offset > data.length || length > data.length - offset || length < sizeof(struct mach_header_64)) return;
    const uint8_t *slice = base + offset;
    const struct mach_header_64 *header = (const struct mach_header_64 *)slice;
    if (header->magic != MH_MAGIC_64) return;
    uint64_t at = sizeof(*header);
    NSMutableArray<NSString *> *loads = [NSMutableArray array], *rpaths = [NSMutableArray array];
    for (uint32_t i = 0; i < header->ncmds && at + sizeof(struct load_command) <= length; ++i) {
        const struct load_command *cmd = (const struct load_command *)(slice + at);
        if (cmd->cmdsize < sizeof(*cmd) || cmd->cmdsize > length - at) break;
        BOOL load = cmd->cmd == LC_LOAD_DYLIB || cmd->cmd == LC_LOAD_WEAK_DYLIB || cmd->cmd == LC_REEXPORT_DYLIB;
        if ((load || cmd->cmd == LC_RPATH) && cmd->cmdsize >= 12) {
            uint32_t str = *(const uint32_t *)(slice + at + 8);
            if (str < cmd->cmdsize && memchr(slice + at + str, 0, cmd->cmdsize - str)) {
                NSString *value = [NSString stringWithUTF8String:(const char *)slice + at + str];
                if (value) [(load ? loads : rpaths) addObject:value];
            }
        }
        at += cmd->cmdsize;
    }
    [text appendFormat:@"Mach-O first slice cpu=%x subtype=%x; rpaths=%@\n", header->cputype, header->cpusubtype, rpaths];
    NSString *loader = path.stringByDeletingLastPathComponent;
    for (NSString *load in loads) {
        if ([load hasPrefix:@"/System/"] || [load hasPrefix:@"/usr/lib/"]) {
            [text appendFormat:@"system import %@ (dyld shared cache; file existence is not resolution proof)\n", load]; continue;
        }
        NSMutableArray *candidates = [NSMutableArray array];
        if ([load hasPrefix:@"@rpath/"]) {
            for (NSString *rpath in rpaths) [candidates addObject:[[rpath stringByReplacingOccurrencesOfString:@"@loader_path" withString:loader] stringByAppendingPathComponent:[load substringFromIndex:7]]];
        } else [candidates addObject:[load stringByReplacingOccurrencesOfString:@"@loader_path" withString:loader]];
        [text appendFormat:@"import %@\n", load];
        for (NSString *candidate in candidates) [text appendFormat:@"  %@\n", H120FileCheck(candidate)];
    }
}
static NSString *H120RecordingSelfCheck(void) {
    NSMutableString *text = [NSMutableString stringWithString:@"Hello120Hz Settings self-check 5.09+full4 (NOT daemon proof)\n"];
    NSDictionary *prefs = H120ReadPreferences();
    [text appendFormat:@"Settings uid=%u pid=%d\npreferences=%@\nmaster=%d recording=%d\n", geteuid(), getpid(),
        H120FileCheck(H120PreferencesPath()), [prefs[@"wantsEnable"] boolValue], [prefs[@"recordingEnabled"] boolValue]];
    NSString *library = H120JailbreakPath(@"/Library/MobileSubstrate/DynamicLibraries/0hello120hzRecording.dylib");
    NSString *filter = H120JailbreakPath(@"/Library/MobileSubstrate/DynamicLibraries/0hello120hzRecording.plist");
    [text appendFormat:@"module=%@\nfilter=%@\nfilter content=%@\n", H120FileCheck(library), H120FileCheck(filter),
        filter ? [NSDictionary dictionaryWithContentsOfFile:filter] : @"resolver nil"];
    H120AppendMachO(text, library);
    typedef int (*ListPIDs)(uint32_t, uint32_t, void *, int);
    typedef int (*ProcessName)(int, void *, uint32_t);
    ListPIDs list = (ListPIDs)dlsym(RTLD_DEFAULT, "proc_listpids");
    ProcessName name = (ProcessName)dlsym(RTLD_DEFAULT, "proc_name");
    BOOL found = NO;
    if (list && name) {
        pid_t pids[4096]; int size = list(1, 0, pids, sizeof(pids));
        for (int i = 0; i < size / (int)sizeof(pid_t) && i < 4096; ++i) {
            char value[64] = {0};
            if (name(pids[i], value, sizeof(value)) > 0 && strcmp(value, "replayd") == 0) {
                [text appendFormat:@"process enumeration: replayd pid=%d (NOT module proof)\n", pids[i]]; found = YES;
            }
        }
    }
    if (!found) [text appendString:@"replayd PID enumeration unavailable/not visible (permissions, absent, or API unavailable)\n"];
    [text appendFormat:@"log (real mobile data path, NOT jbroot): %@\nlegacy mapped log: %@\n", H120FileCheck(@H120_RECORDING_LOG_PATH),
        H120FileCheck(H120JailbreakPath(@"/var/mobile/Library/Logs/Hello120Hz/recording.jsonl"))];
    [text appendString:@"No preference changes, recording, process kill, respring or sandbox modifications performed.\n"];
    return text;
}
@interface H120RecordingDiagnosticController : UIViewController
@property(nonatomic, strong) UITextView *output;
@property(nonatomic, copy) NSString *report;
@end
@implementation H120RecordingDiagnosticController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = H120Text(@"Recording Diagnostics", @"录屏诊断");
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.output = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.output.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.output.editable = NO; self.output.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    [self.view addSubview:self.output];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:H120Text(@"Export", @"导出诊断")
        style:UIBarButtonItemStylePlain target:self action:@selector(exportDiagnostic)];
    self.report = @"设置端正在自检；等待 replayd 真实应答（1.5秒），尚未证明模块已加载…\n";
    self.output.text = self.report;
    __weak H120RecordingDiagnosticController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *check = H120RecordingSelfCheck();
        dispatch_async(dispatch_get_main_queue(), ^{
            H120RecordingDiagnosticController *owner = weakSelf; if (!owner) return;
            owner.report = [check stringByAppendingString:@"\n等待模块握手回执…\n"]; owner.output.text = owner.report;
            H120DiagnosticProbe(1.5, ^(uint64_t state, unsigned status) {
                H120RecordingDiagnosticController *target = weakSelf; if (!target) return;
                NSMutableString *result = [check mutableCopy];
                [result appendFormat:@"\nDarwin notify transport status=%u; rawState=%016llx\n", status, (unsigned long long)state];
                if (status != 0) [result appendString:@"通信注册/状态读写失败；不能据此判断是否加载。\n"];
                else if (!state) [result appendString:@"未收到应答：可能未加载/通信受限。已发送 ping 不等于已收到应答。\n"];
                else {
                    unsigned version = (unsigned)(state >> 48), error = (state >> 12) & 4095;
                    [result appendFormat:@"收到录屏模块真实应答：version=%u (%@), replayd pid=%llu\nhooks=0x%llx enabled=%d preferencesReadable=%d\nlog errno=%u (%s)\n", version,
                        version == H120_DIAGNOSTIC_VERSION ? @"5.09+full4" : @"版本不匹配", (state >> 24) & 0xffffff,
                        (state >> 6) & 15, (int)((state >> 10) & 1), (int)((state >> 11) & 1), error, strerror(error)];
                    [result appendString:@"收到应答只证明该版本模块在进程中响应，不证明系统接受120或真实输出120。errno=0且hooks=0也可能处于初始化阶段。\n"];
                }
                for (NSString *path in @[@H120_RECORDING_LOG_PATH, H120JailbreakPath(@"/var/mobile/Library/Logs/Hello120Hz/recording.jsonl") ?: @""]) {
                    if (!path.length) continue;
                    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
                    if (fd < 0) { [result appendFormat:@"\nlog read %@: errno=%d %s\n", path, errno, strerror(errno)]; continue; }
                    char buffer[131073]; ssize_t count = read(fd, buffer, 131072); int error = count < 0 ? errno : 0; close(fd);
                    NSString *logs = count >= 0 ? [[NSString alloc] initWithBytes:buffer length:count encoding:NSUTF8StringEncoding] : nil;
                    [result appendFormat:@"\n--- %@ (max128KiB, read errno=%d) ---\n%@\n", path, error, logs ?: @"unavailable/non-UTF8"];
                }
                target.report = result; target.output.text = result;
            });
        });
    });
}
- (void)exportDiagnostic {
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[self.report ?: @""] applicationActivities:nil];
    share.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:share animated:YES completion:nil];
}
@end
