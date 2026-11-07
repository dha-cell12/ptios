// Full current/preceding storage routes; real Foundation/UTF8/atomic IO, with
// controlled path/JSON provider entry witnesses and JSValue conversion only.
static const unsigned long long kTLinkautoJSMaxStorageFileBytes=512*1024;
static const unsigned long long kTLinkJSHelperMaxStorageFileBytes=512*1024;
static bool storageOperationOwners=false,storageOperationCheckPreparation=false;
static unsigned storageOperationFault=0;
static void storageOperationWitness(){if(storageOperationOwners)TLinkAXFixtureAutoreleaseOwner();}
@interface StorageOperationJSON : NSObject
+ (BOOL)isValidJSONObject:(id)object;
+ (NSData *)dataWithJSONObject:(id)object options:(NSJSONWritingOptions)options error:(NSError **)error;
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)options error:(NSError **)error;
@end
@implementation StorageOperationJSON
+ (BOOL)isValidJSONObject:(id)object {storageOperationWitness();return [NSJSONSerialization isValidJSONObject:object];}
+ (NSData *)dataWithJSONObject:(id)object options:(NSJSONWritingOptions)options error:(NSError **)error {storageOperationWitness();return [NSJSONSerialization dataWithJSONObject:object options:options error:error];}
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)options error:(NSError **)error {storageOperationWitness();return [NSJSONSerialization JSONObjectWithData:data options:options error:error];}
@end
@interface StorageOperationJSValue : NSObject
@property(nonatomic,strong) id value;
- (id)toObject;
@end
@implementation StorageOperationJSValue
- (id)toObject {storageOperationWitness();return self.value;}
@end
@interface StorageOperationRuntime : NSObject
@property(nonatomic,copy) NSString *path;
@property(nonatomic) NSUInteger storageOpsCount;
@property(nonatomic) unsigned policy;
@property(nonatomic,strong) NSMutableArray *trace;
@property(nonatomic,strong) NSError *childError;
- (NSDictionary *)bundleStoragePathForRelativePath:(NSString *)path createParent:(BOOL)create;
- (NSDictionary *)bundleStoragePathForRelativePath:(NSString *)path bundlePath:(NSString *)bundle writing:(BOOL)writing createParent:(BOOL)create;
@end
@implementation StorageOperationRuntime
- (NSDictionary *)bundleStoragePathForRelativePath:(NSString *)path createParent:(BOOL)create {
    if(storageOperationCheckPreparation)assert(TLinkAXFixtureLiveOwners()==0);
    storageOperationWitness();[self.trace addObject:@{@"relative":path?:@"",@"create":@(create)}];
    if(storageOperationFault==1)[NSException raise:@"StorageOperationFixture" format:@"path"];
    if(storageOperationFault==2)throw std::runtime_error("path");
    if(self.policy==1)return @{@"ok":@NO,@"path":path?:@"",@"error":@"controlled_denial"};
    if(self.policy==2)return @{@"ok":@YES};
    return @{@"ok":@YES,@"path":self.path};
}
- (NSDictionary *)bundleStoragePathForRelativePath:(NSString *)path bundlePath:(NSString *)bundle writing:(BOOL)writing createParent:(BOOL)create {
    [self.trace addObject:@{@"bundle":bundle?:@"",@"writing":@(writing)}];
    return [self bundleStoragePathForRelativePath:path createParent:create];
}
@end
@interface StorageOperationRoot : StorageOperationRuntime
- (TLinkJSNativeResponse *)executeRequest:(TLinkJSNativeRequest *)request context:(id)context error:(NSError **)error;
@end
@implementation StorageOperationRoot
- (TLinkJSNativeResponse *)executeRequest:(TLinkJSNativeRequest *)request context:(id)context error:(NSError **)error {
    StorageOperationRuntime *runtime=self;NSString *method=request.method;NSArray *args=request.arguments;
    if(error&&self.childError)*error=self.childError;
    if(NO){}
#define NSJSONSerialization StorageOperationJSON
#include "StorageOperations-root-ReadText.inc"
#include "StorageOperations-root-WriteText.inc"
#include "StorageOperations-root-ReadJSON.inc"
#include "StorageOperations-root-WriteJSON.inc"
#undef NSJSONSerialization
    return nil;
}
@end
@interface StorageOperationBeforeRoot : StorageOperationRoot @end
@implementation StorageOperationBeforeRoot
- (TLinkJSNativeResponse *)executeRequest:(TLinkJSNativeRequest *)request context:(id)context error:(NSError **)error {
    StorageOperationRuntime *runtime=self;NSString *method=request.method;NSArray *args=request.arguments;
    if(error&&self.childError)*error=self.childError;
    if(NO){}
#define NSJSONSerialization StorageOperationJSON
#include "StorageOperationsBefore-root-ReadText.inc"
#include "StorageOperationsBefore-root-WriteText.inc"
#include "StorageOperationsBefore-root-ReadJSON.inc"
#include "StorageOperationsBefore-root-WriteJSON.inc"
#undef NSJSONSerialization
    return nil;
}
@end
@interface StorageOperationHelper : StorageOperationRuntime
- (NSDictionary *)readTextAtRelativePath:(NSString *)path bundlePath:(NSString *)bundle;
- (NSDictionary *)writeText:(NSString *)text atRelativePath:(NSString *)path bundlePath:(NSString *)bundle;
- (NSDictionary *)readJSONAtRelativePath:(NSString *)path bundlePath:(NSString *)bundle;
- (NSDictionary *)writeJSONValue:(id)value atRelativePath:(NSString *)path bundlePath:(NSString *)bundle;
@end
@implementation StorageOperationHelper
#define NSJSONSerialization StorageOperationJSON
#define JSValue StorageOperationJSValue
#include "StorageOperations-helper-ReadText.inc"
#include "StorageOperations-helper-WriteText.inc"
#include "StorageOperations-helper-ReadJSON.inc"
#include "StorageOperations-helper-WriteJSON.inc"
#undef JSValue
#undef NSJSONSerialization
@end
@interface StorageOperationBeforeHelper : StorageOperationHelper @end
@implementation StorageOperationBeforeHelper
#define NSJSONSerialization StorageOperationJSON
#define JSValue StorageOperationJSValue
#include "StorageOperationsBefore-helper-ReadText.inc"
#include "StorageOperationsBefore-helper-WriteText.inc"
#include "StorageOperationsBefore-helper-ReadJSON.inc"
#include "StorageOperationsBefore-helper-WriteJSON.inc"
#undef JSValue
#undef NSJSONSerialization
@end
static NSString *StorageOperationPath(StorageOperationRuntime *runtime,NSString *path,BOOL writing,NSString **error){
    NSDictionary *resolved=[runtime bundleStoragePathForRelativePath:path createParent:writing];
    if(![resolved[@"ok"] boolValue]){if(error)*error=resolved[@"error"];return nil;}return resolved[@"path"];
}
static NSDictionary *storageOperationTroll(BOOL before,StorageOperationRuntime *runtime,NSString *method,id input){
    __weak StorageOperationRuntime *weakSession=runtime;NSMutableDictionary *device=[NSMutableDictionary dictionary];
#define NSJSONSerialization StorageOperationJSON
#define JSValue StorageOperationJSValue
#define TLinkScriptStoragePath StorageOperationPath
    if(before){
#include "StorageOperationsBefore-troll-ReadText.inc"
#include "StorageOperationsBefore-troll-WriteText.inc"
#include "StorageOperationsBefore-troll-ReadJSON.inc"
#include "StorageOperationsBefore-troll-WriteJSON.inc"
    }else{
#include "StorageOperations-troll-ReadText.inc"
#include "StorageOperations-troll-WriteText.inc"
#include "StorageOperations-troll-ReadJSON.inc"
#include "StorageOperations-troll-WriteJSON.inc"
    }
#undef TLinkScriptStoragePath
#undef JSValue
#undef NSJSONSerialization
    if([method isEqual:@"writeJSON"]){StorageOperationJSValue *value=[StorageOperationJSValue new];value.value=input;NSDictionary *(^call)(NSString *,StorageOperationJSValue *)=device[method];return call(@"ảnh;测试.json",value);}
    if([method isEqual:@"writeText"]){NSDictionary *(^call)(NSString *,NSString *)=device[method];return call(@"ảnh;测试.json",input);}
    NSDictionary *(^call)(NSString *)=device[method];return call(@"ảnh;测试.json");
}
static NSDictionary *storageOperationReply(unsigned backend,BOOL before,StorageOperationRuntime *runtime,NSString *method,id input,NSError **error){
    if(backend==0){
        TLinkJSNativeRequest *request=[[TLinkJSNativeRequest alloc] initWithMethod:method arguments:input?@[@"ảnh;测试.json",input]:@[@"ảnh;测试.json"]];
        return jsonResponse([(StorageOperationRoot *)runtime executeRequest:request context:@"context" error:error]);
    }else if(backend==1){
        StorageOperationHelper *helper=(StorageOperationHelper *)runtime;
        if([method isEqual:@"readText"])return [helper readTextAtRelativePath:@"ảnh;测试.json" bundlePath:@"bundle"];
        else if([method isEqual:@"writeText"])return [helper writeText:input atRelativePath:@"ảnh;测试.json" bundlePath:@"bundle"];
        else if([method isEqual:@"readJSON"])return [helper readJSONAtRelativePath:@"ảnh;测试.json" bundlePath:@"bundle"];
        else return [helper writeJSONValue:input atRelativePath:@"ảnh;测试.json" bundlePath:@"bundle"];
    }else return storageOperationTroll(before,runtime,method,input);
}
static NSDictionary *storageOperationRun(unsigned backend,BOOL before,NSString *path,NSString *method,id input,unsigned policy){
    StorageOperationRuntime *runtime;
    if(backend==0)runtime=before?[StorageOperationBeforeRoot new]:[StorageOperationRoot new];
    else if(backend==1)runtime=before?[StorageOperationBeforeHelper new]:[StorageOperationHelper new];
    else runtime=[StorageOperationRuntime new];
    runtime.path=path;runtime.policy=policy;runtime.trace=[NSMutableArray array];
    runtime.childError=[NSError errorWithDomain:@"StorageOperationChild" code:17 userInfo:nil];
    NSDictionary *reply=nil;NSError *error=nil;
    NSString *exception=@"";
    if(storageOperationFault)reply=storageOperationReply(backend,before,runtime,method,input,&error);
    else {
        @try {try {reply=storageOperationReply(backend,before,runtime,method,input,&error);}catch(const std::runtime_error &){exception=@"cpp";}}
        @catch(NSException *caught){exception=caught.name;}
    }
    if(backend==0&&reply)assert(error==runtime.childError);
    return @{@"reply":reply?:@{},@"trace":[runtime.trace copy],@"ops":@(runtime.storageOpsCount),@"bytes":[NSData dataWithContentsOfFile:path]?:[NSData data],@"exception":exception,@"error":error?(id)@{@"domain":error.domain,@"code":@(error.code)}:(id)[NSNull null]};
}
static void storageOperationCases(NSString *root){
    puts("Storage operation Foundation: twelve complete actual/frozen routes, real atomic UTF8/JSON files and explicit MRC provider owners");fflush(stdout);
    NSString *path=[root stringByAppendingPathComponent:@"storage-operations.json"];
    NSArray *methods=@[@"readText",@"writeText",@"readJSON",@"writeJSON"];
    const unichar badUTF16=0xd800;
    NSArray *inputs=@[@"ảnh 测试 😀\0tail",@"",@42,[NSNull null],@[@"ảnh",@42,@YES],@{@"n":@7},[NSString stringWithCharacters:&badUTF16 length:1]];
    NSArray *bodies=@[@"{\"n\":1}",@"",@"{bad}",@"\ufeff{\"n\":1}",@"null",@"[\"ảnh\"]"];
    unsigned comparisons=0;
    for(unsigned backend=0;backend<3;++backend){
        for(NSString *method in methods){
            for(unsigned policy=0;policy<3;++policy){
                const BOOL reading=[method hasPrefix:@"read"];
                for(id input in (reading?@[[NSNull null]]:inputs)){
                    for(NSString *body in (reading?bodies:@[@"sentinel"])){

                        @autoreleasepool {
                            assert([body writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
                            NSDictionary *expected=storageOperationRun(backend,YES,path,method,input,policy);
                            assert([body writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
                            NSDictionary *actual=storageOperationRun(backend,NO,path,method,input,policy);
                            if(![expected isEqual:actual])fprintf(stderr,"Storage operation parity: backend=%u method=%s policy=%u\n",backend,method.UTF8String,policy);
                            assert([expected isEqual:actual]);++comparisons;
                        }
                    }
                }
            }
            for(BOOL before:{YES,NO}){
                TLinkAXFixtureResetOwners();storageOperationOwners=true;
                storageOperationCheckPreparation=!before&&backend<2&&[method isEqual:@"writeJSON"];
                @autoreleasepool {
                    for(unsigned n=0;n<32;++n){
                        assert([@"[1]" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
                        NSDictionary *held=storageOperationRun(backend,before,path,method,[method isEqual:@"writeJSON"]?(id)@[@1]:(id)@"[1]",0);
                        assert(held[@"reply"]);
                        if(!before)assert(TLinkAXFixtureLiveOwners()==0);
                    }
                    if(before)assert(TLinkAXFixtureLiveOwners()>=32);
                    else assert(TLinkAXFixturePeakOwners()<=4);
                }
                assert(TLinkAXFixtureLiveOwners()==0);storageOperationOwners=false;storageOperationCheckPreparation=false;
            }
        }
    }
    for(unsigned backend=0;backend<3;++backend){
        for(NSString *method in @[@"writeText",@"writeJSON"]){
            for(NSUInteger length:{(NSUInteger)524287,(NSUInteger)524288,(NSUInteger)524289}){
                @autoreleasepool {
                    const BOOL json=[method isEqual:@"writeJSON"];
                    const NSJSONWritingOptions options=backend==2?NSJSONWritingPrettyPrinted:(NSJSONWritingOptions)0;
                    const NSUInteger overhead=json?[NSJSONSerialization dataWithJSONObject:@[@""] options:options error:nil].length:0;
                    assert(overhead<length);const NSUInteger textLength=length-overhead;
                    NSString *text=[@"x" stringByPaddingToLength:textLength withString:@"x" startingAtIndex:0];
                    id input=json?(id)@[text]:(id)text;
                    if(json)assert([NSJSONSerialization dataWithJSONObject:input options:options error:nil].length==length);
                    assert([@"sentinel" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
                    NSDictionary *expected=storageOperationRun(backend,YES,path,method,input,0);
                    assert([@"sentinel" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
                    NSDictionary *actual=storageOperationRun(backend,NO,path,method,input,0);
                    assert([expected isEqual:actual]);++comparisons;
                }
            }
        }
    }
    assert(comparisons==252);
    NSDictionary *held=nil;
    @autoreleasepool {
        assert([@"[1]" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
        held=storageOperationRun(0,NO,path,@"readJSON",nil,0);
    }
    assert([held[@"reply"][@"value"][@"value"][0] intValue]==1);
    // Exceptional pool exit is not assumed to retire independently. An outer
    // caller pool supplies cleanup; propagation and recovery remain unchanged.
    for(unsigned backend=0;backend<3;++backend){
        for(unsigned fault=1;fault<=2;++fault){
            for(BOOL before:{YES,NO}){
                storageOperationOwners=true;storageOperationFault=fault;bool caught=false;
                @autoreleasepool {
                    @try {try {(void)storageOperationRun(backend,before,path,@"writeText",@"value",0);}catch(const std::runtime_error &){caught=true;}}
                    @catch(NSException *exception){assert([exception.name isEqual:@"StorageOperationFixture"]);caught=true;}
                }
                assert(caught&&TLinkAXFixtureLiveOwners()==0);storageOperationOwners=false;storageOperationFault=0;
            }
        }
    }
    puts("Storage operation Foundation passed: 252 complete reply/file/path/count/error comparisons, twelve route lifetime matrices, retained results, original propagated NS/C++ faults and caller-pool recovery. Foundation allocations/RSS and device performance remain unqualified.");
}
