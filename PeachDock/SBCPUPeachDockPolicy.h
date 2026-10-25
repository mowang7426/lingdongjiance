#ifndef SBCPU_PEACH_DOCK_POLICY_H
#define SBCPU_PEACH_DOCK_POLICY_H
#include <stdbool.h>
#include <math.h>
// The archive documents 16.2 coordinate semantics but provides no independently
// captured model identity or lossless uninstall proof. No profile is approved.
// Do NOT turn this into a version-only allowlist.
static inline bool SBCPUPeachDockProfileApproved(int major, int minor) {
    (void)major; (void)minor;
    return false;
}
static inline double SBCPUPeachDockPitch(double width) {
    return isfinite(width) && width > 0 ? width / 4.0 : 0.0;
}
static inline bool SBCPUPeachDockVisualPolicy(bool enabled, bool lowPower,
                                             int thermal, bool reduceMotion,
                                             bool reduceTransparency) {
    return enabled && !lowPower && thermal < 2 &&
           !reduceMotion && !reduceTransparency;
}
#endif
