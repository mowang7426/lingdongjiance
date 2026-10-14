// Real delta snapshots; invokes the production mapping/reducer, including failure cases.
#import "../SBCPUPCoreFrequency.m"
#import <assert.h>
static NSMutableDictionary *Clone(NSDictionary *d) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:d format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    return [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainersAndLeaves format:NULL error:NULL];
}
static double Compute(NSDictionary *d, NSString **reason) {
    return PComputeMapped(d[@"channels"], d[@"machine"], d[@"os"], d[@"rawTables"], reason);
}
static NSMutableDictionary *Core(NSMutableDictionary *d, NSString *name) {
    for (NSMutableDictionary *r in d[@"channels"]) if ([r[@"channel"] isEqualToString:name]) return r;
    abort();
}
static void Reject(NSDictionary *fixture, void (^mutate)(NSMutableDictionary *)) {
    NSMutableDictionary *d = Clone(fixture); mutate(d); NSString *reason = nil;
    assert(Compute(d, &reason) == 0); assert(reason.length);
}
int main(void) {
    @autoreleasepool {
        NSArray *files = @[@"tests/fixtures/a16/idle.plist", @"tests/fixtures/a16/load.plist"];
        double expected[] = {1447.190419554883, 2074.549863668391};
        for (NSUInteger i = 0; i < files.count; i++) {
            NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:files[i]]; assert(d);
            NSString *reason = nil; double mhz = Compute(d, &reason);
            assert(fabs(mhz - expected[i]) < 1e-9);
            assert([reason isEqualToString:@"structural-table5-sram-active-weighted"]);
            printf("A16 real fixture %lu: %.12f MHz PASS\n", (unsigned long)i, mhz);
            // Identity/OS changed snapshots are synthetic acceptance tests, NOT new device evidence.
            NSMutableDictionary *alternate = Clone(d); alternate[@"machine"] = @"iPhone15,2";
            assert(fabs(Compute(alternate, &reason) - expected[i]) < 1e-9);
            alternate[@"os"] = @"Version 17.0 (Build 21A330)";
            assert(fabs(Compute(alternate, &reason) - expected[i]) < 1e-9);
            Reject(d, ^(NSMutableDictionary *x) { x[@"machine"] = @"iPhone12,1"; });
            Reject(d, ^(NSMutableDictionary *x) { x[@"machine"] = @"iPhone99,1"; });
            Reject(d, ^(NSMutableDictionary *x) { x[@"rawTables"][0][@"node"] = @"not-pmgr"; });
            Reject(d, ^(NSMutableDictionary *x) { [x[@"rawTables"] addObject:x[@"rawTables"][0]]; });
            Reject(d, ^(NSMutableDictionary *x) { [x[@"rawTables"][0][@"rawProperties"] removeObjectForKey:@"voltage-states5"]; });
            for (NSNumber *length in @[@135, @128, @144]) {
                Reject(d, ^(NSMutableDictionary *x) { x[@"rawTables"][0][@"rawProperties"][@"voltage-states5-sram"] = [NSMutableData dataWithLength:length.unsignedIntegerValue]; });
            }
            Reject(d, ^(NSMutableDictionary *x) {
                NSMutableDictionary *p = x[@"rawTables"][0][@"rawProperties"];
                NSMutableData *data = [p[@"voltage-states5"] mutableCopy]; ((uint8_t *)data.mutableBytes)[0] ^= 1; p[@"voltage-states5"] = data;
            });
            Reject(d, ^(NSMutableDictionary *x) {
                NSMutableDictionary *p = x[@"rawTables"][0][@"rawProperties"];
                NSMutableData *data = [p[@"voltage-states5-sram"] mutableCopy];
                memcpy((uint8_t *)data.mutableBytes + 8, data.bytes, 4); p[@"voltage-states5-sram"] = data;
            });
            Reject(d, ^(NSMutableDictionary *x) { Core(x, @"PCPU1")[@"unit"] = @"ns"; });
            Reject(d, ^(NSMutableDictionary *x) { Core(x, @"PCPU1")[@"driver"] = @1; });
            Reject(d, ^(NSMutableDictionary *x) { [x[@"channels"] removeObject:Core(x, @"PCPU1")]; });
            Reject(d, ^(NSMutableDictionary *x) { [x[@"channels"] addObject:Core(x, @"PCPU1")]; });
            Reject(d, ^(NSMutableDictionary *x) { Core(x, @"PCPU1")[@"channel"] = @"PCPU2"; });
            Reject(d, ^(NSMutableDictionary *x) { Core(x, @"PCPU0")[@"states"][1][@"name"] = @"V1P15"; });
            Reject(d, ^(NSMutableDictionary *x) { [Core(x, @"PCPU0")[@"states"] exchangeObjectAtIndex:1 withObjectAtIndex:2]; });
            Reject(d, ^(NSMutableDictionary *x) { [Core(x, @"PCPU0")[@"states"] removeLastObject]; });
            Reject(d, ^(NSMutableDictionary *x) { Core(x, @"PCPU0")[@"states"][1][@"residency"] = @(-1); });
            Reject(d, ^(NSMutableDictionary *x) {
                for (NSString *n in @[@"PCPU0", @"PCPU1"]) for (NSMutableDictionary *s in Core(x, n)[@"states"]) s[@"residency"] = @0;
            });
            // Object IDs are runtime identities, not pinned fixture IDs.
            NSMutableDictionary *changed = Clone(d);
            for (NSString *n in @[@"PCPU0", @"PCPU1"]) Core(changed, n)[@"driver"] = @42;
            assert(fabs(Compute(changed, &reason) - expected[i]) < 1e-9);
            // Non-frequency second field may change without altering the frequency result.
            NSMutableDictionary *p = changed[@"rawTables"][0][@"rawProperties"];
            NSMutableData *data = [p[@"voltage-states5-sram"] mutableCopy];
            ((uint8_t *)data.mutableBytes)[4] ^= 1; p[@"voltage-states5-sram"] = data;
            assert(fabs(Compute(changed, &reason) - expected[i]) < 1e-9);
        }
        puts("A16 production mapping/fixture/fail-closed regressions: PASS");
    }
    return 0;
}
