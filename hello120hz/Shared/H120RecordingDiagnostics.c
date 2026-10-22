#include "H120RecordingDiagnostics.h"
#include <notify.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>
#include <sys/stat.h>

static const char *pingName = "cn.zqbb.hello120hz.recording.diagnostic.v4.ping";
static atomic_uint hooksState, activeState, preferencesState, logError;
/* [63:48] protocol/build 50905, [47:24] PID, [23:12] errno,
   [11] preferences readable, [10] enabled, [9:6] hooks, [5:0] reserved. */
uint64_t H120DiagnosticState(void) {
    return ((uint64_t)H120_DIAGNOSTIC_VERSION << 48) | ((uint64_t)(getpid() & 0xffffff) << 24) |
        ((uint64_t)(atomic_load(&logError) & 4095) << 12) |
        ((uint64_t)(atomic_load(&preferencesState) != 0) << 11) |
        ((uint64_t)(atomic_load(&activeState) != 0) << 10) |
        ((uint64_t)(atomic_load(&hooksState) & 15) << 6);
}
void H120DiagnosticUpdate(unsigned hooks, int active, int readable) {
    atomic_store(&hooksState, hooks); atomic_store(&activeState, active); atomic_store(&preferencesState, readable);
}
void H120DiagnosticLogError(int error) { atomic_store(&logError, error < 0 ? EIO : (unsigned)error); }
int H120DiagnosticOpenLogAt(const char *directory, const char *path, int *error) {
    *error = 0;
    /* Only our final directory is created. Never chmod shared parents, follow
       a directory symlink, map /var/mobile through jbroot or weaken a sandbox. */
    if (mkdir(directory, 0755) != 0 && errno != EEXIST) { *error = errno; return -1; }
    struct stat st;
    if (lstat(directory, &st) != 0) { *error = errno; return -1; }
    if (!S_ISDIR(st.st_mode)) { *error = ENOTDIR; return -1; }
    int fd = open(path, O_CREAT | O_WRONLY | O_APPEND | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0644);
    if (fd < 0) { *error = errno; return -1; }
    if (fstat(fd, &st) != 0) { *error = errno; close(fd); return -1; }
    if (!S_ISREG(st.st_mode)) { *error = EINVAL; close(fd); return -1; }
    return fd;
}
void H120DiagnosticUpdateClient(unsigned count, int active, int readable, unsigned target) {
    H120DiagnosticUpdate(count, active, readable); atomic_store(&logError, target);
}
void H120DiagnosticStart(void) { H120DiagnosticStartNamed(pingName); }
void H120DiagnosticStartNamed(const char *ping) {
    static int token = -1;
    dispatch_queue_t queue = dispatch_queue_create("cn.zqbb.hello120hz.diagnostic", DISPATCH_QUEUE_SERIAL);
    unsigned status = notify_register_dispatch(ping, &token, queue, ^(int request) {
        uint64_t nonce = 0;
        if (notify_get_state(request, &nonce) != NOTIFY_STATUS_OK || !nonce) return;
        char reply[128]; snprintf(reply, sizeof(reply), "cn.zqbb.hello120hz.recording.diagnostic.v4.reply.%016llx", (unsigned long long)nonce);
        int response = -1;
        unsigned result = notify_register_check(reply, &response);
        if (result == NOTIFY_STATUS_OK) {
            result = notify_set_state(response, H120DiagnosticState());
            if (result == NOTIFY_STATUS_OK) result = notify_post(reply);
            notify_cancel(response);
        }
        if (result != NOTIFY_STATUS_OK) fprintf(stderr, "Hello120Hz diagnostic reply notify status=%u\n", result);
    });
    if (status != NOTIFY_STATUS_OK) fprintf(stderr, "Hello120Hz diagnostic register notify status=%u\n", status);
    dispatch_release(queue);
}
void H120DiagnosticProbe(double timeout, void (^completion)(uint64_t, unsigned)) {
    H120DiagnosticProbeNamed(pingName, timeout, completion);
}
void H120DiagnosticProbeNamed(const char *ping, double timeout, void (^completion)(uint64_t, unsigned)) {
    uint64_t nonce = ((uint64_t)arc4random() << 32) | arc4random();
    if (!nonce) nonce = 1;
    char reply[128]; snprintf(reply, sizeof(reply), "cn.zqbb.hello120hz.recording.diagnostic.v4.reply.%016llx", (unsigned long long)nonce);
    __block int response = -1;
    __block int request = -1;
    __block int finished = 0;
    unsigned status = notify_register_dispatch(reply, &response, dispatch_get_main_queue(), ^(int token) {
        if (finished) return;
        uint64_t state = 0; unsigned result = notify_get_state(token, &state);
        if (result == NOTIFY_STATUS_OK && !state) return; // registration is NOT an acknowledgement
        finished = 1; notify_cancel(response); if (request >= 0) notify_cancel(request);
        completion(state, result);
    });
    if (status == NOTIFY_STATUS_OK) status = notify_register_check(ping, &request);
    if (status == NOTIFY_STATUS_OK) status = notify_set_state(request, nonce);
    if (status == NOTIFY_STATUS_OK) status = notify_post(ping);
    if (status != NOTIFY_STATUS_OK) {
        finished = 1; if (response >= 0) notify_cancel(response); if (request >= 0) notify_cancel(request);
        completion(0, status); return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (finished) return;
        finished = 1; notify_cancel(response); notify_cancel(request);
        completion(0, NOTIFY_STATUS_OK); // no response: unloaded OR IPC restricted, not proof of either
    });
}
