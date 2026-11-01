// SYNTHETIC fixtures. No claim of additional real-device compatibility.
#import "../SBCPUPCoreFrequency.m"
#import <assert.h>
static void LE(NSMutableData *d, NSUInteger i, uint32_t x) {
    uint8_t *p = (uint8_t *)d.mutableBytes + i * 8;
    for (NSUInteger j = 0; j < 4; j++) p[j] = (uint8_t)(x >> (j * 8));
}
static NSDictionary *Fixture(NSUInteger n) {
    NSMutableData *a = [NSMutableData dataWithLength:n*8], *b = [NSMutableData dataWithLength:n*8];
    NSMutableArray *states = [NSMutableArray arrayWithObject:@{@"name":@"IDLE", @"residency":@99999}];
    for (NSUInteger k=0; k<n; k++) {
        uint32_t hz = (uint32_t)(300000000 + k*10000000);
        LE(a,k,hz); LE(b,k,(uint32_t)(65536000000000ULL/hz));
        [states addObject:@{@"name":[NSString stringWithFormat:@"V%luP%lu",(unsigned long)k,(unsigned long)(n-1-k)], @"residency":@(k+1)}];
    }
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *name in @[@"PCPU0",@"PCPU1",@"ECPU0"])
        [rows addObject:@{@"group":@"CPU Stats",@"subgroup":@"CPU Core Performance States",@"channel":name,@"unit":@"24Mticks",@"driver":@42,@"states":states}];
    return @{@"channels":rows,@"tables":@[@{@"node":@"pmgr",@"rawProperties":@{@"voltage-states5-sram":a,@"voltage-states5":b}}]};
}
static NSMutableDictionary *Clone(NSDictionary *d) {
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:d format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    return [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainersAndLeaves format:NULL error:NULL];
}
static double Run(NSDictionary *d, NSString *machine, NSString **why) {
    return PComputeMapped(d[@"channels"],machine,@"synthetic OS, not device evidence",d[@"tables"],why);
}
int main(void) { @autoreleasepool {
    NSArray *machines=@[@"iPhone13,1",@"iPhone13,2",@"iPhone13,3",@"iPhone13,4",@"iPhone14,2",@"iPhone14,3",@"iPhone14,4",@"iPhone14,5",@"iPhone14,7",@"iPhone14,8",@"iPhone15,2",@"iPhone15,3",@"iPhone15,4",@"iPhone15,5",@"iPhone16,1",@"iPhone16,2"];
    assert([PChip(@"iPhone12,1") isEqual:@"A13"]);
    assert([PChip(@"iPhone14,8") isEqual:@"A15"]);
    assert([PChip(@"iPhone15,5") isEqual:@"A16"]);
    assert([PChip(@"iPhone16,2") isEqual:@"A17Pro"]);
    for (NSNumber *count in @[@2,@7,@19,@31,@255]) {
        NSUInteger n=count.unsignedIntegerValue; NSDictionary *d=Fixture(n); NSString *why=nil;
        double expected=300.0+10.0*(2.0*(double)(n-1)/3.0);
        for (NSString *machine in machines) assert(fabs(Run(d,machine,&why)-expected)<1e-9);
        for (NSString *machine in @[@"iPhone12,1",@"iPhone12,3",@"iPhone12,5"]) {
            assert(Run(d,machine,&why)==0); assert([why isEqual:@"unverified-chip-mapping"]);
        }
        assert(Run(d,@"iPhone99,1",&why)==0); assert([why isEqual:@"unsupported-model"]);
        NSMutableDictionary *x=Clone(d); x[@"channels"][0][@"channel"]=@"PACC0_PCPU0";
        assert(Run(x,@"iPhone13,1",&why)==0);
        x=Clone(d); x[@"channels"][0][@"channel"]=@"CPU4";
        assert(Run(x,@"iPhone13,1",&why)==0);
        x=Clone(d); [x[@"channels"] removeObjectAtIndex:1]; assert(Run(x,@"iPhone13,1",&why)==0);
        x=Clone(d); x[@"tables"][0][@"rawProperties"][@"acc-clusters"]=[NSMutableData dataWithLength:16];
        assert(Run(x,@"iPhone13,1",&why)==0);
        x=Clone(d); NSMutableData *a=x[@"tables"][0][@"rawProperties"][@"voltage-states5-sram"];
        LE(a,0,300000); assert(Run(x,@"iPhone13,1",&why)==0); // kHz not Hz
        x=Clone(d); [x[@"channels"][0][@"states"] removeLastObject]; assert(Run(x,@"iPhone13,1",&why)==0);
    }
    puts("SYNTHETIC multi-count/model/topology/fail-closed production regression: PASS");
} return 0; }
