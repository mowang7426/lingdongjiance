#import <UIKit/UIKit.h>
#import "h120_stubs/Preferences/PSSpecifier.h"
#import "../hello120hz/Shared/H120Preferences.mm"
#import "../hello120hz/Preferences/H120SettingsController.mm"
#include <assert.h>
@implementation PSSpecifier
+ (instancetype)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set get:(SEL)get detail:(Class)detail cell:(NSInteger)cell edit:(Class)edit {
 (void)name;(void)target;(void)set;(void)get;(void)detail;(void)cell;(void)edit;
 PSSpecifier *s=[self new];s.testProperties=[NSMutableDictionary new];return s;
}
- (id)propertyForKey:(NSString *)key{return self.testProperties[key];}
- (void)setProperty:(id)value forKey:(NSString *)key{self.testProperties[key]=value;}
@end
@interface ATLApplicationListMultiSelectionController : UIViewController
@property(nonatomic,strong) PSSpecifier *specifier;
@property(nonatomic,weak) id parentController;
@end
@implementation ATLApplicationListMultiSelectionController @end
@interface H120TestController : H120SettingsController
@property(nonatomic,strong) UIViewController *lastPresentation;
@end
@implementation H120TestController
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
 (void)animated;self.lastPresentation=controller;if(completion)completion();
}
@end
@interface H120TestDiagnostic : H120RecordingDiagnosticController
@property(nonatomic,strong) UIViewController *lastPresentation;
- (void)setRecording:(H120ProbeChannel)recording client:(H120ProbeChannel)client ready:(BOOL)ready;
@end
@implementation H120TestDiagnostic
- (void)setRecording:(H120ProbeChannel)recording client:(H120ProbeChannel)client ready:(BOOL)ready {
 _recordingChannel=recording;_clientChannel=client;self.selfCheck=ready ? @"test self-check\n" : nil;[self refreshDiagnostic];
}
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
 (void)animated;self.lastPresentation=controller;if(completion)completion();
}
@end
static void H120TestDiagnosticExport(void) {
 NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
 assert([NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:NO attributes:nil error:nil]);
 NSString *target=[directory stringByAppendingPathComponent:@"target"], *alias=[directory stringByAppendingPathComponent:@"alias"];
 assert([@"fixture" writeToFile:target atomically:YES encoding:NSUTF8StringEncoding error:nil]);
 assert(symlink("target",alias.fileSystemRepresentation)==0);
 NSString *check=H120FileCheck(alias);
 assert([check containsString:@"final-component symlink -> target"]);
 assert([check containsString:@"follow-open errno=0"]); // O_NOFOLLOW ELOOP is NOT a cycle
 NSString *loop=[directory stringByAppendingPathComponent:@"loop"];
 assert(symlink("loop",loop.fileSystemRepresentation)==0);
 assert(([H120FileCheck(loop) containsString:[NSString stringWithFormat:@"follow-open errno=%d",ELOOP]]));
 [NSFileManager.defaultManager removeItemAtPath:directory error:nil];
 H120TestDiagnostic *page=[H120TestDiagnostic new];[page loadViewIfNeeded];
 H120ProbeChannel recording=H120ProbeBegin(100,1.5), client=H120ProbeBegin(100,1.5);
 [page setRecording:recording client:client ready:YES];
 assert(!page.navigationItem.rightBarButtonItem.enabled);
 assert([page.report containsString:@"status=pending"]);[page exportDiagnostic];
 assert([page.lastPresentation isKindOfClass:UIAlertController.class]);
 uint64_t state=((uint64_t)H120_DIAGNOSTIC_VERSION<<48)|((uint64_t)42<<24);
 assert(H120ProbeFinish(&recording,state,0,101));
 [page setRecording:recording client:client ready:YES];
 assert(!page.navigationItem.rightBarButtonItem.enabled);
 assert([page.report containsString:@"PID=42 hooks=0"]); // reply != installed hooks
 assert([page.report containsString:@"channel=SpringBoard client status=pending"]);
 assert(H120ProbeExpire(&client,102));[page setRecording:recording client:client ready:YES];
 assert(page.navigationItem.rightBarButtonItem.enabled);
 assert([page.report containsString:@"status=timeout"]);
 assert([page.report containsString:@"version=unknown PID=unknown hooks=unknown"]);
 assert([page.output.text isEqual:page.report]);
 assert([page.report containsString:@"exportStatus=final"]);
 NSString *completed=[page.report copy];[page exportDiagnostic];
 assert([page.lastPresentation isKindOfClass:UIActivityViewController.class]);
 // Inspect the actual export file emitted by production exportDiagnostic, not a model string.
 BOOL found=NO;
 for(NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:NSTemporaryDirectory() error:nil]) {
  if(![name hasPrefix:@"Hello120Hz-diagnostic-"]||![name hasSuffix:@".txt"])continue;
  NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:name];
  if([[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] isEqual:completed]) {
   found=YES;[NSFileManager.defaultManager removeItemAtPath:path error:nil];
  }
 }
 assert(found);
 recording=H120ProbeBegin(100,1.5);assert(H120ProbeFinish(&recording,0,7,100.1));
 [page setRecording:recording client:client ready:YES];
 assert(page.navigationItem.rightBarButtonItem.enabled);
 assert([page.report containsString:@"status=transport-failure"]);
 assert([page.report containsString:@"transport=7 rawState=0000000000000000"]);
 [page setRecording:recording client:client ready:NO];assert(!page.navigationItem.rightBarButtonItem.enabled);
 NSLog(@"Production diagnostic UI/export pending/completed/timeout/failure/no-false-hooks PASS");
}
int main(void) { @autoreleasepool {
 H120TestDiagnosticExport();
 NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:@"hello120hz-test-root"];
 [NSFileManager.defaultManager removeItemAtPath:root error:nil];
 assert(H120ReadPreferences().count==0);
 assert(![H120ReadPreferences()[@"wantsEnable"] boolValue]);
 assert(H120ReplacePreferences(@{@"wantsEnable":@NO,@"wantsFPS":@120,@"selectedApps":@[]}));
 H120TestController *ui=[H120TestController new];[ui loadViewIfNeeded];
 assert(ui.coordinator.sections.count==2);
 assert(ui.coordinator.sections[0].count==3);
 assert(![ui.coordinator.sections[0][2][@"h120Toggle"] boolValue]);
 ui.coordinator.recordingToggleChanged(YES);
 assert([H120ReadPreferences()[@"recordingEnabled"] boolValue]);
 assert(![H120ReadPreferences()[@"wantsEnable"] boolValue]);
 assert(![ui.coordinator.sections[0][0][@"h120Toggle"] boolValue]);
 ui.coordinator.toggleChanged(YES);
 assert([H120ReadPreferences()[@"wantsEnable"] boolValue]);
 H120FrameRateController *rate=[H120FrameRateController new];[rate loadViewIfNeeded];
 assert(rate.coordinator.sections[0].count==5);
 for(NSString *value in @[@"10",@"30",@"60",@"80",@"120"]) {
  rate.coordinator.selection(value);assert([H120ReadPreferences()[@"wantsFPS"] integerValue]==value.integerValue);
 }
 assert(H120SetGlobalInjection(YES));assert(H120GlobalInjectionEnabled());
 [ui reloadValues];assert([ui.coordinator.sections[1][0][@"identifier"] isEqual:@"excluded"]);
 assert([ui.coordinator.sections[1][1][@"identifier"] isEqual:@"system"]);
 assert([ui.coordinator.sections[1][2][@"identifier"] isEqual:@"hud"]);
 Class list=H120ApplicationListClass();assert(list && [list isSubclassOfClass:ATLApplicationListMultiSelectionController.class]);
 id picker=[list new];PSSpecifier *s=[PSSpecifier new];s.testProperties=[@{@"key":@"selectedApps",@"default":@[]} mutableCopy];
 H120WriteSpecifier(picker,@selector(setPreferenceValue:specifier:),@[@"com.example.game"],s);
 assert([H120ReadSpecifier(picker,@selector(readPreferenceValue:),s) isEqual:@[@"com.example.game"]]);
 [ui selectIdentifier:@"system"];assert(!H120GlobalInjectionEnabled());
 NSDictionary *filter=[NSDictionary dictionaryWithContentsOfFile:H120FilterPath()];
 assert([filter[@"Filter"][@"Executables"] isEqual:@[@"SpringBoard",@"backboardd",@"replayd"]]);
 [ui reset];NSDictionary *p=H120ReadPreferences();assert(![p[@"wantsEnable"] boolValue]);assert([p[@"wantsFPS"] intValue]==120);assert([p[@"selectedApps"] count]==0);assert(![p[@"recordingEnabled"] boolValue]);
 [ui selectIdentifier:@"applyRecording"];
 assert([ui.lastPresentation isKindOfClass:UIAlertController.class]);
 assert([[(UIAlertController *)ui.lastPresentation message] containsString:@"replayd"]);
 assert([(UIAlertController *)ui.lastPresentation actions].count==1); // instructions, never a fake restart action
 assert(H120_DIAGNOSTIC_VERSION==50906u);
 assert([H120RecordingSelfCheck() containsString:@"5.09+full6"]);
 assert(![H120RecordingSelfCheck() containsString:@"0hello120hzRecording"]);
 [ui respring];assert([ui.lastPresentation isKindOfClass:UIAlertController.class]);
 assert([(UIAlertController *)ui.lastPresentation actions].count==2);
 // Intentionally never invoke a destructive action or HUD/recording API.
 [NSFileManager.defaultManager removeItemAtPath:root error:nil];
 NSLog(@"Hello original UI: sections/rates/toggle/reset/AltList callbacks/filter/confirmed respring PASS");
}return 0;}
