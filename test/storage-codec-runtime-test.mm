#import <Foundation/Foundation.h>
#import "../pccontrol/jsruntime/TLinkJSNativeResponse.mm"
#include <cassert>
#include <cstdio>
#include <cstdint>
#include <initializer_list>
#include <stdexcept>
static NSString * const TLinkJSNativeMethodWriteText=@"writeText";
static const unsigned long long kTLinkautoJSMaxStorageFileBytes=512*1024;
static const unsigned long long kTLinkJSHelperMaxStorageFileBytes=512*1024;
@interface StorageRuntime : NSObject
@property(nonatomic,copy) NSString *path;
@property(nonatomic) unsigned policy;
@property(nonatomic) NSUInteger storageOpsCount;
@property(nonatomic,strong) NSMutableArray *trace;
- (NSDictionary *)bundleStoragePathForRelativePath:(NSString *)path createParent:(BOOL)create;
- (NSDictionary *)bundleStoragePathForRelativePath:(NSString *)path bundlePath:(NSString *)bundle writing:(BOOL)writing createParent:(BOOL)create;
@end
@implementation StorageRuntime
- (NSDictionary *)bundleStoragePathForRelativePath:(NSString *)path createParent:(BOOL)create {
    [self.trace addObject:@{@"relative":path?:@"",@"create":@(create)}];
    if(self.policy==1)return @{@"ok":@NO,@"error":@"controlled_path_denial",@"path":path?:@""};
    if(self.policy==2)return @{@"ok":@YES};
    return @{@"ok":@YES,@"path":self.path};
}
- (NSDictionary *)bundleStoragePathForRelativePath:(NSString *)path bundlePath:(NSString *)bundle writing:(BOOL)writing createParent:(BOOL)create {
    [self.trace addObject:@{@"bundle":bundle?:@"",@"writing":@(writing)}];
    return [self bundleStoragePathForRelativePath:path createParent:create];
}
@end
@interface StorageHelper : StorageRuntime
- (NSDictionary *)writeText:(NSString *)text atRelativePath:(NSString *)relativePath bundlePath:(NSString *)bundlePath;
@end
@implementation StorageHelper
#include "StorageHelperWriteTextUnderTest.inc"
@end
@interface StorageLegacyHelper : StorageRuntime
- (NSDictionary *)writeText:(NSString *)text atRelativePath:(NSString *)relativePath bundlePath:(NSString *)bundlePath;
@end
@implementation StorageLegacyHelper
#include "fixtures/storage-helper-write-text-legacy-v1.inc"
@end
static TLinkJSNativeResponse *storageRootWrite(NSArray *args,StorageRuntime *runtime){
    NSString *method=TLinkJSNativeMethodWriteText;
    if(NO){}
#include "StorageWriteTextUnderTest.inc"
    return nil;
}
static TLinkJSNativeResponse *storageLegacyRootWrite(NSArray *args,StorageRuntime *runtime){
    NSString *method=TLinkJSNativeMethodWriteText;
    if(NO){}
#include "fixtures/storage-write-text-legacy-v1.inc"
    return nil;
}
static NSString *TLinkScriptStoragePath(StorageRuntime *session,NSString *relativePath,BOOL writing,NSString **error){
    assert(writing);NSDictionary *resolved=[session bundleStoragePathForRelativePath:relativePath createParent:YES];
    if(![resolved[@"ok"] boolValue]){*error=resolved[@"error"];return nil;}return resolved[@"path"];
}
static NSDictionary *storageTrollWrite(BOOL legacy,StorageRuntime *runtime,NSString *relativePath,NSString *text){
    __weak StorageRuntime *weakSession=runtime;NSMutableDictionary *device=[NSMutableDictionary dictionary];
    if(legacy){
#include "fixtures/storage-trollstore-write-text-legacy-v1.inc"
    }else{
#include "StorageTrollWriteTextUnderTest.inc"
    }
    NSDictionary *(^writer)(NSString *,NSString *)=device[@"writeText"];return writer(relativePath,text);
}
// Count only the bridge's explicit conversion/size/write calls. Real Foundation
// encoding and file IO run on the backing NSString and are not counted as ours.
@interface StorageCountedString : NSString {
@public NSString *backing;NSUInteger dataCalls,sizeCalls,writeCalls;unsigned fault;
}
- (instancetype)initWithBacking:(NSString *)text;
@end
@implementation StorageCountedString
- (instancetype)initWithBacking:(NSString *)text {self=[super init];if(self)backing=[text copy];return self;}
- (NSUInteger)length {return backing.length;}
- (unichar)characterAtIndex:(NSUInteger)index {return [backing characterAtIndex:index];}
- (void)getCharacters:(unichar *)buffer range:(NSRange)range {[backing getCharacters:buffer range:range];}
- (NSData *)dataUsingEncoding:(NSStringEncoding)encoding {++dataCalls;return [backing dataUsingEncoding:encoding];}
- (NSUInteger)lengthOfBytesUsingEncoding:(NSStringEncoding)encoding {++sizeCalls;return [backing lengthOfBytesUsingEncoding:encoding];}
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomic encoding:(NSStringEncoding)encoding error:(NSError **)error {
    ++writeCalls;
    if(fault==1){if(error)*error=[NSError errorWithDomain:@"StorageFixture" code:7 userInfo:nil];return NO;}
    if(fault==2)return NO;
    if(fault==3)[NSException raise:@"StorageFixture" format:@"write failed"];
    if(fault==4)throw std::runtime_error("write failed");
    return [backing writeToFile:path atomically:atomic encoding:encoding error:error];
}
@end
static NSDictionary *storageRun(unsigned backend,BOOL legacy,NSString *root,id text,unsigned policy=0,BOOL missing=NO){
    NSString *file=[root stringByAppendingPathComponent:@"storage.txt"];
    assert([@"sentinel" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    StorageRuntime *runtime=nil;
    if(backend==1){if(legacy)runtime=[StorageLegacyHelper new];else runtime=[StorageHelper new];}
    else runtime=[StorageRuntime new];
    runtime.path=policy==3?root:file;runtime.policy=policy;runtime.trace=[NSMutableArray array];
    NSDictionary *value=nil;NSString *exception=@"";BOOL outerOK=YES;id errorCode=[NSNull null],errorMessage=[NSNull null];
    @try{try{
        if(backend==0){
            NSArray *args=missing?@[]:@[@"relative/ảnh;测试.txt",text?:@""];
            TLinkJSNativeResponse *response=legacy?storageLegacyRootWrite(args,runtime):storageRootWrite(args,runtime);
            assert(response);outerOK=response.ok;value=response.value;
            if(response.errorCode)errorCode=response.errorCode;if(response.errorMessage)errorMessage=response.errorMessage;
        }else if(backend==1){
            if(legacy)value=[(StorageLegacyHelper *)runtime writeText:(missing?nil:text) atRelativePath:@"relative/ảnh;测试.txt" bundlePath:@"controlled-bundle"];
            else value=[(StorageHelper *)runtime writeText:(missing?nil:text) atRelativePath:@"relative/ảnh;测试.txt" bundlePath:@"controlled-bundle"];
        }else value=storageTrollWrite(legacy,runtime,@"relative/ảnh;测试.txt",missing?nil:text);
    }catch(const std::runtime_error &){exception=@"cpp";}}
    @catch(NSException *caught){exception=caught.name;}
    NSData *contents=[NSData dataWithContentsOfFile:file];assert(contents);
    return @{@"outer_ok":@(outerOK),@"value":value?:@{},@"code":errorCode,@"message":errorMessage,@"exception":exception,@"contents":contents,@"trace":[runtime.trace copy],@"storage_ops":@(runtime.storageOpsCount)};
}
static void storageParity(unsigned backend,NSString *root,id text,unsigned policy=0,BOOL missing=NO){
    NSDictionary *expected=storageRun(backend,YES,root,text,policy,missing),*actual=storageRun(backend,NO,root,text,policy,missing);
    if(![expected isEqual:actual])fprintf(stderr,"Storage parity failed: backend=%u policy=%u expected=%s actual=%s\n",backend,policy,expected.description.UTF8String,actual.description.UTF8String);
    assert([expected isEqual:actual]);
}
int main(int argc,char **argv){@autoreleasepool{
    assert(argc==2);NSString *root=[NSString stringWithUTF8String:argv[1]];
    fputs("Storage writeText Foundation: extracted production root/helper/TrollStore writers, real UTF8 IO and frozen replies\n",stderr);
    const unichar unpaired[]={0xd800,0xdc00,0xdfff};
    NSMutableArray *corpus=[NSMutableArray arrayWithArray:@[@"",@"ascii",@"ảnh 测试 😀",@"\ufeff\ufeff{}",@"a\0b",@42,[NSNull null],@{@"value":@"description"}]];
    for(unsigned n=0;n<3;++n)[corpus addObject:[NSString stringWithCharacters:unpaired+n length:1]];
    NSMutableString *invalidLong=[[@"x" stringByPaddingToLength:524289 withString:@"x" startingAtIndex:0] mutableCopy];
    [invalidLong appendString:[NSString stringWithCharacters:unpaired length:1]];[corpus addObject:invalidLong];
    for(NSUInteger length:{(NSUInteger)524287,(NSUInteger)524288,(NSUInteger)524289}){
        [corpus addObject:[@"x" stringByPaddingToLength:length withString:@"x" startingAtIndex:0]];
        [corpus addObject:[@"é" stringByPaddingToLength:length/2+1 withString:@"é" startingAtIndex:0]];
    }
    for(unsigned backend=0;backend<3;++backend){
        for(id text in corpus){@autoreleasepool{storageParity(backend,root,text);}}
        storageParity(backend,root,nil,0,YES);
        for(unsigned policy=1;policy<=3;++policy)storageParity(backend,root,@"text",policy);
        for(unsigned fault=0;fault<=4;++fault){
            StorageCountedString *text=[[StorageCountedString alloc] initWithBacking:@"ảnh;测试\n"];text->fault=fault;
            const NSUInteger counted=backend==2&&fault>=3?0:1;
            NSDictionary *expected=storageRun(backend,YES,root,text);assert(text->dataCalls==counted&&text->sizeCalls==0&&text->writeCalls==1);
            text->dataCalls=text->sizeCalls=text->writeCalls=0;
            NSDictionary *actual=storageRun(backend,NO,root,text);assert([expected isEqual:actual]);
            // TrollStore retains its original post-write count: a throwing write
            // has no subsequent size conversion in either implementation.
            assert(text->dataCalls==0&&text->sizeCalls==counted&&text->writeCalls==1);
        }
    }
    uint32_t seed=0x5a17;
    for(unsigned n=0;n<1000;++n){@autoreleasepool{
        unichar units[256];seed=seed*1664525U+1013904223U;const NSUInteger length=seed%256;
        for(NSUInteger i=0;i<length;++i){seed=seed*1664525U+1013904223U;units[i]=(unichar)(seed>>16);}
        NSString *text=[[NSString alloc] initWithCharacters:units length:length];NSData *encoded=[text dataUsingEncoding:NSUTF8StringEncoding];
        assert([text lengthOfBytesUsingEncoding:NSUTF8StringEncoding]==encoded.length);
    }}
    puts("Storage writeText passed: frozen root/helper/TrollStore replies, 1000 UTF16 size equivalences, Unicode/NUL/BOM/unpaired-surrogate and exact 512-KiB boundaries, description/default/path/error ordering, unchanged real atomic writer, NS/C++ write faults and no explicit counting NSData. Foundation internal allocations and device performance remain unqualified.");
}}
