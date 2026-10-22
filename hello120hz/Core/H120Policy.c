#include "H120Policy.h"

bool H120ClientEnabled(bool requested, bool excluded) { return requested && !excluded; }

float H120NormalizeFPS(float fps) {

    if (fps == 10.0f || fps == 30.0f || fps == 60.0f || fps == 80.0f) return fps;
    return 120.0f;
}

uint32_t H120CadenceForFPS(float fps) {
    return (uint32_t)(240.0f / H120NormalizeFPS(fps));
}

bool H120SystemAllowsOverride(bool enabled, bool lowPower, int thermalState) {
    return enabled && !lowPower && thermalState >= 0 && thermalState < 2;
}

uint32_t H120ChooseCadence(uint32_t original, uint32_t policy, uint32_t hardwareMinimum) {

    // Original unit is 240/FPS, not a float FPS or CMTime. Only the original
    // user-selectable cadences and a nonzero hardware minimum are admissible.
    bool knownPolicy = policy == 2 || policy == 3 || policy == 4 || policy == 8 || policy == 24;
    if (original <= 1 || !knownPolicy || !hardwareMinimum || original == policy) return original;
    return policy >= hardwareMinimum ? policy : original;
}
