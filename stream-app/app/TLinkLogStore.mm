#import "TLinkLogStore.h"

NSNotificationName const TLinkLogStoreDidAppendNotification = @"TLinkLogStoreDidAppendNotification";

@interface TLinkLogStore ()
@property (nonatomic, strong) NSMutableArray<NSString *> *lines;
@end

@implementation TLinkLogStore

+ (TLinkLogStore *)sharedStore
{
    static TLinkLogStore *store = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [[TLinkLogStore alloc] init];
    });
    return store;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _lines = [NSMutableArray array];
        _maximumLineCount = 500;
    }
    return self;
}

- (void)appendLine:(NSString *)line
{
    if (line.length == 0) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                             dateStyle:NSDateFormatterNoStyle
                                                             timeStyle:NSDateFormatterMediumStyle];
        [self.lines addObject:[NSString stringWithFormat:@"[%@] %@", timestamp, line]];
        if (self.maximumLineCount > 0 && self.lines.count > self.maximumLineCount) {
            NSRange overflow = NSMakeRange(0, self.lines.count - self.maximumLineCount);
            [self.lines removeObjectsInRange:overflow];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:TLinkLogStoreDidAppendNotification
                                                            object:self];
    });
}

- (NSArray<NSString *> *)allLines
{
    __block NSArray<NSString *> *snapshot = nil;
    if ([NSThread isMainThread]) {
        snapshot = [self.lines copy];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            snapshot = [self.lines copy];
        });
    }
    return snapshot ?: @[];
}

- (NSArray<NSString *> *)recentLines:(NSUInteger)count
{
    NSArray<NSString *> *all = [self allLines];
    if (count == 0 || all.count <= count) return all;
    return [all subarrayWithRange:NSMakeRange(all.count - count, count)];
}

- (void)clear
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.lines removeAllObjects];
        [[NSNotificationCenter defaultCenter] postNotificationName:TLinkLogStoreDidAppendNotification
                                                            object:self];
    });
}

@end
