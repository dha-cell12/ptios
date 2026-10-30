#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import "../pccontrol/jsruntime/TLinkJSNativeRequest.mm"
#import "../pccontrol/jsruntime/TLinkJSNativeResponse.mm"
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <initializer_list>
static unsigned jsonPointerMode=0;
static NSUInteger jsonPointerCalls=0,jsonFallbackCalls=0,jsonOwnerLive=0;
static const char *jsonDirectPointer(CFStringRef string,CFStringEncoding encoding);
// The ordinary case delegates to real CF. Only the lifetime/fallback cases
// inject a controlled pointer, with its bytes actually owned by the NSString.
#define CFStringGetCStringPtr jsonDirectPointer
#include "../shared/TLinkUTF8Data.h"
#undef CFStringGetCStringPtr
@interface JSONOwnerString : NSString {
@public NSString *backing;char *ownedBytes;NSUInteger byteCount;
}
- (instancetype)initWithText:(NSString *)text;
@end
@implementation JSONOwnerString
- (instancetype)initWithText:(NSString *)text {
    self=[super init];if(self){backing=[text copy];NSData *encoded=[backing dataUsingEncoding:NSUTF8StringEncoding];
        byteCount=encoded.length;ownedBytes=(char *)malloc(byteCount+1);assert(ownedBytes);
        memcpy(ownedBytes,encoded.bytes,byteCount);ownedBytes[byteCount]=0;++jsonOwnerLive;
    }return self;
}
- (NSUInteger)length {return backing.length;}
- (unichar)characterAtIndex:(NSUInteger)index {return [backing characterAtIndex:index];}
- (void)getCharacters:(unichar *)buffer range:(NSRange)range {[backing getCharacters:buffer range:range];}
- (id)copyWithZone:(NSZone *)zone {(void)zone;return self;}
- (NSUInteger)lengthOfBytesUsingEncoding:(NSStringEncoding)encoding {return [backing lengthOfBytesUsingEncoding:encoding];}
- (NSData *)dataUsingEncoding:(NSStringEncoding)encoding {++jsonFallbackCalls;return [backing dataUsingEncoding:encoding];}
- (void)dealloc {assert(jsonOwnerLive>0);--jsonOwnerLive;free(ownedBytes);}
@end
static const char *jsonDirectPointer(CFStringRef string,CFStringEncoding encoding){
    ++jsonPointerCalls;assert(encoding==kCFStringEncodingUTF8);
    if(jsonPointerMode==1)return NULL;
    NSString *object=(__bridge NSString *)string;
    if([object isKindOfClass:[JSONOwnerString class]])return ((JSONOwnerString *)object)->ownedBytes;
    return CFStringGetCStringPtr(string,encoding);
}
@interface JSONRootBase : NSObject
@property(nonatomic,strong) TLinkJSNativeResponse *child;
@property(nonatomic,strong) NSError *childError;
@property(nonatomic,strong) NSMutableArray *trace;
- (TLinkJSNativeResponse *)executeRequest:(TLinkJSNativeRequest *)request context:(id)context error:(NSError **)error;
@end
@implementation JSONRootBase
- (TLinkJSNativeResponse *)executeRequest:(TLinkJSNativeRequest *)request context:(id)context error:(NSError **)error {
    assert([request.method isEqual:TLinkJSNativeMethodReadText]);
    [self.trace addObject:@{@"args":request.arguments,@"context":context,@"metadata":request.metadata?:@{}}];
    if(error)*error=self.childError;return self.child;
}
@end
@interface JSONRoot : JSONRootBase @end
@implementation JSONRoot
- (TLinkJSNativeResponse *)executeRequest:(TLinkJSNativeRequest *)request context:(id)context error:(NSError **)error {
    NSString *method=request.method;NSArray *args=request.arguments;
    if([method isEqual:TLinkJSNativeMethodReadText])return [super executeRequest:request context:context error:error];
#include "StorageReadJSONUnderTest.inc"
    return nil;
}
@end
@interface JSONLegacyRoot : JSONRootBase @end
@implementation JSONLegacyRoot
- (TLinkJSNativeResponse *)executeRequest:(TLinkJSNativeRequest *)request context:(id)context error:(NSError **)error {
    NSString *method=request.method;NSArray *args=request.arguments;
    if([method isEqual:TLinkJSNativeMethodReadText])return [super executeRequest:request context:context error:error];
#include "fixtures/storage-read-json-legacy-v1.inc"
    return nil;
}
@end
@interface JSONHelperBase : NSObject
@property(nonatomic) NSUInteger storageOpsCount;
@property(nonatomic,strong) NSDictionary *child;
@property(nonatomic,strong) NSMutableArray *trace;
- (NSDictionary *)readTextAtRelativePath:(NSString *)relativePath bundlePath:(NSString *)bundlePath;
@end
@implementation JSONHelperBase
- (NSDictionary *)readTextAtRelativePath:(NSString *)relativePath bundlePath:(NSString *)bundlePath {
    ++self.storageOpsCount;[self.trace addObject:@[relativePath,bundlePath]];return self.child;
}
@end
@interface JSONHelper : JSONHelperBase
- (NSDictionary *)readJSONAtRelativePath:(NSString *)relativePath bundlePath:(NSString *)bundlePath;
@end
@implementation JSONHelper
#include "StorageHelperReadJSONUnderTest.inc"
@end
@interface JSONLegacyHelper : JSONHelperBase
- (NSDictionary *)readJSONAtRelativePath:(NSString *)relativePath bundlePath:(NSString *)bundlePath;
@end
@implementation JSONLegacyHelper
#include "fixtures/storage-helper-read-json-legacy-v1.inc"
@end
static NSDictionary *jsonResponse(TLinkJSNativeResponse *response){
    return @{@"ok":@(response.ok),@"value":response.value?:@{},@"code":(id)response.errorCode?:[NSNull null],@"error":(id)response.errorMessage?:[NSNull null]};
}
static void jsonReaderParity(NSDictionary *textResult){
    TLinkJSNativeRequest *request=[[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodReadJSON arguments:@[@"ảnh;测试.json"]];
    NSObject *context=[NSObject new];
    for(BOOL failure:{NO,YES}){
        JSONRootBase *old=[JSONLegacyRoot new],*actual=[JSONRoot new];
        old.child=actual.child=failure?[TLinkJSNativeResponse responseWithError:@"controlled_child_error" code:@-7]:[TLinkJSNativeResponse responseWithValue:textResult];
        old.childError=actual.childError=[NSError errorWithDomain:@"JSONFixture" code:17 userInfo:nil];
        old.trace=[NSMutableArray array];actual.trace=[NSMutableArray array];
        NSError *oldError=nil,*actualError=nil;NSDictionary *expected=jsonResponse([old executeRequest:request context:context error:&oldError]);
        NSDictionary *reply=jsonResponse([actual executeRequest:request context:context error:&actualError]);
        assert([expected isEqual:reply]&&[old.trace isEqual:actual.trace]&&oldError==actualError);
    }
    JSONLegacyHelper *old=[JSONLegacyHelper new];JSONHelper *actual=[JSONHelper new];
    old.child=actual.child=textResult;old.trace=[NSMutableArray array];actual.trace=[NSMutableArray array];
    NSDictionary *expected=[old readJSONAtRelativePath:@"ảnh;测试.json" bundlePath:@"bundle"];
    NSDictionary *reply=[actual readJSONAtRelativePath:@"ảnh;测试.json" bundlePath:@"bundle"];
    assert([expected isEqual:reply]&&[old.trace isEqual:actual.trace]&&old.storageOpsCount==2&&actual.storageOpsCount==2);
}
static void jsonViewCases(){
    NSString *body=[@"{\"text\":\"" stringByAppendingString:[[@"x" stringByPaddingToLength:65536 withString:@"x" startingAtIndex:0] stringByAppendingString:@"\"}"]];
    NSData *held=nil;
    @autoreleasepool{
        JSONOwnerString *owner=[[JSONOwnerString alloc] initWithText:body];
        held=TLinkUTF8DataFromString(owner);assert(held.bytes==owner->ownedBytes&&jsonFallbackCalls==0);
        owner=nil;
    }
    assert(jsonOwnerLive==1&&[held isEqual:[body dataUsingEncoding:NSUTF8StringEncoding]]);
    held=nil;assert(jsonOwnerLive==0);
    @autoreleasepool{
        JSONOwnerString *owner=[[JSONOwnerString alloc] initWithText:body];jsonPointerMode=1;
        held=TLinkUTF8DataFromString(owner);jsonPointerMode=0;assert(jsonFallbackCalls==1);
        owner=nil;
    }
    assert(jsonOwnerLive==0&&[held isEqual:[body dataUsingEncoding:NSUTF8StringEncoding]]);held=nil;
    // Parsed graphs and bytes remain valid after source/view pools are drained.
    @autoreleasepool{
        NSDictionary *parsed=nil;
        @autoreleasepool{JSONOwnerString *owner=[[JSONOwnerString alloc] initWithText:body];NSData *view=TLinkUTF8DataFromString(owner);parsed=[NSJSONSerialization JSONObjectWithData:view options:0 error:nil];}
        assert([parsed[@"text"] length]==65536);parsed=nil;
    }
    assert(jsonOwnerLive==0);
    NSData *snapshot=nil;
    @autoreleasepool{NSMutableString *mutableText=[@"{\"n\":1}" mutableCopy];snapshot=TLinkUTF8DataFromString(mutableText);[mutableText setString:@"{\"n\":2}"];}
    assert([[[NSJSONSerialization JSONObjectWithData:snapshot options:0 error:nil] objectForKey:@"n"] intValue]==1);snapshot=nil;
    assert(TLinkUTF8DataFromString(nil)==nil);
    for(id bad in @[[NSNull null],@42,@[]]){
        NSString *oldException=nil,*newException=nil;
        @try{(void)[bad dataUsingEncoding:NSUTF8StringEncoding];}@catch(NSException *caught){oldException=caught.name;}
        @try{(void)TLinkUTF8DataFromString(bad);}@catch(NSException *caught){newException=caught.name;}
        assert(oldException&&[oldException isEqualToString:newException]);
    }
}
int main(){@autoreleasepool{
    fputs("Storage readJSON Foundation: retained CF byte views, fallback, frozen root/helper parsing and child calls\n",stderr);
    jsonViewCases();
    const unichar invalid=0xd800;
    NSMutableArray *texts=[NSMutableArray arrayWithArray:@[@"",@"{}",@"[]",@"{\"name\":\"ảnh 测试 😀\"}",@"{\"nul\":\"a\\u0000b\"}",@"\ufeff{}",@"\ufeff\ufeff{}",@"{bad}",@"1",@"null",@"{}\0trailing"]];
    [texts addObject:[NSString stringWithCharacters:&invalid length:1]];
    for(NSString *text in texts)for(unsigned mode=0;mode<2;++mode){@autoreleasepool{
        jsonPointerMode=mode;NSData *expected=[text dataUsingEncoding:NSUTF8StringEncoding],*actual=TLinkUTF8DataFromString(text);
        assert((expected==nil&&actual==nil)||[expected isEqual:actual]);
        jsonReaderParity(@{@"ok":@YES,@"path":@"controlled.json",@"text":text});jsonPointerMode=0;
    }}
    jsonReaderParity(@{@"ok":@NO,@"error":@"controlled_read_failed",@"path":@"controlled.json"});
    jsonReaderParity(@{@"ok":@YES,@"path":@"controlled.json"});
    for(unsigned n=0;n<1000;++n){@autoreleasepool{
        NSString *text=[NSString stringWithFormat:@"{\"n\":%u,\"nested\":[true,false,\"x\"]}",n];
        jsonReaderParity(@{@"ok":@YES,@"path":@"controlled.json",@"text":text});
    }}
    assert(jsonOwnerLive==0);
    puts("Storage readJSON passed: borrowed owner survives pools, fallback releases owner, immutable mutable-input snapshots, parsed graph lifetime, 1000 frozen root/helper replies, UTF8/BOM/NUL/invalid UTF16/parser errors, child transport/error/context and helper operation-count parity. CF fast-path availability/device allocation gains remain platform dependent.");
}}
