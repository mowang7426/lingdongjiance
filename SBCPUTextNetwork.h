#ifndef SBCPU_TEXT_NETWORK_H
#define SBCPU_TEXT_NETWORK_H
#import <Foundation/Foundation.h>
#include <math.h>
#include <string.h>

// Physical iPhone uplinks only: never add tunnel, loopback, AWDL or bridge traffic.
static inline BOOL SBCPUNetworkInterface(const char *name) {
    if (!name) return NO;
    if (strcmp(name, "en0") == 0) return YES;
    if (strncmp(name, "pdp_ip", 6) != 0 || !name[6]) return NO;
    for (const char *p = name + 6; *p; ++p) if (*p < '0' || *p > '9') return NO;
    return YES;
}

// Snapshots map name + interface index to [received bytes, sent bytes].
// An interface-set change or any counter reset invalidates the whole interval.
static inline BOOL SBCPUNetworkDelta(NSDictionary *previous, NSDictionary *current,
    double elapsed, double *download, double *upload) {
    *download = 0; *upload = 0;
    if (!previous.count || !current.count || !isfinite(elapsed) || elapsed <= 0 || elapsed > 5 ||
        ![[NSSet setWithArray:previous.allKeys] isEqualToSet:[NSSet setWithArray:current.allKeys]]) return NO;
    double rx = 0, tx = 0;
    for (NSString *key in current) {
        NSArray *old = previous[key], *now = current[key];
        uint64_t oldRx = [old[0] unsignedLongLongValue], oldTx = [old[1] unsignedLongLongValue];
        uint64_t newRx = [now[0] unsignedLongLongValue], newTx = [now[1] unsignedLongLongValue];
        if (newRx < oldRx || newTx < oldTx) return NO;
        rx += (double)(newRx - oldRx); tx += (double)(newTx - oldTx);
    }
    *download = rx / elapsed; *upload = tx / elapsed;
    return YES;
}
static inline NSString *SBCPUNetworkRate(double bytesPerSecond) {
    if (!isfinite(bytesPerSecond) || bytesPerSecond < 0) return @"-- B/s";
    if (bytesPerSecond < 1024) return [NSString stringWithFormat:@"%.0f B/s", bytesPerSecond];
    if (bytesPerSecond < 1024 * 1024) return [NSString stringWithFormat:@"%.1f KB/s", bytesPerSecond / 1024];
    return [NSString stringWithFormat:@"%.1f MB/s", bytesPerSecond / (1024 * 1024)];
}
static inline NSString *SBCPUNetworkText(BOOL valid, double download, double upload) {
    return [NSString stringWithFormat:@"上传 %@ · 下载 %@", SBCPUNetworkRate(valid ? upload : NAN),
        SBCPUNetworkRate(valid ? download : NAN)];
}
#endif
