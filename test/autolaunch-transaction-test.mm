// macOS-only: real Foundation persistence and Darwin flock, across threads and processes.
#import "../shared/TLinkAutoLaunchConfig.h"
#import <dispatch/dispatch.h>
#include <cassert>
#include <cstdio>
#include <sys/stat.h>

static id readPlist(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    assert(data);
    return [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
}
static void writer(NSString *path, NSString *prefix) {
    for (int i = 0; i < 100; ++i) { @autoreleasepool {
        NSString *name = [NSString stringWithFormat:@"%@-%d", prefix, i];
        NSError *error = nil;
        assert(TLinkAutoLaunchSetEntry(path, name, @{@"script": name, @"enabled": @YES}, &error) && !error);
    } }
}
int main(int argc, const char *argv[]) { @autoreleasepool {
    assert(argc >= 2);
    NSString *root = [NSString stringWithUTF8String:argv[1]];
    NSString *path = [root stringByAppendingPathComponent:@"autolaunch-test.plist"];
    if (argc == 4) { writer(path, [NSString stringWithUTF8String:argv[3]]); return 0; }
    NSError *error = nil;
    assert(TLinkAutoLaunchSetEntry(path, @"legacy", @{@"script": @"old", @"enabled": @NO, @"unknown": @42}, &error));
    NSMutableArray<NSTask *> *children = [NSMutableArray array];
    NSString *executable = [NSString stringWithUTF8String:argv[0]];
    for (int i = 0; i < 8; ++i) {
        NSTask *child = [[NSTask alloc] init];
        child.executableURL = [NSURL fileURLWithPath:executable];
        child.arguments = @[root, @"child", [NSString stringWithFormat:@"process%d", i]];
        assert([child launchAndReturnError:&error] && !error);
        [children addObject:child];
    }
    dispatch_apply(8, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t i) {
        @autoreleasepool { writer(path, [NSString stringWithFormat:@"thread%zu", i]); }
    });
    for (NSTask *child in children) { [child waitUntilExit]; assert(child.terminationStatus == 0); }
    NSDictionary *config = readPlist(path);
    assert(config.count == 1601 && [config[@"legacy"][@"unknown"] isEqual:@42]);
    for (int client = 0; client < 8; ++client) for (int i = 0; i < 100; ++i) {
        for (NSString *prefix in @[@"process", @"thread"]) {
            NSString *name = [NSString stringWithFormat:@"%@%d-%d", prefix, client, i];
            assert([config[name][@"script"] isEqualToString:name]);
        }
    }
    // Malformed existing data is preserved rather than being silently reset.
    NSString *badPath = [root stringByAppendingPathComponent:@"malformed.plist"];
    NSData *bad = [@"broken" dataUsingEncoding:NSUTF8StringEncoding];
    assert([bad writeToFile:badPath atomically:YES]);
    assert(!TLinkAutoLaunchSetEntry(badPath, @"x", @{}, &error) && error);
    assert([[NSData dataWithContentsOfFile:badPath] isEqualToData:bad]);
    NSData *arrayData = [NSPropertyListSerialization dataWithPropertyList:@[] format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
    assert([arrayData writeToFile:badPath options:NSDataWritingAtomic error:NULL]);
    assert(!TLinkAutoLaunchSetEntry(badPath, @"x", @{}, NULL));
    assert([readPlist(badPath) isEqual:@[]]);
    assert(!TLinkAutoLaunchSetEntry(path, @"", @{}, &error) && error);

    // Failed lock acquisition cannot ACK a write. A subsequent valid call can recover.
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *lockedPath = [root stringByAppendingPathComponent:@"lock-failure.plist"];
    NSString *lockPath = [lockedPath stringByAppendingString:@".lock"];
    assert([fm createSymbolicLinkAtPath:lockPath withDestinationPath:[root stringByAppendingPathComponent:@"absent-parent/file"] error:NULL]);
    assert(!TLinkAutoLaunchSetEntry(lockedPath, @"x", @{}, &error) && error);
    assert(![fm fileExistsAtPath:lockedPath]);
    assert([fm removeItemAtPath:lockPath error:NULL]);
    assert(TLinkAutoLaunchSetEntry(lockedPath, @"x", @{}, &error) && !error);

    // Deny atomic replacement after the lock file already exists, then verify recovery.
    if (geteuid() != 0) {
        NSString *directory = [root stringByAppendingPathComponent:@"read-only"];
        NSString *readOnlyPath = [directory stringByAppendingPathComponent:@"config.plist"];
        assert(TLinkAutoLaunchSetEntry(readOnlyPath, @"old", @{}, &error));
        assert(chmod(directory.fileSystemRepresentation, 0555) == 0);
        BOOL saved = TLinkAutoLaunchSetEntry(readOnlyPath, @"new", @{}, &error);
        assert(chmod(directory.fileSystemRepresentation, 0755) == 0);
        assert(!saved && error && ((NSDictionary *)readPlist(readOnlyPath)).count == 1);
        assert(TLinkAutoLaunchSetEntry(readOnlyPath, @"new", @{}, &error) && !error);
    }
    std::puts("Auto-launch transactions passed: 8 processes + 8 threads, 1,600 acknowledged updates preserved; malformed/lock/write failures and recovery.");
} }
