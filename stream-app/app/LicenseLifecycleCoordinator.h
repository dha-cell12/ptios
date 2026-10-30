#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *const SCLicenseLifecycleDidChangeNotification;

typedef void (^SCLicenseLifecycleCompletion)(BOOL success, NSString *message);

// Cancels only this subscriber. A delivery already claimed may finish.
// Shared refresh/HTTP work and other subscribers remain active.
@protocol SCLicenseRefreshSubscription <NSObject>
- (void)cancel;
@end

@interface SCLicenseLifecycleCoordinator : NSObject

@property(nonatomic, readonly, getter=isRequestInFlight) BOOL requestInFlight;
@property(nonatomic, readonly) NSString *diagnosticsPath;

+ (instancetype)sharedCoordinator;
- (NSDictionary *)diagnostics;
- (NSDictionary *)cachedLicenseStatus;
- (BOOL)cachedFeatureAllowed:(NSString *)feature reason:(NSString **)reason;
- (void)refreshLicenseUISnapshotAsyncForReason:(NSString *)reason;
- (void)handleApplicationLaunch;
- (void)handleApplicationDidBecomeActive;
- (void)performBackgroundRefreshWithCompletion:(SCLicenseLifecycleCompletion)completion;
- (id<SCLicenseRefreshSubscription>)subscribeToBackgroundRefreshWithCompletion:(SCLicenseLifecycleCompletion)completion;
- (void)activateLicenseKey:(NSString *)licenseKey completion:(SCLicenseLifecycleCompletion)completion;
- (void)activateLicenseKey:(NSString *)licenseKey
                    intent:(NSString *)intent
                completion:(SCLicenseLifecycleCompletion)completion;
- (void)refreshManuallyWithCompletion:(SCLicenseLifecycleCompletion)completion;
- (void)deactivateWithCompletion:(SCLicenseLifecycleCompletion)completion;
- (BOOL)removeLocalLease:(NSError **)error;
- (BOOL)repairDevicePublicKey:(NSError **)error;

@end
