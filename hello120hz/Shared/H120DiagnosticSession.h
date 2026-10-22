#ifndef H120_DIAGNOSTIC_SESSION_H
#define H120_DIAGNOSTIC_SESSION_H
#include <stdint.h>

/* Production presentation state; no notify registration may count as an ACK.
   Each channel has its own deadline and immutable terminal result. */
typedef enum {
    H120ProbePending, H120ProbeCompleted, H120ProbeTimeout, H120ProbeFailure
} H120ProbeStatus;
typedef struct {
    H120ProbeStatus status;
    uint64_t receipt;
    unsigned transport;
    double startedAt, finishedAt, deadline;
} H120ProbeChannel;
static inline H120ProbeChannel H120ProbeBegin(double now, double timeout) {
    H120ProbeChannel channel = {H120ProbePending, 0, 0, now, 0, now + timeout};
    return channel;
}
static inline int H120ProbeFinish(H120ProbeChannel *channel, uint64_t receipt,
                                  unsigned transport, double now) {
    if (channel->status != H120ProbePending) return 0;
    channel->status = transport ? H120ProbeFailure : receipt ? H120ProbeCompleted : H120ProbeTimeout;
    channel->receipt = receipt; channel->transport = transport; channel->finishedAt = now;
    return 1;
}
static inline int H120ProbeExpire(H120ProbeChannel *channel, double now) {
    if (channel->status != H120ProbePending || now < channel->deadline) return 0;
    return H120ProbeFinish(channel, 0, 0, now);
}
static inline int H120ProbeCanExport(int selfCheckReady, const H120ProbeChannel *recording,
                                   const H120ProbeChannel *client) {
    return selfCheckReady && recording->status != H120ProbePending && client->status != H120ProbePending;
}
static inline const char *H120ProbeStatusName(H120ProbeStatus status) {
    switch (status) {
        case H120ProbePending: return "pending";
        case H120ProbeCompleted: return "completed";
        case H120ProbeTimeout: return "timeout";
        case H120ProbeFailure: return "transport-failure";
    }
    return "invalid";
}
#endif
