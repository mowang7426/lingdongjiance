#ifndef SBCPU_MEMORY_SAMPLE_H
#define SBCPU_MEMORY_SAMPLE_H

#import <Foundation/Foundation.h>
#include <mach/mach.h>
#include <mach/mach_host.h>
#include <string.h>

#include "SBCPUMemoryMetrics.h"

/* Injectable production boundary: HOST_VM_INFO64 free_count and kernel page size. */
static inline SBCPUMemoryMetrics SBCPUMemoryReadWith(
    mach_port_t host,
    uint64_t physical,
    kern_return_t (*pageQuery)(host_t, vm_size_t *),
    kern_return_t (*statsQuery)(host_t, host_flavor_t, host_info64_t, mach_msg_type_number_t *))
{
    SBCPUMemoryMetrics result = {false, 0U, 0U, 0U};
    vm_size_t page = 0U;
    vm_statistics64_data_t vm;
    memset(&vm, 0, sizeof(vm));
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;

    if (host == MACH_PORT_NULL ||
        pageQuery(host, &page) != KERN_SUCCESS || page == 0U ||
        statsQuery(host, HOST_VM_INFO64, (host_info64_t)&vm, &count) != KERN_SUCCESS ||
        count < HOST_VM_INFO64_COUNT) {
        return result;
    }

    SBCPUMemoryPageCounters counters = {vm.free_count};
    SBCPUMemoryMetricsCompute(&counters, page, physical, &result);
    return result;
}

/* Main-thread cache shared by both text HUDs. Failed reads replace stale data. */
static inline SBCPUMemoryMetrics SBCPUMemoryCachedSample(void)
{
    static SBCPUMemoryMetrics cached = {false, 0U, 0U, 0U};
    static NSTimeInterval lastSampleUptime = -1.0;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;

    if (lastSampleUptime >= 0.0 && now >= lastSampleUptime &&
        now - lastSampleUptime < 1.0) {
        return cached;
    }

    lastSampleUptime = now;
    mach_port_t host = mach_host_self();
    cached = SBCPUMemoryReadWith(host, NSProcessInfo.processInfo.physicalMemory,
                                 host_page_size, host_statistics64);
    if (host != MACH_PORT_NULL) {
        mach_port_deallocate(mach_task_self(), host);
    }
    return cached;
}

#endif /* SBCPU_MEMORY_SAMPLE_H */
