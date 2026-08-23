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
FOUNDATION_EXPORT NSDictionary *TLinkEventChannelStatus(void);

NS_ASSUME_NONNULL_END
