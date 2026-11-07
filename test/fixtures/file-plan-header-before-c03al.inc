#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>

NS_ASSUME_NONNULL_BEGIN

@interface TLinkJSFileHandle : NSObject

@property(nonatomic, readonly) NSUInteger handleId;
@property(nonatomic, copy, readonly) NSString *path;
@property(nonatomic, copy, readonly) NSString *mode;
@property(nonatomic, readonly, getter=isClosed) BOOL closed;

+ (nullable instancetype)openPath:(NSString *)path
                             mode:(NSString *)mode
                         handleId:(NSUInteger)handleId
                 maxTransferBytes:(NSUInteger)maxTransferBytes
                            error:(NSString * _Nullable * _Nullable)error;

- (NSDictionary *)readRequest:(nullable id)request;
- (NSDictionary *)readLine;
- (NSDictionary *)writeText:(NSString *)text;
- (NSDictionary *)writeBase64:(NSString *)base64;
- (NSDictionary *)seekWhence:(NSString *)whence offset:(long long)offset;
- (NSDictionary *)tell;
- (NSDictionary *)flush;
- (NSDictionary *)close;

@end

FOUNDATION_EXPORT BOOL TLinkJSFileModeIsValid(NSString *mode);
FOUNDATION_EXPORT BOOL TLinkJSFileModeWrites(NSString *mode);
FOUNDATION_EXPORT JSValue *TLinkJSFileHandleCreateJSObject(
    JSContext *context,
    TLinkJSFileHandle *handle,
    void (^ _Nullable didClose)(NSUInteger handleId));

NS_ASSUME_NONNULL_END
