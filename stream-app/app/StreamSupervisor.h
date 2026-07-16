#import <Foundation/Foundation.h>

// ---------------------------------------------------------------------------
// SCStreamSupervisor
//
// Ensures and watchdogs the bundled `streamd` binary. Foreground app launches
// can use a direct child process, while service mode asks the TrollStore root
// helper to keep a detached streamd process alive outside the app UI lifecycle.
//
// streamd is bundled at StreamControl.app/streamd and spawned by relative path.
// Core automation stays in streamd; the helper only starts/stops/replaces it.
// ---------------------------------------------------------------------------

@protocol SCStreamSupervisorDelegate <NSObject>
@optional
- (void)supervisorDidLog:(NSString *)line;
- (void)supervisorDidChangeRunning:(BOOL)running pid:(pid_t)pid;
@end

@interface SCStreamSupervisor : NSObject

@property (nonatomic, weak) id<SCStreamSupervisorDelegate> delegate;
@property (nonatomic, readonly) BOOL running;
@property (nonatomic, readonly) pid_t childPid;

// Enable/disable automatic respawn on unexpected child exit.
@property (nonatomic, assign) BOOL autoRespawn;

// Absolute path to the streamd binary inside the app bundle.
- (NSString *)streamdPath;

// Ensure streamd is listening on tcp/6000. No-op if it already responds.
- (void)start;

// Explicit service-mode ensure used by app lifecycle hooks.
- (void)ensureService;

// Ensure service and report only after tcp/6000 has been probed. The callback
// is delivered on the main queue and is suitable for BGTask completion.
- (void)ensureServiceWithCompletion:(void (^)(BOOL running, NSString *detail))completion;

// Terminate streamd and disable respawn for this stop.
- (void)stop;

// Forcefully replace any running/stale streamd with the bundled binary.
- (void)restart;

@end
