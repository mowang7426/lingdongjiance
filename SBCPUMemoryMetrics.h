#ifndef SBCPU_MEMORY_METRICS_H
#define SBCPU_MEMORY_METRICS_H

/* Inspector-compatible RAM accounting:
 * free = HOST_VM_INFO64.free_count × page_size
 * used = clamp(NSProcessInfo.physicalMemory - free, 0, physical)
 * XNU free_count already includes speculative pages. Do not add inactive or purgeable.
 */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint64_t free_count;
} SBCPUMemoryPageCounters;

typedef struct {
    bool valid;
    uint64_t used_bytes;
    uint64_t total_bytes;
    uint64_t page_size;
} SBCPUMemoryMetrics;

static inline bool SBCPUMemoryMetricsCompute(const SBCPUMemoryPageCounters *counters,
                                              uint64_t page_size,
                                              uint64_t physical_total,
                                              SBCPUMemoryMetrics *out)
{
    if (out == NULL) {
        return false;
    }

    out->valid = false;
    out->used_bytes = 0U;
    out->total_bytes = 0U;
    out->page_size = 0U;

    if (counters == NULL || page_size == 0U || physical_total == 0U) {
        return false;
    }

    uint64_t free_bytes = UINT64_MAX;
    if (counters->free_count <= UINT64_MAX / page_size) {
        free_bytes = counters->free_count * page_size;
    }

    out->valid = true;
    out->used_bytes = (free_bytes >= physical_total) ? 0U : physical_total - free_bytes;
    out->total_bytes = physical_total;
    out->page_size = page_size;
    return true;
}

#ifdef __cplusplus
}
#endif

#endif /* SBCPU_MEMORY_METRICS_H */
