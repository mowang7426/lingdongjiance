#ifndef SBCPUPeachDock_DOCK_DROP_GEOMETRY_H
#define SBCPUPeachDock_DOCK_DROP_GEOMETRY_H
#include <math.h>
#include <stdbool.h>
// The existing four-icon / 89pt layout, shared by forward and inverse maps.
static inline bool SBCPUPeachDockDropCenterX(unsigned column, unsigned capacity, double width,
                                    double pitch, double *center) {
    if (!center || !column || column > capacity || !isfinite(width) ||
        !isfinite(pitch) || pitch <= 0 || width <= 3 * pitch) return false;
    unsigned index = column - 1;
    *center = (index / 4) * width + (width - 3 * pitch) / 2 + (index % 4) * pitch;
    return isfinite(*center);
}
static inline bool SBCPUPeachDockDropColumnAtX(double x, unsigned capacity, double width,
                                      double pitch, unsigned *column, double *fraction) {
    if (!column || !capacity || !isfinite(x) || !isfinite(width) ||
        !isfinite(pitch) || pitch <= 0 || width <= 3 * pitch || x < 0 ||
        x >= ((capacity + 3) / 4) * width) return false;
    unsigned page = (unsigned)floor(x / width);
    double first = (width - 3 * pitch) / 2;
    double slotValue = floor((x - page * width - first) / pitch + 0.5);
    unsigned slot = (unsigned)fmax(0, fmin(3, slotValue));
    unsigned col = page * 4 + slot + 1;
    if (col > capacity) col = capacity;
    double center;
    if (!SBCPUPeachDockDropCenterX(col, capacity, width, pitch, &center)) return false;
    *column = col;
    if (fraction) {
        // Match the native meaning: distance THROUGH the selected column's
        // midpoint-bounded region, not distance from its center / fixed pitch.
        // Page-edge regions are wider, and their icon center is not fraction .5.
        double left = 0, right = ((capacity + 3) / 4) * width, adjacent;
        if (col > 1) {
            if (!SBCPUPeachDockDropCenterX(col - 1, capacity, width, pitch, &adjacent)) return false;
            left = (adjacent + center) / 2;
        }
        if (col < capacity) {
            if (!SBCPUPeachDockDropCenterX(col + 1, capacity, width, pitch, &adjacent)) return false;
            right = (center + adjacent) / 2;
        }
        if (!isfinite(left) || !isfinite(right) || right <= left) return false;
        *fraction = fmax(0, fmin(1, (x - left) / (right - left)));
    }
    return true;
}
#endif
