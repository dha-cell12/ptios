#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *const SCLicenseLifecycleDidChangeNotification;

typedef void (^SCLicenseLifecycleCompletion)(BOOL success, NSString *message);

@interface SCLicenseLifecycleCoordinator : NSObject

@property(nonatomic, readonly, getter=isRequestInFlight) BOOL requestInFlight;
@property(nonatomic, readonly) NSString *diagnosticsPath;

+ (instancetype)sharedCoordinator;
- (NSDictionary *)diagnostics;
- (void)handleApplicationLaunch;
- (void)handleApplicationDidBecomeActive;
- (void)performBackgroundRefreshWithCompletion:(SCLicenseLifecycleCompletion)completion;
- (void)activateLicenseKey:(NSString *)licenseKey completion:(SCLicenseLifecycleCompletion)completion;
- (void)refreshManuallyWithCompletion:(SCLicenseLifecycleCompletion)completion;
- (void)deactivateWithCompletion:(SCLicenseLifecycleCompletion)completion;
- (BOOL)removeLocalLease:(NSError **)error;
- (BOOL)repairDevicePublicKey:(NSError **)error;

@end
