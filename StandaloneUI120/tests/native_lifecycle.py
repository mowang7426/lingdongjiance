#!/usr/bin/env python3
"""Compile real Restore/SetRange bodies against Foundation + a mock display link.
Validates bookkeeping/lifetime/recursion; not UIKit/ProMotion runtime behavior.
"""
from pathlib import Path
import sys
p=Path(__file__).resolve().parents[1]
s=(p/'Tweak.m').read_text()
restore=s[s.index('static void Restore(void)'):s.index('static void Reload(void)')]
setter=s[s.index('static void SetRange('):s.index('static BOOL ValidABI(')]
head='''#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <assert.h>
#import "Policy.h"
typedef struct CAFrameRateRange { float minimum, maximum, preferred; } CAFrameRateRange;
static CAFrameRateRange CAFrameRateRangeMake(float a,float b,float c) { return (CAFrameRateRange){a,b,c}; }
@interface CADisplayLink : NSObject
@property(nonatomic) CAFrameRateRange range;
@end
@implementation CADisplayLink
@end
static NSHashTable<CADisplayLink *> *Touched;
static char SavedKey;
static __thread unsigned Bypass;
static BOOL Enabled = YES, Recurse;
static unsigned Calls;
static BOOL Safe(void) { return Enabled && NSThread.isMainThread; }
static void (*OriginalRange)(CADisplayLink *, SEL, CAFrameRateRange);
static void SetRange(CADisplayLink *,SEL,CAFrameRateRange);
'''
tail='''static void Original(CADisplayLink *link,SEL cmd,CAFrameRateRange range) {
    (void)cmd; ++Calls; link.range=range;
    if (Recurse) { Recurse=NO; SetRange(link,cmd,CAFrameRateRangeMake(20,30,30)); }
}
int main(void) { @autoreleasepool {
    Touched=[NSHashTable weakObjectsHashTable]; OriginalRange=Original;
    CADisplayLink *a=[CADisplayLink new]; SEL cmd=@selector(setPreferredFrameRateRange:);
    SetRange(a,cmd,CAFrameRateRangeMake(0,60,60)); assert(a.range.maximum==120);
    Restore(); assert(a.range.minimum==0 && a.range.maximum==60 && a.range.preferred==60);
    SetRange(a,cmd,CAFrameRateRangeMake(0,0,0));
    SetRange(a,cmd,CAFrameRateRangeMake(40,90,80));
    Enabled=NO; Restore(); assert(a.range.minimum==40 && a.range.maximum==90 && a.range.preferred==80);
    SetRange(a,cmd,CAFrameRateRangeMake(0,60,60)); assert(a.range.maximum==60);
    Enabled=YES; SetRange(a,cmd,CAFrameRateRangeMake(0,60,60));
    SetRange(a,cmd,CAFrameRateRangeMake(20,30,30)); Restore(); assert(a.range.maximum==30);
    SetRange(a,cmd,CAFrameRateRangeMake(0,60,60));
    dispatch_sync(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0), ^{
        assert(!NSThread.isMainThread); SetRange(a,cmd,CAFrameRateRangeMake(10,30,30));
    });
    Restore(); assert(a.range.maximum==30 && a.range.minimum==10);
    __weak CADisplayLink *weakLink;
    @autoreleasepool {
        CADisplayLink *temporary=[CADisplayLink new]; weakLink=temporary;
        SetRange(temporary,cmd,CAFrameRateRangeMake(0,60,60));
    }
    assert(weakLink==nil); Restore(); assert(Touched.count==0);
    unsigned before=Calls; Recurse=YES;
    SetRange(a,cmd,CAFrameRateRangeMake(0,60,60));
    assert(Calls==before+2 && Bypass==0 && a.range.maximum==30);
    Restore(); assert(a.range.maximum==60);
    puts("PASS real setter/restore bodies: restore latest, disable, low request, background supersession, weak lifetime, recursion");
} return 0; }
'''
Path(sys.argv[1]).write_text(head+restore+setter+tail)
