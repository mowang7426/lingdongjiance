#import "../SBCPUTextNetwork.h"
#include <assert.h>
#include <initializer_list>
int main(void) {
    @autoreleasepool {
        assert(SBCPUNetworkInterface("en0"));
        assert(SBCPUNetworkInterface("pdp_ip0"));
        assert(SBCPUNetworkInterface("pdp_ip12"));
        for (const char *name : {"lo0", "utun0", "ipsec0", "awdl0", "bridge0", "en1", "pdp_ip", "pdp_ip0x"})
            assert(!SBCPUNetworkInterface(name));
        NSDictionary *a = @{@"en0:4":@[@1000,@2000], @"pdp_ip0:5":@[@500,@600]};
        NSDictionary *b = @{@"en0:4":@[@3048,@3024], @"pdp_ip0:5":@[@2548,@1624]};
        double rx = 0, tx = 0;
        assert(!SBCPUNetworkDelta(nil, b, 1, &rx, &tx));
        assert(SBCPUNetworkDelta(a, b, 2, &rx, &tx));
        assert(rx == 2048 && tx == 1024);
        assert(SBCPUNetworkDelta(b, b, 1, &rx, &tx) && rx == 0 && tx == 0);
        assert(!SBCPUNetworkDelta(b, a, 1, &rx, &tx));
        assert(!SBCPUNetworkDelta(a, b, 0, &rx, &tx));
        assert(!SBCPUNetworkDelta(a, b, -1, &rx, &tx));
        assert(!SBCPUNetworkDelta(a, b, NAN, &rx, &tx));
        assert(!SBCPUNetworkDelta(a, b, 6, &rx, &tx));
        assert(!SBCPUNetworkDelta(a, @{}, 1, &rx, &tx));
        assert(!SBCPUNetworkDelta(a, @{@"en0:6":@[@3048,@3024]}, 1, &rx, &tx));
        NSDictionary *partialReset = @{@"en0:4":@[@999,@3024], @"pdp_ip0:5":@[@999999,@999999]};
        assert(!SBCPUNetworkDelta(a, partialReset, 1, &rx, &tx));
        assert([SBCPUNetworkRate(0) isEqual:@"0 B/s"]);
        assert([SBCPUNetworkRate(1023) isEqual:@"1023 B/s"]);
        assert([SBCPUNetworkRate(1024) isEqual:@"1.0 KB/s"]);
        assert([SBCPUNetworkRate(1048576) isEqual:@"1.0 MB/s"]);
        assert([SBCPUNetworkRate(NAN) isEqual:@"-- B/s"]);
        assert([SBCPUNetworkRate(-1) isEqual:@"-- B/s"]);
        assert([SBCPUNetworkText(YES, 2048, 1024) isEqual:@"上传 1.0 KB/s · 下载 2.0 KB/s"]);
        assert([SBCPUNetworkText(NO, 2048, 1024) isEqual:@"上传 -- B/s · 下载 -- B/s"]);
    }
    puts("network delta/filter/format regressions: passed");
    return 0;
}
