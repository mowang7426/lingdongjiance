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
int main(void) { @autoreleasepool {
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
 assert([filter[@"Filter"][@"Executables"] isEqual:@[@"SpringBoard"]]);
 [ui reset];NSDictionary *p=H120ReadPreferences();assert(![p[@"wantsEnable"] boolValue]);assert([p[@"wantsFPS"] intValue]==120);assert([p[@"selectedApps"] count]==0);assert(![p[@"recordingEnabled"] boolValue]);
 [ui respring];assert([ui.lastPresentation isKindOfClass:UIAlertController.class]);
 assert([(UIAlertController *)ui.lastPresentation actions].count==2);
 // Intentionally never invoke a destructive action or HUD/recording API.
 [NSFileManager.defaultManager removeItemAtPath:root error:nil];
 NSLog(@"Hello original UI: sections/rates/toggle/reset/AltList callbacks/filter/confirmed respring PASS");
}return 0;}
