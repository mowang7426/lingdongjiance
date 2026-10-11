#ifndef SBCPU_TEXT_ONLY_POLICY_H
#define SBCPU_TEXT_ONLY_POLICY_H
#include <math.h>
static inline int SBCPUTextOnlyDockEffective(int configured, int textOnly) {
    return configured && !textOnly;
}
static inline double SBCPUTextOnlyBound(double value, double low, double high, double fallback) {
    if (!isfinite(value)) return fallback;
    return fmax(low, fmin(high, value));
}
static inline double SBCPUTextOnlyAnchorX(int preset, double width, double halfWidth) {
    return preset == 0 ? halfWidth + 4 : (preset == 2 ? width - halfWidth - 4 : width * 0.5);
}
static inline double SBCPUTextOnlyTop(int enabled, double safeTop, int dock) {
    return enabled ? 0 : (dock ? fmax(0, safeTop + 2) : fmax(20, safeTop + (safeTop > 0 ? 8 : 0)));
}
// Bounds are measured before the floating view's orientation transform.
static inline double SBCPUTextOnlyAvailableWidth(double width, double height, int rotated) {
    double logicalWidth = rotated ? height : width;
    return fmax(1, logicalWidth - 8);
}
static inline double SBCPUTextOnlyFitFont(double naturalWidth, double available, double configured) {
    configured = SBCPUTextOnlyBound(configured, 8, 24, 13);
    if (!isfinite(naturalWidth) || naturalWidth <= 0) return configured;
    // Small padding protects the last glyph; never shrink below readable 8pt.
    // If the row still does not fit, the caller wraps rather than drops fields.
    return fmax(8, fmin(configured, configured * fmax(1, available - 2) / naturalWidth));
}
#endif
