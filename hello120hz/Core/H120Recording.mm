#import "H120Recording.h"
#import "../Shared/H120Preferences.h"
#import <VideoToolbox/VideoToolbox.h>
#include <atomic>
#include <notify.h>
#include <mach-o/dyld.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#include <dlfcn.h>
#include <pthread.h>
#include <cstring>
#include <cstdint>

#if __has_feature(objc_arc)
#error Compile H120Recording.mm with -fno-objc-arc
#endif

namespace {
constexpr int32_t kRecordingFPS = 120;
std::atomic<bool> recordingActive(false);
bool H120RecordingActive() { return recordingActive.load(std::memory_order_acquire); }
// Event-only, per-event bounded and at most 128 KiB on disk. No media/user payload.
void Event(NSString *event, NSDictionary *fields) {
    @synchronized ([NSMethodSignature class]) {
        static NSMutableDictionary *counts;
        static NSMutableDictionary *previous;
        if (!counts) { counts = [NSMutableDictionary new]; previous = [NSMutableDictionary new]; }
        NSString *key = fields[@"class"] ? [event stringByAppendingString:fields[@"class"]] : event;
        if ([previous[key] isEqual:fields]) return;
        NSUInteger count = [counts[key] unsignedIntegerValue];
        if (count >= 24) return;
        counts[key] = @(count + 1); previous[key] = fields;
        NSString *directory = H120JailbreakPath(@"/var/mobile/Library/Logs/Hello120Hz");
        if (!directory) return;
        [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
        NSString *path = [directory stringByAppendingPathComponent:@"recording.jsonl"];
        int fd = open(path.fileSystemRepresentation, O_CREAT|O_WRONLY|O_APPEND|O_NOFOLLOW, 0644);
        if (fd < 0) { NSLog(@"[Hello120Hz recording] diagnostic file unavailable errno=%d", errno); return; }
        if (geteuid() == 0) { fchown(fd, 501, 501); fchmod(fd, 0644); }
        struct stat st;
        if (fstat(fd, &st) == 0 && st.st_size < 131072) {
            NSMutableDictionary *row = [fields mutableCopy];
            row[@"event"] = event; row[@"time"] = @([[NSDate date] timeIntervalSince1970]);
            NSData *data = [NSJSONSerialization dataWithJSONObject:row options:0 error:NULL];
            if (data && (uint64_t)st.st_size + data.length + 1 <= 131072) {
                write(fd, data.bytes, data.length); write(fd, "\n", 1);
            }
            [row release];
        }
        close(fd);
    }
}
pthread_key_t captureContextKey;
pthread_key_t writerContextKey;
char systemRecordingMarker;
uint32_t installedHooks;
IMP originalCaptureFactory;
IMP originalWriterInputInit;
IMP originalStartSession;
IMP originalMovieWriterSetup;

const char *Unqualified(const char *type) {
    if (!type) return "";
    while (*type && std::strchr("rnNoORV", *type)) ++type;
    return type;
}
bool ExactType(const char *type, const char *expected) {
    return std::strcmp(Unqualified(type), expected) == 0;
}
bool ObjectType(const char *type) {
    type = Unqualified(type);
    return type[0] == '@' && (type[1] == '\0' || type[1] == '"');
}
bool BlockType(const char *type) {
    return ExactType(type, "@?");
}
bool BooleanType(const char *type) {
    return ExactType(type, "B") || ExactType(type, "c");
}
bool TimeType(const char *type) {

    return ExactType(type, "{?=qiIq}") || ExactType(type, "{CMTime=qiIq}");
}
NSMethodSignature *Signature(Class cls, SEL selector, bool classMethod) {
    if (!cls) return nil;
    Method method = classMethod ? class_getClassMethod(cls, selector)
                                : class_getInstanceMethod(cls, selector);
    const char *types = method ? method_getTypeEncoding(method) : nullptr;
    @try { return types ? [NSMethodSignature signatureWithObjCTypes:types] : nil; }
    @catch (NSException *exception) { (void)exception; return nil; }
}
bool HasArguments(NSMethodSignature *signature, NSUInteger count) {
    return signature && signature.numberOfArguments == count;
}
bool ActiveRecordingContext(pthread_key_t key) {
    return H120RecordingActive() && pthread_getspecific(key);
}
void *SetRecordingContext(pthread_key_t key, bool systemRecording) {
    void *previous = pthread_getspecific(key);
    pthread_setspecific(key,
        systemRecording && H120RecordingActive() ? &systemRecordingMarker : nullptr);
    return previous;
}

id CaptureFactory(id receiver, SEL selector, CGSize size, CMTime interval) {
    bool active = ActiveRecordingContext(captureContextKey);
    bool vsync = false;
    // The uploaded setter is class-wide and returns void. Without a verified
    // per-session/reversible option API it can leak 120 into third-party capture.
    // Request a real 1/120 sampling interval; diagnose VSync rather than leak state.
    if (active) interval = CMTimeMake(1, kRecordingFPS);
    using Factory = id (*)(id, SEL, CGSize, CMTime);
    id result = reinterpret_cast<Factory>(originalCaptureFactory)(receiver, selector, size, interval);
    Event(@"capture-request", @{@"active":@(active), @"intervalValue":@(interval.value),
        @"intervalScale":@(interval.timescale), @"vsyncRequested":@(vsync),
        @"vsyncStatusAvailable":@NO, @"vsyncReason":@"class-wide-setter-not-session-safe", @"resultNonNil":@(result != nil)});
    return result;
}

id WriterInputInit(id receiver, SEL selector, NSString *mediaType, NSDictionary *settings) {
    NSDictionary *effective = settings;
    NSMutableDictionary *adjusted = nil;
    if (ActiveRecordingContext(writerContextKey) && [mediaType isEqualToString:AVMediaTypeVideo] &&
        [settings isKindOfClass:[NSDictionary class]]) {
        adjusted = [settings mutableCopy];
        id existing = [settings objectForKey:AVVideoCompressionPropertiesKey];
        NSMutableDictionary *compression = [existing isKindOfClass:[NSDictionary class]]
            ? [existing mutableCopy] : [[NSMutableDictionary alloc] init];
        [compression setObject:@(kRecordingFPS) forKey:AVVideoExpectedSourceFrameRateKey];
        [compression setObject:@(kRecordingFPS) forKey:AVVideoMaxKeyFrameIntervalKey];
        [adjusted setObject:compression forKey:AVVideoCompressionPropertiesKey];
        [compression release];
        effective = adjusted;
    }
    using Init = id (*)(id, SEL, NSString *, NSDictionary *);
    id result;
    @try {
        result = reinterpret_cast<Init>(originalWriterInputInit)(receiver, selector, mediaType, effective);
    } @finally {
        [adjusted release];
    }
    Event(@"writer-request", @{@"active":@(ActiveRecordingContext(writerContextKey)),
        @"overridden":@(adjusted != nil), @"resultNonNil":@(result != nil), @"requestedFPS":@(adjusted ? 120 : 0)});
    return result;
}

template<typename Flag> void StartSession(id receiver, SEL selector, int pid, CGSize size, Flag systemRecording,
                  id contextIDs, id outputHandler, id didStartHandler) {
    Event(@"start-session", @{@"systemRecording":@(systemRecording != 0), @"enabled":@(H120RecordingActive())});
    void *previous = SetRecordingContext(captureContextKey, systemRecording);
    @try {
        using Start = void (*)(id, SEL, int, CGSize, Flag, id, id, id);
        reinterpret_cast<Start>(originalStartSession)(receiver, selector, pid, size,
            systemRecording, contextIDs, outputHandler, didStartHandler);
    } @finally {
        pthread_setspecific(captureContextKey, previous);
    }
}

void MovieWriterSetup(id receiver, SEL selector, id handler) {
    bool systemRecording = false;
    SEL flagSelector = sel_registerName("systemRecording");
    NSMethodSignature *signature = Signature(object_getClass(receiver), flagSelector, false);
    if (HasArguments(signature, 2) && BooleanType(signature.methodReturnType)) {
        if (ExactType(signature.methodReturnType, "c")) {
            systemRecording = reinterpret_cast<signed char (*)(id, SEL)>(objc_msgSend)(receiver, flagSelector) != 0;
        } else {
            systemRecording = reinterpret_cast<bool (*)(id, SEL)>(objc_msgSend)(receiver, flagSelector);
        }
    }
    Event(@"writer-setup", @{@"systemRecording":@(systemRecording), @"enabled":@(H120RecordingActive()),
        @"asyncPropagationSupported":@NO});
    void *previous = SetRecordingContext(writerContextKey, systemRecording);
    @try {
        using Setup = void (*)(id, SEL, id);
        reinterpret_cast<Setup>(originalMovieWriterSetup)(receiver, selector, handler);
    } @finally {
        pthread_setspecific(writerContextKey, previous);
    }
}
}

uint32_t H120InstallRecordingHooks(void) {
    @synchronized ([NSMethodSignature class]) {
        static bool keyReady;
        if (!keyReady) {
            if (pthread_key_create(&captureContextKey, nullptr) != 0) return installedHooks;
            if (pthread_key_create(&writerContextKey, nullptr) != 0) {
                pthread_key_delete(captureContextKey);
                return installedHooks;
            }
            keyReady = true;
        }
        Class capture = NSClassFromString(@"FigScreenCaptureController");
        SEL factory = sel_registerName("screenCaptureControllerWithSize:minIntervalBetweenFrames:");
        NSMethodSignature *signature = Signature(capture, factory, true);
        if (!(installedHooks & H120RecordingCaptureFactory) && HasArguments(signature, 4) &&
            ObjectType(signature.methodReturnType) &&
            ExactType([signature getArgumentTypeAtIndex:2], "{CGSize=dd}") &&
            TimeType([signature getArgumentTypeAtIndex:3])) {
            MSHookMessageEx(object_getClass(capture), factory, (IMP)CaptureFactory, &originalCaptureFactory);
            installedHooks |= H120RecordingCaptureFactory;
        }
        Class writer = NSClassFromString(@"AVAssetWriterInput");
        SEL initializer = sel_registerName("initWithMediaType:outputSettings:");
        signature = Signature(writer, initializer, false);
        if (!(installedHooks & H120RecordingAssetWriterInput) && HasArguments(signature, 4) &&
            ObjectType(signature.methodReturnType) &&
            ObjectType([signature getArgumentTypeAtIndex:2]) &&
            ObjectType([signature getArgumentTypeAtIndex:3])) {
            MSHookMessageEx(writer, initializer, (IMP)WriterInputInit, &originalWriterInputInit);
            installedHooks |= H120RecordingAssetWriterInput;
        }
        Class manager = NSClassFromString(@"RPScreenCaptureManagerIOS");
        SEL start = sel_registerName("startSessionWithPID:windowSize:systemRecording:contextIDs:outputHandler:didStartHandler:");
        signature = Signature(manager, start, false);
        if (!(installedHooks & H120RecordingStartSession) && HasArguments(signature, 8) &&
            ExactType(signature.methodReturnType, "v") &&
            ExactType([signature getArgumentTypeAtIndex:2], "i") &&
            ExactType([signature getArgumentTypeAtIndex:3], "{CGSize=dd}") &&
            BooleanType([signature getArgumentTypeAtIndex:4]) &&
            ObjectType([signature getArgumentTypeAtIndex:5]) &&
            BlockType([signature getArgumentTypeAtIndex:6]) &&
            BlockType([signature getArgumentTypeAtIndex:7])) {
            IMP replacement = ExactType([signature getArgumentTypeAtIndex:4], "c")
                ? (IMP)StartSession<signed char> : (IMP)StartSession<bool>;
            MSHookMessageEx(manager, start, replacement, &originalStartSession);
            installedHooks |= H120RecordingStartSession;
        }

        Class movieWriter = NSClassFromString(@"RPMovieWriter");
        SEL setup = sel_registerName("setUpAssetWriterWithHandler:");
        signature = Signature(movieWriter, setup, false);
        NSMethodSignature *flag = Signature(movieWriter, sel_registerName("systemRecording"), false);
        if (!(installedHooks & H120RecordingMovieWriterSetup) && HasArguments(signature, 3) &&
            ExactType(signature.methodReturnType, "v") && BlockType([signature getArgumentTypeAtIndex:2]) &&
            HasArguments(flag, 2) && BooleanType(flag.methodReturnType)) {
            MSHookMessageEx(movieWriter, setup, (IMP)MovieWriterSetup, &originalMovieWriterSetup);
            installedHooks |= H120RecordingMovieWriterSetup;
        }
        NSArray *classes = @[@"FigScreenCaptureController", @"AVAssetWriterInput", @"RPScreenCaptureManagerIOS", @"RPMovieWriter"];
        SEL selectors[] = {factory, initializer, start, setup};
        for (unsigned i = 0; i < 4; ++i) {
            Class candidate = NSClassFromString(classes[i]);
            Method method = i == 0 ? class_getClassMethod(candidate, selectors[i]) : class_getInstanceMethod(candidate, selectors[i]);
            const char *encoding = method ? method_getTypeEncoding(method) : NULL;
            Event(@"method-gate", @{@"class":classes[i], @"selector":NSStringFromSelector(selectors[i]),
                @"encoding":encoding ? @(encoding) : @"missing", @"installed":@((installedHooks & (1u << i)) != 0),
                @"reason":(installedHooks & (1u << i)) ? @"matched" : method ? @"signature-rejected" : @"missing"});
        }
        return installedHooks;
    }
}
#include "H120RecordingRuntime.inc"
