#ifndef SBCPU_TEXT_ANCHOR_POLICY_H
#define SBCPU_TEXT_ANCHOR_POLICY_H
#include <math.h>
typedef struct { double x, y; } SBCPUTextPoint;
typedef struct { int right, bottom; double xMargin, yMargin; } SBCPUTextAnchor;
static inline SBCPUTextPoint SBCPUTextPointMake(double x, double y) { SBCPUTextPoint p = {x,y}; return p; }
/* rotation: 0 oriented container; +1/-1 landscape in a portrait container;
 * 2 upside down in a portrait container. No UIKit/window conversion is repeated. */
static inline SBCPUTextPoint SBCPUTextToLogical(SBCPUTextPoint p, double w, double h, int rotation) {
    if (rotation == 1) return SBCPUTextPointMake(p.y, w-p.x);
    if (rotation == -1) return SBCPUTextPointMake(h-p.y, p.x);
    if (rotation == 2) return SBCPUTextPointMake(w-p.x, h-p.y);
    return p;
}
static inline SBCPUTextPoint SBCPUTextFromLogical(SBCPUTextPoint p, double w, double h, int rotation) {
    if (rotation == 1) return SBCPUTextPointMake(w-p.y, p.x);
    if (rotation == -1) return SBCPUTextPointMake(p.y, h-p.x);
    if (rotation == 2) return SBCPUTextPointMake(w-p.x, h-p.y);
    return p;
}
static inline SBCPUTextAnchor SBCPUTextCaptureAnchor(SBCPUTextPoint p, double w, double h, double hw, double hh,
                                                    double left, double top, double right, double bottom) {
    SBCPUTextAnchor a;
    a.right = p.x > w/2; a.bottom = p.y > h/2;
    a.xMargin = fmax(0, a.right ? w-right-hw-p.x : p.x-left-hw);
    a.yMargin = fmax(0, a.bottom ? h-bottom-hh-p.y : p.y-top-hh);
    return a;
}
static inline double SBCPUTextSafeCoordinate(double p, double lo, double hi) {
    return hi < lo ? (lo+hi)/2 : fmax(lo, fmin(hi, p));
}
static inline SBCPUTextPoint SBCPUTextResolveAnchor(SBCPUTextAnchor a, double w, double h, double hw, double hh,
                                                    double left, double top, double right, double bottom) {
    SBCPUTextPoint p = {a.right ? w-right-hw-a.xMargin : left+hw+a.xMargin,
                       a.bottom ? h-bottom-hh-a.yMargin : top+hh+a.yMargin};
    p.x = SBCPUTextSafeCoordinate(p.x, left+hw, w-right-hw);
    p.y = SBCPUTextSafeCoordinate(p.y, top+hh, h-bottom-hh);
    return p;
}
#endif
