#import <Foundation/Foundation.h>

@interface SCLicenseManager : NSObject

+ (instancetype)sharedManager;
- (NSDictionary *)localStatus;
- (void)activateLicenseKey:(NSString *)licenseKey
                completion:(void (^)(BOOL success, NSString *message))completion;
- (void)refreshLeaseWithCompletion:(void (^)(BOOL success, NSString *message))completion;
- (BOOL)removeLocalLease:(NSError **)error;

@end

