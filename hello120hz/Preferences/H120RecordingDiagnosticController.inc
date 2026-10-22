// Included by the original settings controller; adds one action, not a replacement UI.
#include "../Shared/H120RecordingDiagnostics.h"
#include <errno.h>
#include <string.h>
#include <fcntl.h>
#include <mach-o/loader.h>
#include <mach-o/fat.h>
#include <sys/stat.h>

static NSString *H120FileCheck(NSString *path) {
    if (!path) return @"path resolver returned nil";
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    int error = fd < 0 ? errno : 0;
    if (fd >= 0) close(fd);
    NSMutableString *result = [NSMutableString stringWithFormat:@"%@ : %@ (O_NOFOLLOW errno=%d %s)", path,
        error == ELOOP ? @"nofollow-open refused (follow check below)" : error ? @"unreadable/missing" : @"readable", error, strerror(error)];
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) == 0 && S_ISLNK(st.st_mode)) {
        char link[4096]; ssize_t size = readlink(path.fileSystemRepresentation, link, sizeof(link) - 1);
        if (size >= 0) { link[size] = 0; [result appendFormat:@"; final-component symlink -> %s", link]; }
        else [result appendFormat:@"; readlink errno=%d", errno];
    }
    if (error == ELOOP) {
        // O_NOFOLLOW itself returns ELOOP for a valid final-component symlink.
        // A separate read-only follow check distinguishes that from a real loop.
        int followed = open(path.fileSystemRepresentation, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        int followError = followed < 0 ? errno : 0;
        if (followed >= 0) close(followed);
        [result appendFormat:@"; follow-open errno=%d %s (Settings only; O_NOFOLLOW ELOOP alone is NOT proof of a symlink cycle or replayd load failure)", followError, strerror(followError)];
    }
    return result;
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
    NSMutableString *text = [NSMutableString stringWithString:@"Hello120Hz Settings self-check 5.09+full5 (NOT daemon proof)\n"];
    NSDictionary *prefs = H120ReadPreferences();
    [text appendFormat:@"Settings uid=%u pid=%d\npreferences=%@\nmaster=%d recording=%d\n", geteuid(), getpid(),
        H120FileCheck(H120PreferencesPath()), [prefs[@"wantsEnable"] boolValue], [prefs[@"recordingEnabled"] boolValue]];
    [text appendFormat:@"Settings requested target FPS=%@ (NOT measured Hz)\n", prefs[@"wantsFPS"] ?: @120];
    for (NSString *logical in @[@"/Library/MobileSubstrate/DynamicLibraries/0hello120hz.dylib", @"/Library/MobileSubstrate/DynamicLibraries/0hello120hz.plist", @"/usr/libexec/hello120hz-install"]) {
        NSString *path = H120JailbreakPath(logical);
        // The main filter is intentionally a symlink to the writable mobile policy.
        [text appendFormat:@"client/helper %@ exists=%d\n", path ?: @"resolver nil", path && [NSFileManager.defaultManager fileExistsAtPath:path]];
        if ([logical hasSuffix:@".plist"]) [text appendFormat:@"effective client filter=%@\n", path ? [NSDictionary dictionaryWithContentsOfFile:path] : nil];
    }
    [text appendString:@"系统模式仅SpringBoard/Preferences；全局模式为UIKit客户端并保留黑名单，不是所有进程。backboard cadence未实现；读取目标120不等于实际物理锁120，dirty-frame FPS也不等于物理Hz，录屏输出FPS另行验收。\n"];
    [text appendString:@"System mode targets SpringBoard/Preferences only. Global UI mode adds UIKit clients, not all daemons; exclusions still apply. Backboard cadence is NOT implemented. Dirty-frame/compositor FPS is NOT physical panel Hz; request120 is NOT guaranteed physical lock120 or recorded120.\n"];
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
#include "H120DiagnosticSessionController.inc"
