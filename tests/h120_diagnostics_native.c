#include "../hello120hz/Shared/H120RecordingDiagnostics.h"
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

int main(int argc, char **argv) {
    assert(argc >= 2);
    if (!strcmp(argv[1], "paths")) {
        char root[] = "/tmp/h120-diagnostic.XXXXXX"; assert(mkdtemp(root));
        char directory[256], path[256]; int error;
        snprintf(directory, sizeof(directory), "%s/missing/child", root);
        snprintf(path, sizeof(path), "%s/missing/child/recording.jsonl", root);
        assert(H120DiagnosticOpenLogAt(directory, path, &error) < 0 && error == ENOENT);
        snprintf(directory, sizeof(directory), "%s/logs", root);
        snprintf(path, sizeof(path), "%s/logs/recording.jsonl", root);
        int fd = H120DiagnosticOpenLogAt(directory, path, &error); assert(fd >= 0 && !error); close(fd);
        unlink(path); assert(chmod(directory, 0500) == 0);
        assert(H120DiagnosticOpenLogAt(directory, path, &error) < 0 && error == EACCES);
        assert(chmod(directory, 0755) == 0); assert(symlink("/dev/null", path) == 0);
        assert(H120DiagnosticOpenLogAt(directory, path, &error) < 0 && error == ELOOP);
        unlink(path); rmdir(directory); assert(symlink(root, directory) == 0);
        assert(H120DiagnosticOpenLogAt(directory, path, &error) < 0 && error == ENOTDIR);
        unlink(directory); rmdir(root);
        puts("PASS production POSIX log path selection: no parent/permission/symlink/errno"); return 0;
    }
    int client = strstr(argv[1], "client") != NULL;
    if (!strcmp(argv[1], "server") || !strcmp(argv[1], "client-server")) {
        assert(argc == 4);
        if (client) {
            H120DiagnosticStartNamed(H120_CLIENT_DIAGNOSTIC_PING);
            H120DiagnosticUpdateClient(8, atoi(argv[3]), 1, (unsigned)atoi(argv[2]));
        } else {
            H120DiagnosticStart(); H120DiagnosticUpdate(15, atoi(argv[3]), 1); H120DiagnosticLogError(atoi(argv[2]));
        }
        printf("READY %d\n", getpid()); fflush(stdout); dispatch_main();
    }
    assert(argc == 5);
    int pid = atoi(argv[2]), error = atoi(argv[3]), active = atoi(argv[4]);
    void (^done)(uint64_t, unsigned) = ^(uint64_t state, unsigned status) {
        assert(status == 0);
        if (pid == 0) assert(state == 0);
        else {
            assert(state != 0 && (state >> 48) == H120_DIAGNOSTIC_VERSION);
            assert(((state >> 24) & 0xffffff) == (unsigned)pid);
            assert(((state >> 12) & 4095) == (unsigned)error);
            assert(((state >> 11) & 1) == 1);
            assert(((state >> 10) & 1) == (unsigned)active);
            assert(((state >> 6) & 15) == (client ? 8u : 15u));
            assert((state >> 48) != 50903); // old full3 must never be reported as full4
        }
        printf("PASS production Darwin notification %s state=%016llx status=%u\n", pid ? "ack/version/PID/hooks/disabled/errno" : "timeout-no-false-ack", (unsigned long long)state, status);
        exit(0);
    };
    if (client) H120DiagnosticProbeNamed(H120_CLIENT_DIAGNOSTIC_PING, 0.5, done);
    else H120DiagnosticProbe(0.5, done);
    dispatch_main();
}
