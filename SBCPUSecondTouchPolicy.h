#ifndef SBCPU_SECOND_TOUCH_POLICY_H
#define SBCPU_SECOND_TOUCH_POLICY_H
/* Only the second text window: ignore its entire surface when locked.
 * Modal UI stays on the original window, whose interaction is untouched. */
static inline int SBCPUSecondTouchIgnored(int locked, int enabled, int visible, int modal) {
    return locked || !enabled || !visible || modal;
}
#endif
