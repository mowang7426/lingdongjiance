// Tests production parser/reducer directly; never substitutes a rewritten formula.
#import "../SBCPUPCoreFrequency.m"
#import <assert.h>
static NSDictionary *S(NSString *name, int64_t residency) {
    return @{@"name":name, @"residency":@(residency)};
}
static NSDictionary *R(NSString *channel, NSArray *states) {
    return @{@"group":@"CPU Stats", @"subgroup":@"CPU Core Performance States",
             @"channel":channel, @"unit":@"ns", @"driver":@1, @"states":states};
}
int main(void) {
    @autoreleasepool {
        assert(PIsCore(@"PCPU0")); assert(PIsCore(@"DIE_1_PCPU1_CPU0"));
        assert(PIsCore(@"PACC0_PCPU2"));
        for (NSString *name in @[@"ECPU0", @"MCPU0", @"GPU0", @"CPU4", @"NOTPCPU0", @"PCPUx", @"PCPU0junk"])
            assert(!PIsCore(name));
        assert(PExplicitMHz(@"2.5 GHz") == 2500);
        assert(PExplicitMHz(@"1500MHz") == 1500);
        assert(PExplicitMHz(@"1500000 kHz") == 1500);
        assert(PExplicitMHz(@"1500000000 Hz") == 1500);
        for (NSString *name in @[@"V0P1", @"P1", @"1500", @"nan GHz", @"0 MHz", @"-1 MHz", @"1 THz", @"1500 MHz junk"])
            assert(PExplicitMHz(name) == 0);
        NSString *reason = nil;
        NSArray *states = @[S(@"IDLE", 900), S(@"1000 MHz", 25), S(@"2000 MHz", 75)];
        assert(PCompute(@[R(@"PCPU0", states)], &reason) == 1750);
        // Unequal busy time: aggregate P-core residency, not per-core arithmetic average.
        NSArray *rows = @[R(@"PCPU0", states), R(@"PCPU1", @[S(@"OFF", 700), S(@"3000 MHz", 300)]),
                          R(@"ECPU0", @[S(@"V0P1", 999999)])];
        assert(PCompute(rows, &reason) == 2687.5);
        NSMutableDictionary *complex = [R(@"PCPU", @[S(@"9000 MHz", 999999)]) mutableCopy];
        complex[@"subgroup"] = @"CPU Complex Performance States";
        assert(PCompute([rows arrayByAddingObject:complex], &reason) == 2687.5);
        assert(PCompute(@[R(@"PCPU0", @[S(@"DOWN", 10)])], &reason) == 0);
        assert([reason isEqualToString:@"no-active-pcore-residency"]);
        assert(PCompute(@[R(@"PCPU0", @[S(@"V0P1", 0), S(@"2000 MHz", 10)])], &reason) == 0);
        assert([reason isEqualToString:@"unmapped-state-needs-device-evidence"]);
        assert(PCompute(@[R(@"PCPU0", @[S(@"IDLE", -1), S(@"2000 MHz", 10)])], &reason) == 0);
        assert([reason isEqualToString:@"counter-reset-or-invalid"]);
        assert(PCompute(@[R(@"PCPU0", states), R(@"PCPU0", states)], &reason) == 0);
        assert(PCompute(@[R(@"CPU4", states), R(@"PCPU0", states)], &reason) == 0);
        assert([reason isEqualToString:@"unclassified-core-channel"]);
        assert(PCompute(@[R(@"ECPU0", states)], &reason) == 0); // no E fallback
        NSMutableDictionary *other = [R(@"PCPU1", states) mutableCopy];
        other[@"unit"] = @"us";
        assert(PCompute(@[R(@"PCPU0", states), other], &reason) == 0);
        other[@"unit"] = @"ns"; other[@"driver"] = @2;
        assert(PCompute(@[R(@"PCPU0", states), other], &reason) == 0);
        NSArray *changedCounters = @[R(@"PCPU0", @[S(@"IDLE", 100), S(@"1000 MHz", 8), S(@"2000 MHz", 2)])];
        assert([PTopology(@[R(@"PCPU0", states)]) isEqual:PTopology(changedCounters)]);
        assert(![PTopology(rows) isEqual:PTopology(changedCounters)]);
        puts("P-core production parser/reducer: PASS");
    }
    return 0;
}
