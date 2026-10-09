#ifndef SBCPU_PIP_POLICY_H
#define SBCPU_PIP_POLICY_H
#include <stdbool.h>
#include <stdint.h>
typedef enum { PIPOff, PIPPreparing, PIPStarting, PIPActive, PIPStopping, PIPUnconfirmed, PIPFailed } PiPPhase;
typedef struct { PiPPhase phase; uint64_t generation; } PiPState;
static inline bool PiPBegin(PiPState *s) {
    if (s->phase != PIPOff && s->phase != PIPFailed) return false;
    ++s->generation; s->phase = PIPPreparing; return true;
}
static inline bool PiPStart(PiPState *s, uint64_t g) {
    if (g != s->generation || s->phase != PIPPreparing) return false;
    s->phase = PIPStarting; return true;
}
static inline bool PiPDidStart(PiPState *s, uint64_t g) {
    if (g != s->generation || s->phase != PIPStarting) return false;
    s->phase = PIPActive; return true;
}
static inline bool PiPStop(PiPState *s) {
    if (s->phase == PIPStopping) return true;
    if (s->phase == PIPUnconfirmed) { ++s->generation; s->phase = PIPOff; return false; }
    bool pending = s->phase == PIPStarting || s->phase == PIPActive;
    ++s->generation; s->phase = pending ? PIPStopping : PIPOff; return pending;
}
static inline void PiPStopTimeout(PiPState *s) {
    if (s->phase == PIPStopping) s->phase = PIPUnconfirmed;
}
#endif
