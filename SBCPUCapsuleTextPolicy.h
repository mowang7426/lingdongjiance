#ifndef SBCPU_CAPSULE_TEXT_POLICY_H
#define SBCPU_CAPSULE_TEXT_POLICY_H
// No preference normalization here: only the existing explicit mode 4 opts in.
static inline int SBCPUCapsuleTextEnabled(int mode, int textOnly, int notification,
                                        int startup, int collapsed, int folded,
                                        int visible, int hasText) {
    return mode == 4 && !textOnly && !notification && !startup &&
           (!!collapsed == !!folded) && visible && hasText;
}
#endif
