#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Posted on the main queue whenever lines are appended or cleared.
extern NSNotificationName const TLinkLogStoreDidAppendNotification;

// ---------------------------------------------------------------------------
// TLinkLogStore
//
// Shared ring buffer for service/UI log lines. Replaces per-screen
// stringByAppendingString log views (O(n^2) growth) with a capped store that
// screens observe via TLinkLogStoreDidAppendNotification.
// ---------------------------------------------------------------------------
@interface TLinkLogStore : NSObject

@property (class, nonatomic, readonly) TLinkLogStore *sharedStore;

// Maximum number of retained lines (ring buffer). Defaults to 500.
@property (nonatomic, assign) NSUInteger maximumLineCount;

// Appends a line with an [HH:mm:ss] timestamp prefix. Safe from any queue;
// the mutation and notification happen on the main queue.
- (void)appendLine:(NSString *)line;

// Snapshot of retained lines (oldest first).
- (NSArray<NSString *> *)allLines;

// The most recent `count` lines (oldest first).
- (NSArray<NSString *> *)recentLines:(NSUInteger)count;

- (void)clear;

@end

NS_ASSUME_NONNULL_END
