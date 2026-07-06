#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TLinkSocketClient : NSObject

+ (NSString *)sendLineAndRead:(NSString *)line timeout:(NSTimeInterval)timeout;
+ (void)sendLineFireAndForget:(NSString *)line;
+ (NSString *)requestTask:(NSInteger)task args:(NSArray<NSString *> *)args timeout:(NSTimeInterval)timeout;

@end

NS_ASSUME_NONNULL_END
