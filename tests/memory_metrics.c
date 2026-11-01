#include "../SBCPUMemoryMetrics.h"
#include <assert.h>
#include <stdio.h>
static void free_only_page_size_and_used(void) { SBCPUMemoryPageCounters c={.free_count=100}; SBCPUMemoryMetrics m; assert(SBCPUMemoryMetricsCompute(&c,16384,16ULL*1024*1024,&m)); assert(m.used_bytes==16ULL*1024*1024-100ULL*16384); assert(m.total_bytes==16ULL*1024*1024); assert(m.page_size==16384); }
static void overflow_and_physical_less_than_free_clamp(void) { SBCPUMemoryPageCounters c={UINT64_MAX}; SBCPUMemoryMetrics m; assert(SBCPUMemoryMetricsCompute(&c,16384,1000,&m)); assert(m.valid && m.used_bytes==0 && m.total_bytes==1000); }
static void failure_clears_output(void) { SBCPUMemoryMetrics m={true,123,456,789}; SBCPUMemoryPageCounters c={1}; assert(!SBCPUMemoryMetricsCompute(&c,0,1000,&m)); assert(!m.valid&&!m.used_bytes&&!m.total_bytes&&!m.page_size); m.valid=true; assert(!SBCPUMemoryMetricsCompute(NULL,4096,1000,&m)); assert(!m.valid); assert(!SBCPUMemoryMetricsCompute(&c,4096,0,&m)); }
int main(void) { free_only_page_size_and_used(); overflow_and_physical_less_than_free_clamp(); failure_clears_output(); puts("mem2 Inspector free-only metrics passed"); }
