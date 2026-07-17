#import <Foundation/Foundation.h>

@class SCStreamSupervisor;
@class SCLicenseLifecycleCoordinator;

// Best-effort iOS background recovery for the detached streamd service.
// This does not provide launchd-style boot startup; iOS controls when tasks run.
@interface SCBackgroundServiceScheduler : NSObject

@property(nonatomic, readonly) NSString *diagnosticsPath;

- (instancetype)initWithSupervisor:(SCStreamSupervisor *)supervisor
                 licenseCoordinator:(SCLicenseLifecycleCoordinator *)licenseCoordinator;
- (void)registerTasks;
- (void)scheduleRecoveryTasksForReason:(NSString *)reason;

@end
