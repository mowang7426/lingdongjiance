#import "SBCPUPCoreFrequency.h"
#import <IOKit/IOKitLib.h>
#import <mach/mach_time.h>
#import <notify.h>
#import <dlfcn.h>
#import <sys/sysctl.h>
#import <math.h>

// No Hello CPU implementation or hardware writes. Unknown table mappings fail closed.
// Signatures and signed residency follow macmon sources.rs (MIT); independently implemented.
typedef CFTypeRef Subscription;
typedef struct {
    void *handle;
    CFMutableDictionaryRef (*copy)(CFStringRef, CFStringRef, uint64_t, uint64_t, uint64_t);
    Subscription (*subscribe)(void *, CFMutableDictionaryRef, CFMutableDictionaryRef *, uint64_t, CFTypeRef);
    CFDictionaryRef (*sample)(Subscription, CFMutableDictionaryRef, CFTypeRef);
    CFDictionaryRef (*delta)(CFDictionaryRef, CFDictionaryRef, CFTypeRef);
    int (*iterate)(CFDictionaryRef, int (^)(CFDictionaryRef));
    CFStringRef (*group)(CFDictionaryRef), (*subgroup)(CFDictionaryRef), (*name)(CFDictionaryRef);
    int (*count)(CFDictionaryRef);
    CFStringRef (*state)(CFDictionaryRef, int);
    int64_t (*residency)(CFDictionaryRef, int);
    CFStringRef (*unit)(CFDictionaryRef);
    uint64_t (*driver)(CFDictionaryRef);
} PAPI;

static double PNow(void) {
    static mach_timebase_info_data_t tb;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ mach_timebase_info(&tb); });
    return (double)mach_continuous_time() * tb.numer / tb.denom / 1e9;
}
static NSString *PString(CFStringRef s) { return s ? (__bridge NSString *)s : @""; }
static BOOL PIsCore(NSString *name) {
    // Full channel names remain identities; never infer P from 'not E' or core index.
    return [name rangeOfString:@"^(?:DIE_[0-9]+_)?(?:PACC[0-9]*_)?PCPU[0-9]+(?:_CPU[0-9]+)?$"
                       options:NSRegularExpressionSearch].location != NSNotFound;
}
static BOOL PIdle(NSString *s) {
    return [@[@"IDLE", @"OFF", @"DOWN"] containsObject:s];
}
static double PExplicitMHz(NSString *name) {
    // Explicit units only: V0P1, bare numbers and table indices are NOT frequencies.
    NSScanner *scanner = [NSScanner scannerWithString:name];
    double value = 0;
    if (![scanner scanDouble:&value] || !isfinite(value) || value <= 0) return 0;
    NSString *unit = [[name substringFromIndex:scanner.scanLocation]
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([unit isEqualToString:@"GHz"]) value *= 1000;
    else if ([unit isEqualToString:@"MHz"]) {}
    else if ([unit isEqualToString:@"kHz"]) value /= 1000;
    else if ([unit isEqualToString:@"Hz"]) value /= 1000000;
    else return 0;
    return value >= 1 && value <= 10000 ? value : 0;
}

static NSArray *PTopology(NSArray *rows) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        NSMutableDictionary *copy = [row mutableCopy];
        copy[@"states"] = [row[@"states"] valueForKey:@"name"];
        [result addObject:copy];
    }
    return result;
}
static double PCompute(NSArray *rows, NSString **reason) {
    double sum = 0, active = 0;
    NSString *commonUnit = nil; NSNumber *commonDriver = nil;
    NSMutableSet *names = [NSMutableSet set];
    NSUInteger cores = 0;
    *reason = @"no-verifiable-pcore-channel";
    for (NSDictionary *row in rows) {
        if (![row[@"subgroup"] isEqualToString:@"CPU Core Performance States"]) continue;
        if (!PIsCore(row[@"channel"])) {
            NSString *name = row[@"channel"];
            if ([name rangeOfString:@"^(?:DIE_[0-9]+_)?(?:(?:EACC|PACC)[0-9]*_)?[EM]CPU[0-9]+(?:_CPU[0-9]+)?$"
                           options:NSRegularExpressionSearch].location != NSNotFound) continue;
            *reason = @"unclassified-core-channel"; return 0;
        }
        cores++;
        if ([names containsObject:row[@"channel"]]) { *reason = @"duplicate-pcore-channel"; return 0; }
        [names addObject:row[@"channel"]];
        NSString *unit = row[@"unit"];
        if (!unit.length || (commonUnit && ![unit isEqualToString:commonUnit]) ||
            (commonDriver && ![row[@"driver"] isEqual:commonDriver])) {
            *reason = @"unverified-residency-unit-or-source"; return 0;
        }
        commonUnit = unit; commonDriver = row[@"driver"];
        for (NSDictionary *state in row[@"states"]) {
            int64_t r = [state[@"residency"] longLongValue];
            if (r < 0) { *reason = @"counter-reset-or-invalid"; return 0; }
            NSString *name = state[@"name"];
            if (PIdle(name)) continue;
            double mhz = PExplicitMHz(name);
            // Reject unmapped states even when their delta is zero: no partial table inference.
            if (!mhz) { *reason = @"unmapped-state-needs-device-evidence"; return 0; }
            sum += mhz * (double)r; active += (double)r;
        }
    }
    if (!cores) return 0;
    if (!(active > 0) || !isfinite(sum) || !isfinite(active)) { *reason = @"no-active-pcore-residency"; return 0; }
    *reason = @"explicit-state-frequency-active-weighted";
    return sum / active;
}

// Evidence-gated A16 mapping. Static Hello CPU input-chain evidence, not live telemetry.
static uint32_t PLE32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
static NSArray *PA16Table(NSArray *tables) {
    NSDictionary *pmgr = nil;
    for (NSDictionary *node in tables) {
        NSDictionary *props = node[@"rawProperties"];
        // The known table must occur exactly once and on the pmgr service only.
        if (props[@"voltage-states5-sram"] || props[@"voltage-states5"]) {
            if (pmgr || ![node[@"node"] isEqualToString:@"pmgr"]) return nil;
            pmgr = props;
        }
    }
    NSData *sram = pmgr[@"voltage-states5-sram"], *reciprocal = pmgr[@"voltage-states5"];
    if (![sram isKindOfClass:NSData.class] || ![reciprocal isKindOfClass:NSData.class] ||
        sram.length % 8 || reciprocal.length % 8 || sram.length != 17 * 8 || reciprocal.length != 17 * 8) return nil;
    const uint8_t *a = sram.bytes, *b = reciprocal.bytes;
    NSMutableArray *frequencies = [NSMutableArray array];
    uint32_t last = 0;
    for (NSUInteger k = 0; k < 17; k++) {
        uint32_t hz = PLE32(a + k * 8);
        // A16 evidence envelope; second field is deliberately NOT a frequency.
        if (hz < 636000000U || hz > 3468000000U || hz <= last ||
            (k == 0 && hz != 636000000U) || (k == 16 && hz != 3468000000U) ||
            PLE32(b + k * 8) != (uint32_t)(65536000000000ULL / hz)) return nil;
        last = hz;
        [frequencies addObject:@((double)hz / 1000000.0)];
    }
    return frequencies;
}
static double PComputeMapped(NSArray *rows, NSString *machine, NSString *os, NSArray *tables, NSString **reason) {
    BOOL binary = NO;
    for (NSDictionary *row in rows) {
        if (![row[@"subgroup"] isEqualToString:@"CPU Core Performance States"] || !PIsCore(row[@"channel"])) continue;
        for (NSDictionary *state in row[@"states"])
            if (!PIdle(state[@"name"]) && !PExplicitMHz(state[@"name"])) binary = YES;
    }
    if (!binary) return PCompute(rows, reason); // Existing explicit-unit path, no binary guessing.
    *reason = @"unsupported-binary-mapping-platform";
    if (![machine isEqualToString:@"iPhone15,3"] || ![os isEqualToString:@"Version 17.0 (Build 21A329)"]) return 0;
    NSArray *frequencies = PA16Table(tables);
    *reason = @"invalid-or-ambiguous-pmgr-table5";
    if (!frequencies) return 0;
    NSMutableArray *mapped = [NSMutableArray array];
    NSMutableSet *names = [NSMutableSet set];
    NSNumber *driver = nil;
    for (NSDictionary *row in rows) {
        if (![row[@"subgroup"] isEqualToString:@"CPU Core Performance States"] || !PIsCore(row[@"channel"])) {
            [mapped addObject:row]; continue;
        }
        *reason = @"invalid-a16-pcore-topology";
        NSString *name = row[@"channel"];
        if (![@[@"PCPU0", @"PCPU1"] containsObject:name] || [names containsObject:name] ||
            ![row[@"group"] isEqualToString:@"CPU Stats"] || ![row[@"unit"] isEqualToString:@"24Mticks"] ||
            ![row[@"driver"] isKindOfClass:NSNumber.class] || [row[@"driver"] unsignedLongLongValue] == 0 ||
            (driver && ![driver isEqual:row[@"driver"]])) return 0;
        driver = row[@"driver"]; [names addObject:name];
        NSArray *states = row[@"states"];
        if (states.count != 18 || ![states[0][@"name"] isEqualToString:@"IDLE"]) return 0;
        NSMutableArray *resolved = [NSMutableArray arrayWithObject:states[0]];
        for (NSUInteger k = 0; k < 17; k++) {
            NSDictionary *state = states[k + 1];
            NSString *expected = [NSString stringWithFormat:@"V%luP%lu", (unsigned long)k, (unsigned long)(16 - k)];
            if (![state[@"name"] isEqualToString:expected]) return 0;
            [resolved addObject:@{@"name":[NSString stringWithFormat:@"%.6f MHz", [frequencies[k] doubleValue]],
                                  @"residency":state[@"residency"]}];
        }
        NSMutableDictionary *copy = [row mutableCopy]; copy[@"states"] = resolved;
        [mapped addObject:copy];
    }
    if (names.count != 2) { *reason = @"missing-a16-pcore"; return 0; }
    double mhz = PCompute(mapped, reason);
    if (mhz > 0) *reason = @"a16-table5-sram-active-weighted";
    return mhz;
}

@interface SBCPUPCoreSampler : NSObject {
    PAPI api;
    Subscription subscription;
    CFMutableDictionaryRef subscribed;
    CFDictionaryRef previous;
    double previousTime, retryTime, diagnosticTime;
    NSString *lastDiagnosticStatus;
    NSArray *previousTopology, *tables;
    dispatch_queue_t queue;
    NSObject *cacheLock;
    BOOL pending;
    double cachedMHz, cachedEnd, requestedAt;
    int blankToken;
}
- (double)read;
@end

@implementation SBCPUPCoreSampler
- (instancetype)init {
    if ((self = [super init])) {
        queue = dispatch_queue_create("com.sbcpu.pcore-readonly", DISPATCH_QUEUE_SERIAL);
        cacheLock = [NSObject new];
        blankToken = -1;
        // Registration on a serial worker; screen transitions discard baseline/cache promptly.
        dispatch_async(queue, ^{
            notify_register_dispatch("com.apple.springboard.hasBlankedScreen", &self->blankToken,
                self->queue, ^(int token) {
                    uint64_t blanked = 0;
                    if (notify_get_state(token, &blanked) != NOTIFY_STATUS_OK || blanked) {
                        [self reset];
                        @synchronized (self->cacheLock) { self->cachedMHz = 0; self->cachedEnd = 0; }
                    }
                });
        });
    }
    return self;
}
- (void)reset {
    // All CF objects, API calls, IORegistry access and diagnostic I/O confined to queue.
    if (previous) CFRelease(previous);
    if (subscription) CFRelease(subscription);
    if (subscribed) CFRelease(subscribed);
    previous = NULL; subscription = NULL; subscribed = NULL;
    previousTime = 0; previousTopology = nil; tables = nil;
}
- (BOOL)loadAPI {
    if (api.handle) return YES;
    void *h = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY | RTLD_LOCAL);
    if (!h) return NO;
    api.handle = h;
#define LOAD(field, symbol) api.field = (__typeof__(api.field))dlsym(h, symbol)
    LOAD(copy, "IOReportCopyChannelsInGroup");
    LOAD(subscribe, "IOReportCreateSubscription");
    LOAD(sample, "IOReportCreateSamples"); LOAD(delta, "IOReportCreateSamplesDelta");
    LOAD(iterate, "IOReportIterate"); LOAD(group, "IOReportChannelGetGroup");
    LOAD(subgroup, "IOReportChannelGetSubGroup"); LOAD(name, "IOReportChannelGetChannelName");
    LOAD(count, "IOReportStateGetCount"); LOAD(state, "IOReportStateGetNameForIndex");
    LOAD(residency, "IOReportStateGetResidency");
    LOAD(unit, "IOReportChannelGetUnitLabel"); LOAD(driver, "IOReportChannelGetDriverID");
#undef LOAD
    if (api.copy && api.subscribe && api.sample && api.delta && api.iterate && api.group &&
        api.subgroup && api.name && api.count && api.state && api.residency && api.unit && api.driver) return YES;
    dlclose(h); api = (PAPI){0}; return NO;
}
- (NSArray *)rawTables {
    // Read-only pmgr evidence. Binary decoding is restricted to PA16Table and the platform gate.
    NSMutableArray *result = [NSMutableArray array];
    io_iterator_t it = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(0, IOServiceMatching("AppleARMIODevice"), &it) != KERN_SUCCESS)
        return result;
    io_service_t service;
    unsigned services = 0;
    while ((service = IOIteratorNext(it))) {
        NSMutableDictionary *filtered = [NSMutableDictionary dictionary];
        for (NSString *key in @[@"voltage-states5-sram", @"voltage-states5"]) {
            CFTypeRef property = IORegistryEntryCreateCFProperty(service, (__bridge CFStringRef)key, kCFAllocatorDefault, 0);
            if (property) {
                // Preserve malformed candidates too, so they cannot evade the uniqueness check.
                filtered[key] = (__bridge id)property;
                CFRelease(property);
            }
        }
        if (filtered.count) {
            io_name_t node = {0};
            if (IORegistryEntryGetName(service, node) != KERN_SUCCESS) node[0] = 0;
            [result addObject:@{@"node":@((const char *)node), @"rawProperties":filtered}];
        }
        IOObjectRelease(service);
        if (++services >= 128) { [result removeAllObjects]; break; }
    }
    IOObjectRelease(it);
    return result;
}
- (NSArray *)rows:(CFDictionaryRef)sample {
    NSMutableArray *rows = [NSMutableArray array];
    __block BOOL invalid = NO;
    int status = api.iterate(sample, ^int(CFDictionaryRef channel) {
        NSString *group = PString(self->api.group(channel));
        NSString *subgroup = PString(self->api.subgroup(channel));
        if (![group isEqualToString:@"CPU Stats"]) return 0;
        if (![subgroup isEqualToString:@"CPU Core Performance States"] &&
            ![subgroup isEqualToString:@"CPU Complex Performance States"]) return 0;
        int count = self->api.count(channel);
        if (count <= 0 || count > 256 || rows.count >= 256) { invalid = YES; return 0; }
        NSMutableArray *states = [NSMutableArray array];
        for (int i = 0; i < count; i++) {
            [states addObject:@{@"name":PString(self->api.state(channel, i)),
                @"residency":@(self->api.residency(channel, i))}];
        }
        [rows addObject:@{@"group":group, @"subgroup":subgroup,
            @"channel":PString(self->api.name(channel)), @"unit":PString(self->api.unit(channel)),
            @"driver":@(self->api.driver(channel)), @"states":states}];
        return 0;
    });
    if (status != 0 || invalid) return nil;
    // Canonical identity/order comparison does not depend on IOReport enumeration order.
    return [rows sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSString *ka = [NSString stringWithFormat:@"%@/%@/%@", a[@"driver"], a[@"subgroup"], a[@"channel"]];
        NSString *kb = [NSString stringWithFormat:@"%@/%@/%@", b[@"driver"], b[@"subgroup"], b[@"channel"]];
        return [ka compare:kb];
    }];
}
- (void)diagnose:(NSString *)reason rows:(NSArray *)rows elapsed:(double)elapsed mhz:(double)mhz {
    // Formal build: one small report per status transition, never periodic full-table dumps.
    // Raw diagnostic snapshots remain available in the separate diagnostic build only.
    if ([lastDiagnosticStatus isEqualToString:reason]) return;
    double now = PNow();
    if (diagnosticTime && now - diagnosticTime < 300) return;
    diagnosticTime = now;
    lastDiagnosticStatus = [reason copy];
    (void)rows;
    char model[128] = {0}; size_t size = sizeof(model);
    sysctlbyname("hw.machine", model, &size, NULL, 0);
    NSString *directory = @"/var/mobile/Library/Logs";
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error];
    NSDictionary *report = @{@"version":@"5.04", @"status":reason,
        @"time":[NSDate date], @"machine":@((const char *)model),
        @"os":NSProcessInfo.processInfo.operatingSystemVersionString,
        @"windowSeconds":@(elapsed), @"activeWeightedPcoreMHz":@(mhz),
        @"semantics":@"sum(frequencyMHz * deltaResidency) / sum(active deltaResidency); IDLE/OFF/DOWN excluded; no active residence is unavailable",
        @"mapping":@"iPhone15,3 / 17.0 / 21A329 only: pmgr table5-sram LE uint32 Hz; VkP(16-k) -> raw[k]; explicit-unit names otherwise"};
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:report format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    if (data) [data writeToFile:[directory stringByAppendingPathComponent:@"LingdongPcore-5.04-status.plist"] options:NSDataWritingAtomic error:&error];
}
- (double)take {
    double now = PNow();
    uint64_t blanked = 0;
    if (blankToken == -1 || notify_get_state(blankToken, &blanked) != NOTIFY_STATUS_OK || blanked) {
        [self reset]; return 0;
    }
    if (now < retryTime) return 0;
    if (![self loadAPI]) {
        [self diagnose:@"libIOReport-or-symbol-unavailable" rows:nil elapsed:0 mhz:0];
        retryTime = now + 30; return 0;
    }
    if (!subscription) {
        CFMutableDictionaryRef channels = api.copy(CFSTR("CPU Stats"), NULL, 0, 0, 0);
        if (channels) {
            subscription = api.subscribe(NULL, channels, &subscribed, 0, NULL);
            CFRelease(channels);
        }
        if (!subscription || !subscribed) {
            [self reset]; retryTime = now + 30;
            [self diagnose:@"subscription-unavailable" rows:nil elapsed:0 mhz:0]; return 0;
        }
        tables = [self rawTables];
    }
    CFDictionaryRef next = api.sample(subscription, subscribed, NULL);
    double end = PNow();
    NSArray *currentRows = next ? [self rows:next] : nil;
    if (!currentRows) {
        if (next) CFRelease(next);
        [self reset]; retryTime = now + 5;
        [self diagnose:@"sample-unavailable" rows:nil elapsed:0 mhz:0]; return 0;
    }
    NSArray *topology = PTopology(currentRows);
    double elapsed = end - previousTime;
    if (!previous || elapsed > 5 || elapsed < 0.5 || ![topology isEqual:previousTopology]) {
        if (previous) CFRelease(previous);
        previous = next; previousTime = end; previousTopology = topology;
        [self diagnose:@"baseline-cumulative-not-delta" rows:currentRows elapsed:0 mhz:0]; return 0;
    }
    CFDictionaryRef delta = api.delta(previous, next, NULL);
    CFRelease(previous);
    previous = next; previousTime = end; previousTopology = topology;
    NSArray *deltaRows = delta ? [self rows:delta] : nil;
    if (delta) CFRelease(delta);
    if (!deltaRows || ![PTopology(deltaRows) isEqual:topology]) {
        [self reset]; retryTime = now + 5;
        [self diagnose:@"delta-unavailable-or-topology-changed" rows:deltaRows elapsed:elapsed mhz:0]; return 0;
    }
    NSString *reason;
    char machine[128] = {0}; size_t machineSize = sizeof(machine);
    sysctlbyname("hw.machine", machine, &machineSize, NULL, 0);
    double frequency = PComputeMapped(deltaRows, @((const char *)machine),
        NSProcessInfo.processInfo.operatingSystemVersionString, tables, &reason);
    if ([reason isEqualToString:@"counter-reset-or-invalid"]) [self reset];
    [self diagnose:reason rows:deltaRows elapsed:elapsed mhz:frequency];
    return frequency;
}
- (double)read {
    double now = PNow();
    @synchronized (cacheLock) {
        // Coalesce HUD/panel calls; at most one queued job, no new timer or sleep loop.
        if (!pending && (!requestedAt || now - requestedAt >= 0.9)) {
            pending = YES; requestedAt = now;
            dispatch_async(queue, ^{
                @autoreleasepool {
                    double mhz = [self take];
                    @synchronized (self->cacheLock) {
                        self->cachedMHz = mhz; // Failure replaces cache: never display stale successful reading.
                        self->cachedEnd = PNow(); self->pending = NO;
                    }
                }
            });
        }
        return cachedEnd && now - cachedEnd <= 3 ? cachedMHz : 0;
    }
}
@end

double SBCPUReadPcoreFrequency(void) {
    static SBCPUPCoreSampler *sampler;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sampler = [SBCPUPCoreSampler new]; });
    return [sampler read];
}
