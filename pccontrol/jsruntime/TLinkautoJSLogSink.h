#ifndef TLINKAUTO_JS_LOG_SINK_H
#define TLINKAUTO_JS_LOG_SINK_H

#import <Foundation/Foundation.h>

@protocol TLinkautoJSLogSink <NSObject>
- (void)logWithLevel:(NSString *)level message:(NSString *)message;
- (void)close;
@end

@interface TLinkautoJSFileLogSink : NSObject <TLinkautoJSLogSink>
- (instancetype)initWithRunId:(NSString *)runId bundlePath:(NSString *)bundlePath;
@property (nonatomic, readonly) NSString *currentLogPath;
@property (nonatomic, readonly) NSString *latestLogPath;
@end

#endif /* TLINKAUTO_JS_LOG_SINK_H */
