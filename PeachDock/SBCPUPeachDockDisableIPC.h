#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
// Real cross-process request/reply; never substitute a process-local count.
#define SBCPU_PEACH_DISABLE_PORT CFSTR("com.yourname.sbcpufloating.peach-disable.v2")
static inline NSDictionary *SBCPUPeachDockDisableMessage(NSString *phase, NSString *nonce) {
    CFMessagePortRef remote = CFMessagePortCreateRemote(kCFAllocatorDefault, SBCPU_PEACH_DISABLE_PORT);
    if (!remote) return nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"phase":phase, @"nonce":nonce} options:0 error:nil];
    CFDataRef reply = NULL;
    SInt32 result = CFMessagePortSendRequest(remote, 1, (__bridge CFDataRef)data,
        2.0, 2.0, kCFRunLoopDefaultMode, &reply);
    CFRelease(remote);
    NSData *response = CFBridgingRelease(reply);
    if (result != kCFMessagePortSuccess || !response) return nil;
    id decoded = [NSJSONSerialization JSONObjectWithData:response options:0 error:nil];
    if (![decoded isKindOfClass:NSDictionary.class] || ![decoded[@"nonce"] isEqual:nonce]) return nil;
    return decoded;
}
