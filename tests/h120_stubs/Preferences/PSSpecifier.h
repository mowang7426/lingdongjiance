#import <UIKit/UIKit.h>
enum { PSLinkListCell = 2 };
@interface PSSpecifier : NSObject
@property(nonatomic,strong) NSMutableDictionary *testProperties;
+ (instancetype)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set get:(SEL)get detail:(Class)detail cell:(NSInteger)cell edit:(Class)edit;
- (id)propertyForKey:(NSString *)key;
- (void)setProperty:(id)value forKey:(NSString *)key;
@end
