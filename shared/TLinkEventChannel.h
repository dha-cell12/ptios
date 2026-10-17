#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const TLinkEventChannelSchemaV1;
FOUNDATION_EXPORT NSString * const TLinkEventSchemaV1;

FOUNDATION_EXPORT NSString *TLinkEventChannelRootPath(void);
FOUNDATION_EXPORT NSDictionary *TLinkEventChannelPublish(NSString *runtime,
                                                         NSString *topic,
                                                         NSString *type,
                                                         NSDictionary *_Nullable payload);
FOUNDATION_EXPORT NSDictionary *TLinkEventChannelPoll(uint64_t cursor,
                                                      NSArray<NSString *> *_Nullable topics,
                                                      NSUInteger timeoutMs,
                                                      NSUInteger maxEvents);
FOUNDATION_EXPORT NSDictionary *TLinkEventChannelPollBody(NSString *_Nullable body,
                                                          NSString *_Nullable *_Nullable error);
// Cancel is thread-safe and immediately returns admission. A racing completion must recheck cancelled before delivery.
@interface TLinkEventPollRequest : NSObject
- (void)cancel;
@property(nonatomic, readonly, getter=isCancelled) BOOL cancelled;
@end
typedef NSString *_Nullable (^TLinkEventPollAuthorization)(void);
typedef void (^TLinkEventPollCompletion)(TLinkEventPollRequest *request, NSDictionary *_Nullable batch, NSString *_Nullable error);
// Completion is asynchronous on the event owner queue. Never synchronously wait from that queue.
FOUNDATION_EXPORT TLinkEventPollRequest *TLinkEventChannelBeginPoll(NSString *_Nullable body,
    TLinkEventPollAuthorization _Nullable authorization, TLinkEventPollCompletion completion);
FOUNDATION_EXPORT NSDictionary *TLinkEventChannelStatus(void);

NS_ASSUME_NONNULL_END
