#include "../hello120hz/Shared/H120DiagnosticSession.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
int main(void) {
    H120ProbeChannel recording = H120ProbeBegin(100, 1.5), client = H120ProbeBegin(100, 1.5);
    assert(!H120ProbeCanExport(1, &recording, &client));
    assert(!H120ProbeExpire(&recording, 101));
    assert(H120ProbeFinish(&recording, UINT64_C(50906) << 48, 0, 101));
    assert(recording.status == H120ProbeCompleted && recording.receipt);
    assert(!H120ProbeCanExport(1, &recording, &client));
    assert(H120ProbeExpire(&client, 101.5));
    assert(client.status == H120ProbeTimeout && client.receipt == 0);
    assert(H120ProbeCanExport(1, &recording, &client));
    assert(!H120ProbeCanExport(0, &recording, &client));
    assert(!H120ProbeFinish(&client, 123, 0, 102)); // late/stale result cannot rewrite terminal snapshot
    assert(client.status == H120ProbeTimeout && !client.receipt);
    client = H120ProbeBegin(200, 1.5);
    assert(H120ProbeFinish(&client, 0, 7, 200.1));
    assert(client.status == H120ProbeFailure && client.transport == 7);
    assert(H120ProbeCanExport(1, &recording, &client));
    assert(!strcmp(H120ProbeStatusName(client.status), "transport-failure"));
    assert(!H120ProbeExpire(&recording, 500));
    puts("PASS production two-channel export state: pending/completed/timeout/failure/late reply");
    return 0;
}
