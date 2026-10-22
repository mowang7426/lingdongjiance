#pragma once
#include <string.h>

// Exact executable routing is shared by the sole production constructor and
// native regression tests. No Foundation/process-name mutation before routing.
typedef void (*H120ProcessEntry)(void);
typedef struct {
    H120ProcessEntry client;
    H120ProcessEntry backboard;
    H120ProcessEntry recording;
} H120ProcessEntries;

static inline void H120EnterProcess(const char *name, H120ProcessEntries entries) {
    if (!name || !*name) return; // fail closed on an unavailable executable name
    H120ProcessEntry entry = !strcmp(name, "replayd") ? entries.recording
        : !strcmp(name, "backboardd") ? entries.backboard : entries.client;
    if (entry) entry();
}
