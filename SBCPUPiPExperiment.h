#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <notify.h>
#import <signal.h>
#import <errno.h>
#define SBCPUPiPStatusPath @"/var/mobile/Library/Preferences/com.sbcpu.pip-experiment.status.plist"
#define SBCPUPiPChanged "com.sbcpu.pip-experiment.changed"
#define SBCPUPiPStartRequest "com.sbcpu.pip-experiment.start"
#define SBCPUPiPStopRequest "com.sbcpu.pip-experiment.stop"
#define SBCPUPiPQuery "com.sbcpu.pip-experiment.query"
static inline NSDictionary *SBCPUPiPReadStatus(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:SBCPUPiPStatusPath];
    pid_t pid = [d[@"pid"] intValue];
    if (pid <= 0 || (kill(pid, 0) != 0 && errno == ESRCH))
        return @{@"active": @NO, @"message": @"宿主离线／未加载；不会自动恢复"};
    return d ?: @{};
}
// Only the SpringBoard branch installs this bridge; no AV objects at install time.
#ifdef __cplusplus
extern "C" {
#endif
void SBCPUPiPInstall(UIWindow *(^windowProvider)(void), BOOL (^lockedProvider)(void));
void SBCPUPiPStop(NSString *reason);
#ifdef __cplusplus
}
#endif
