#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include "../hello120hz/Core/H120Process.h"
#include "../hello120hz/Core/H120Policy.h"

static unsigned clients, backboards, recordings;
static void client(void) { ++clients; }
static void backboard(void) { ++backboards; }
static void recording(void) { ++recordings; }
int main(void) {
    // These are genuine function-pointer providers, not strings/source checks.
    H120ProcessEntries entries = {client, backboard, recording};
    H120EnterProcess("SpringBoard", entries);
    H120EnterProcess("Preferences", entries);
    H120EnterProcess("ordinary-client", entries);
    assert(clients == 3 && !backboards && !recordings);
    H120EnterProcess("replayd", entries);
    assert(clients == 3 && !backboards && recordings == 1);
    H120EnterProcess("backboardd", entries);
    assert(clients == 3 && backboards == 1 && recordings == 1);
    H120EnterProcess(NULL, entries); H120EnterProcess("", entries);
    assert(clients == 3 && backboards == 1 && recordings == 1);
    entries.recording = NULL; entries.backboard = NULL;
    H120EnterProcess("replayd", entries); H120EnterProcess("backboardd", entries);
    assert(clients == 3 && backboards == 1 && recordings == 1);
    for (unsigned low = 0; low < 2; ++low)
        for (int thermal = -1; thermal <= 4; ++thermal)
            assert(H120SystemAllowsOverride(true, low, thermal) ==
                (!low && thermal >= 0 && thermal < 2));
    uint32_t policies[] = {2, 3, 4, 8, 24};
    for (unsigned i = 0; i < 5; ++i) {
        uint32_t p = policies[i];
        for (uint32_t hardware = 1; hardware <= 25; ++hardware) {
            uint32_t result = H120ChooseCadence(6, p, hardware);
            assert(result == (p >= hardware ? p : 6));
        }
        assert(H120ChooseCadence(6, p, 0) == 6);
        assert(H120ChooseCadence(6, p, UINT32_MAX) == 6);
        assert(H120ChooseCadence(1, p, 1) == 1);
        assert(H120ChooseCadence(0, p, 1) == 0);
    }
    assert(H120ChooseCadence(4, 0, 2) == 4);
    assert(H120ChooseCadence(4, 120, 2) == 4); // wrong unit rejected
    assert(H120ChooseCadence(4, UINT32_MAX, 2) == 4);
    puts("PASS production constructor routing/function providers/integer cadence boundaries");
}
