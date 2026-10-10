#ifndef SBCPU_REFRESH_REQUEST_POLICY_H
#define SBCPU_REFRESH_REQUEST_POLICY_H
#include <string.h>
#include <stddef.h>
/* Known ProMotion hardware, independent of any other tweak spoofing UIScreen.
 * Unknown/future models fail closed and need explicit verification before adding. */
static inline int SBCPURefreshHardware120(const char *model) {
    static const char * const models[] = {
        "iPhone14,2", "iPhone14,3", "iPhone15,2", "iPhone15,3", "iPhone16,1", "iPhone16,2", "iPhone17,1", "iPhone17,2",
        "iPad7,1", "iPad7,2", "iPad7,3", "iPad7,4",
        "iPad8,1", "iPad8,2", "iPad8,3", "iPad8,4", "iPad8,5", "iPad8,6", "iPad8,7", "iPad8,8", "iPad8,9", "iPad8,10", "iPad8,11", "iPad8,12",
        "iPad13,4", "iPad13,5", "iPad13,6", "iPad13,7", "iPad13,8", "iPad13,9", "iPad13,10", "iPad13,11",
        "iPad14,3", "iPad14,4", "iPad14,5", "iPad14,6", "iPad16,3", "iPad16,4", "iPad16,5", "iPad16,6"
    };
    if (!model) return 0;
    for (size_t i=0;i<sizeof(models)/sizeof(models[0]);i++) if (strcmp(model,models[i]) == 0) return 1;
    return 0;
}
/* Fail closed on unknown lock/display state; serious thermal state (2+) and LPM
 * always win. Never changes insulation/thermal daemon settings. */
static inline const char *SBCPURefreshPauseReason(int enabled, int capability, int abi,
                                                int lockKnown, int locked, int displayKnown,
                                                int displayOn, int lowPower, int thermal) {
    if (!enabled) return "开关关闭";
    if (capability < 120) return "原始能力低于120Hz，不支持";
    if (!abi) return "公开请求selector或ABI不可用";
    if (!lockKnown || !displayKnown) return "锁屏/显示状态未知，安全暂停";
    if (locked) return "锁屏/AOD，已停止";
    if (!displayOn) return "屏幕熄灭，已停止";
    if (lowPower) return "低电量模式，已停止";
    if (thermal >= 2) return "高温保护，已停止";
    return "";
}
#endif
