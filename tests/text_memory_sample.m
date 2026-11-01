#import "../SBCPUMemorySample.h"
#include <assert.h>
static int mode=0,pages=0,stats=0;
static kern_return_t page(host_t h,vm_size_t *p) { (void)h;pages++;*p=mode==2?0:16384;return mode==1?KERN_FAILURE:KERN_SUCCESS; }
static kern_return_t query(host_t h,host_flavor_t f,host_info64_t out,mach_msg_type_number_t *n) {
 (void)h;assert(f==HOST_VM_INFO64);stats++;
 if(mode==3) return KERN_FAILURE;
 if(mode==4) *n=2;
 vm_statistics64_t v=(vm_statistics64_t)out;v->free_count=100;v->inactive_count=200;v->speculative_count=50;v->purgeable_count=70;
 return KERN_SUCCESS;
}
int main(void) { @autoreleasepool {
 for(mode=0;mode<=4;mode++) {
  SBCPUMemoryMetrics m=SBCPUMemoryReadWith(1,8ULL<<30,page,query);
  assert(m.valid==(mode==0));
  assert(m.available_bytes==(mode==0?300ULL*16384:0));
 }
 assert(pages==5 && stats==3);
 assert(!SBCPUMemoryReadWith(MACH_PORT_NULL,8ULL<<30,page,query).valid);
 mode=0; assert(!SBCPUMemoryReadWith(1,0,page,query).valid);
 SBCPUMemoryPageCounters overflow={UINT64_MAX,UINT64_MAX,0,0};SBCPUMemoryMetrics m;
 assert(SBCPUMemoryMetricsCompute(&overflow,UINT64_MAX,8ULL<<30,8ULL<<30,&m));
 assert(m.available_bytes==(8ULL<<30));
 SBCPUMemoryMetrics a=SBCPUMemoryCachedSample(),b=SBCPUMemoryCachedSample();
 assert(a.valid==b.valid && a.available_bytes==b.available_bytes);
 if(a.valid) assert(a.available_bytes<=a.total_bytes && a.page_size>0);
 printf("PASS production Mach query errors/zero page/short count/null host/overflow/no double-count/cache, real host valid=%d\n",a.valid);
 } return 0; }
