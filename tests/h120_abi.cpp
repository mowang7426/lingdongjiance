// Exercise the actual shipped arm64 range trampolines, not a rewritten mock.
#include <cassert>
#include <cstdint>
#include <cstring>
#include <initializer_list>
#include <cstdio>
struct Range {float a,b,c;};
extern "C" {
alignas(4) uint32_t H120ActiveFPSBits=0;
uint64_t H120ObservedX8=0;
void CaptureTimingsBB(),CaptureTimingsB(),CaptureConvert(),CaptureSource(),CaptureItemLocked(),CaptureItem();
void *H120OriginalRangeTimingsBB,*H120OriginalRangeTimingsB,*H120OriginalRangeConvert;
void *H120OriginalRangeSource,*H120OriginalRangeItemLocked,*H120OriginalRangeItem;
Range ProbeTimingsBB(void *,Range,bool,bool);
Range ProbeTimingsB(void *,Range,bool);
Range ProbeConvert(Range,double,unsigned char,bool,bool,bool);
Range ProbeSource(void *,Range,bool);
Range ProbeItemLocked(void *,Range,bool);
Range ProbeItem(void *,Range,bool,bool);
}
static void *marker=(void *)0x1234;
extern "C" Range H120TestBB(void *p,Range r,bool a,bool b){assert(p==marker && a && !b);return r;}
extern "C" Range H120TestOne(void *p,Range r,bool a){assert(p==marker && a);return r;}
extern "C" Range H120TestConvert(Range r,double d,unsigned char u,bool a,bool b,bool c){assert(d==13.5 && u==7 && a && !b && c);return r;}
static void check(Range r,float a,float b,float c){assert(r.a==a && r.b==b && r.c==c);assert(H120ObservedX8==0x5678);H120ObservedX8=0;}
int main(){
 H120OriginalRangeTimingsBB=(void *)CaptureTimingsBB;H120OriginalRangeTimingsB=(void *)CaptureTimingsB;
 H120OriginalRangeConvert=(void *)CaptureConvert;H120OriginalRangeSource=(void *)CaptureSource;
 H120OriginalRangeItemLocked=(void *)CaptureItemLocked;H120OriginalRangeItem=(void *)CaptureItem;
 Range original={10,80,60};
 for(float fps: {0.f,10.f,30.f,60.f,80.f,120.f}) {
  if(fps) std::memcpy(&H120ActiveFPSBits,&fps,4);else H120ActiveFPSBits=0;
  float a=fps?fps:10,b=fps?fps:80,c=fps?fps:60;
  check(ProbeTimingsBB(marker,original,true,false),a,b,c);
  check(ProbeTimingsB(marker,original,true),a,b,c);
  check(ProbeConvert(original,13.5,7,true,false,true),a,b,c);
  check(ProbeSource(marker,original,true),a,b,c);
  check(ProbeItemLocked(marker,original,true),a,b,c);
  check(ProbeItem(marker,original,true,false),a,b,c);
 }
 std::puts("Six production ARM64 trampolines: HFA/this/d3/x8/disabled passthrough PASS");
 return 0;
}
