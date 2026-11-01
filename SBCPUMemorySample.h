#ifndef SBCPU_MEMORY_SAMPLE_H
#define SBCPU_MEMORY_SAMPLE_H
#import <Foundation/Foundation.h>
#include <mach/mach.h>
#include <mach/mach_host.h>
#include <sys/sysctl.h>
#include <string.h>
#include "SBCPUMemoryMetrics.h"

/* Injectable kernel boundary; production and native tests use the same path. */
static inline SBCPUMemoryMetrics SBCPUMemoryReadWith(
    mach_port_t host, uint64_t total,
    kern_return_t (*pageQuery)(host_t, vm_size_t *),
    kern_return_t (*statsQuery)(host_t, host_flavor_t, host_info64_t, mach_msg_type_number_t *)) {
    SBCPUMemoryMetrics result={false,0,0,0};
    vm_size_t page=0;
    vm_statistics64_data_t vm; memset(&vm,0,sizeof(vm));
    mach_msg_type_number_t count=HOST_VM_INFO64_COUNT;
    if (host==MACH_PORT_NULL || pageQuery(host,&page)!=KERN_SUCCESS || !page ||
        statsQuery(host,HOST_VM_INFO64,(host_info64_t)&vm,&count)!=KERN_SUCCESS ||
        count<HOST_VM_INFO64_COUNT) return result; /* complete response before reading VM fields */
    SBCPUMemoryPageCounters counters={vm.free_count,vm.inactive_count,0,0};
    SBCPUMemoryMetricsCompute(&counters,page,total,total,&result);
    return result;
}

/* Main-thread only, shared by the existing updateCPU timer and detail panel.
   A failed query replaces old data, and is also throttled. No per-label I/O. */
static inline SBCPUMemoryMetrics SBCPUMemoryCachedSample(void) {
    static SBCPUMemoryMetrics cached={false,0,0,0};
    static NSTimeInterval last=-1;
    NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    if (last>=0 && now>=last && now-last<1.0) return cached;
    last=now;
    uint64_t total=NSProcessInfo.processInfo.physicalMemory;
    uint64_t kernel=0; size_t size=sizeof(kernel);
    if (sysctlbyname("hw.memsize",&kernel,&size,NULL,0)==0 && size==sizeof(kernel))
        total=SBCPUMemoryMetricsEffectiveTotal(kernel,total);
    mach_port_t host=mach_host_self();
    cached=SBCPUMemoryReadWith(host,total,host_page_size,host_statistics64);
    if (host!=MACH_PORT_NULL) mach_port_deallocate(mach_task_self(),host);
    return cached;
}
#endif
