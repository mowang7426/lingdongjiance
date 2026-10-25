#ifndef SBCPUPeachDock_EDGE_TRANSITION_GEOMETRY_H
#define SBCPUPeachDock_EDGE_TRANSITION_GEOMETRY_H

#include <math.h>

// Unitless, symmetric profiles: sharp+blur never exceeds one. The outermost
// pixels fade to clear instead of leaking over the stationary Dock background.
static inline double SBCPUPeachDockEdgeUnit(double value) {
    return isfinite(value) ? fmax(0.0, fmin(1.0, value)) : 1.0;
}
static inline double SBCPUPeachDockEdgeSharpWeight(double distance, double band) {
    if (!(band > 0.0) || !isfinite(band)) return 1.0;
    double t = SBCPUPeachDockEdgeUnit(distance / band);
    if (t < 0.25) return 0.1 * t / 0.25;
    if (t < 0.60) return 0.1 + 0.45 * (t - 0.25) / 0.35;
    return 0.55 + 0.45 * (t - 0.60) / 0.40;
}
static inline double SBCPUPeachDockEdgeBlurWeight(double distance, double band) {
    if (!(band > 0.0) || !isfinite(band)) return 0.0;
    double t = SBCPUPeachDockEdgeUnit(distance / band);
    if (t < 0.25) return 0.85 * t / 0.25;
    if (t < 0.60) return 0.85 - 0.40 * (t - 0.25) / 0.35;
    return 0.45 * (1.0 - t) / 0.40;
}
static inline double SBCPUPeachDockEdgeBandWidth(double viewportWidth) {
    if (!(viewportWidth > 0.0) || !isfinite(viewportWidth)) return 0.0;
    return fmin(28.0, viewportWidth * 0.15);
}
static inline double SBCPUPeachDockEdgeSafeBand(double band, double viewportWidth,
                                      double restingX, double iconWidth) {
    if (!isfinite(restingX) || !isfinite(iconWidth) || iconWidth <= 0) return band;
    double margin = fmin(restingX, viewportWidth - restingX - iconWidth);
    // Stop the effect before a resting icon's visible rectangle. Removing the
    // masks after settling must not suddenly sharpen half of the first icon.
    return margin >= 0 ? fmin(band, fmax(4.0, margin - 1.0)) : band;
}
static inline double SBCPUPeachDockEdgeViewportX(double iconX, double contentX,
                                      double scrollFrameX, double displayedOffsetX) {
    return iconX + contentX + scrollFrameX - displayedOffsetX;
}
// 2.1.2: whole-icon edge shrink, not a spatial sharp/blur mask. Keep the old
// profile helpers above only for reproducing the 2.1.1 numerical tests.
static inline double SBCPUPeachDockEdgeSmoothStep(double value) {
    if (!isfinite(value)) return 0.0;
    double t = fmax(0.0, fmin(1.0, value));
    return t * t * (3.0 - 2.0 * t);
}
static inline double SBCPUPeachDockEdgeRestingDistance(double current, double viewportWidth,
                                             double restingX, double iconWidth) {
    if (!isfinite(current) || !isfinite(viewportWidth) || !isfinite(restingX) ||
        !isfinite(iconWidth) || current <= 0 || viewportWidth <= 0 || iconWidth <= 0)
        return current;
    double center = restingX + iconWidth * 0.5;
    double distance = fmin(center, viewportWidth - center);
    // A resting icon must already be at scale=1 before tracking stops. If an
    // unusual layout puts its center on/outside the viewport, disable the effect
    // rather than introduce a visible unmask/size jump at rest.
    return fmax(0.0, fmin(current, distance));
}
static inline double SBCPUPeachDockEdgeIconProgress(double centerX, double viewportWidth,
                                          double iconWidth, double neutralDistance) {
    if (!isfinite(centerX) || !isfinite(viewportWidth) || !isfinite(iconWidth) ||
        !isfinite(neutralDistance) || viewportWidth <= 0 || iconWidth <= 0 ||
        neutralDistance <= 0) return 0.0;
    double distance = fmin(centerX, viewportWidth - centerX);
    return fmax(0.0, fmin(1.0,
        (neutralDistance - distance) / (neutralDistance + iconWidth * 0.25)));
}
static inline double SBCPUPeachDockEdgeIconScale(double progress) {
    return 1.0 - 0.45 * SBCPUPeachDockEdgeSmoothStep(progress);
}
static inline double SBCPUPeachDockEdgeIconBlurMix(double progress) {
    return SBCPUPeachDockEdgeSmoothStep(progress);
}
#endif
