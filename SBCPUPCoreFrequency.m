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

@interface SBCPUPCoreSampler : NSObject {
    PAPI api;
    Subscription subscription;
    CFMutableDictionaryRef subscribed;
    CFDictionaryRef previous;
    double previousTime, retryTime, diagnosticTime;
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
    // Evidence only. No fixed table suffix, decoding, unit guessing or table-based frequency.
    NSMutableArray *result = [NSMutableArray array];
    io_iterator_t it = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(0, IOServiceMatching("AppleARMIODevice"), &it) != KERN_SUCCESS)
        return result;
    io_service_t service;
    unsigned services = 0;
    NSUInteger rawBytes = 0;
    while ((service = IOIteratorNext(it))) {
        CFMutableDictionaryRef props = NULL;
        if (IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS && props) {
            NSMutableDictionary *filtered = [NSMutableDictionary dictionary];
            NSDictionary *dict = (__bridge NSDictionary *)props;
            for (id key in dict) {
                if (![key isKindOfClass:NSString.class]) continue;
                if (![key hasPrefix:@"voltage-states"] && ![key isEqualToString:@"acc-clusters"]) continue;
                id value = dict[key];
                if ([value isKindOfClass:NSData.class] && [value length] <= 65536 && filtered.count < 64 &&
                    rawBytes + [value length] <= 1048576) {
                    filtered[key] = value; rawBytes += [value length];
                }
            }
            if (filtered.count) {
                io_name_t node = {0}; uint64_t rid = 0;
                IORegistryEntryGetName(service, node);
                IORegistryEntryGetRegistryEntryID(service, &rid);
                [result addObject:@{@"node":@((const char *)node), @"registryID":@(rid), @"rawProperties":filtered}];
            }
        }
        if (props) CFRelease(props);
        IOObjectRelease(service);
        if (++services >= 128) break;
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
    double now = PNow();
    if (diagnosticTime && now - diagnosticTime < 30) return;
    diagnosticTime = now;
    char model[128] = {0}; size_t size = sizeof(model);
    sysctlbyname("hw.machine", model, &size, NULL, 0);
    NSString *directory = @"/var/mobile/Library/Logs";
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error];
    NSDictionary *report = @{@"version":@"5.04-pcore-diagnostic.1", @"status":reason,
        @"time":[NSDate date], @"machine":@((const char *)model),
        @"os":NSProcessInfo.processInfo.operatingSystemVersionString,
        @"windowSeconds":@(elapsed), @"activeWeightedPcoreMHz":@(mhz),
        @"semantics":@"sum(frequencyMHz * deltaResidency) / sum(active deltaResidency); IDLE/OFF/DOWN excluded; no active residence is unavailable",
        @"mapping":@"explicit Hz/kHz/MHz/GHz state names only; binary DVFS tables are raw evidence, never decoded or used",
        @"channels":rows ?: @[], @"rawTables":tables ?: @[]};
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:report format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    if (data) [data writeToFile:[directory stringByAppendingPathComponent:@"LingdongPcore-5.04-diagnostic.plist"] options:NSDataWritingAtomic error:&error];
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
    double frequency = PCompute(deltaRows, &reason);
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
