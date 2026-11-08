// A real immutable NSData backing with a controlled writer. The selected route
// must hand the existing serialized bytes to this writer, without a re-encode.
static bool preparedJSONCapture=false;
static unsigned preparedJSONWrites=0,preparedJSONLive=0,preparedJSONFault=0;
static NSData *preparedJSONWrittenBytes=nil;
static NSDataWritingOptions preparedJSONOptions=(NSDataWritingOptions)0;
@interface PreparedJSONData : NSData {
    NSData *_backing;
}
- (instancetype)initWithBacking:(NSData *)data;
@end
@implementation PreparedJSONData
- (instancetype)initWithBacking:(NSData *)data {self=[super init];if(self){_backing=[data copy];++preparedJSONLive;}return self;}
- (NSUInteger)length {return _backing.length;}
- (const void *)bytes {return _backing.bytes;}
- (id)copyWithZone:(NSZone *)zone {(void)zone;return self;}
- (BOOL)writeToFile:(NSString *)path options:(NSDataWritingOptions)options error:(NSError **)error {
    ++preparedJSONWrites;preparedJSONWrittenBytes=_backing;preparedJSONOptions=options;
    if(preparedJSONFault==1){if(error)*error=[NSError errorWithDomain:@"PreparedJSONFixture" code:17 userInfo:nil];return NO;}
    if(preparedJSONFault==2)[NSException raise:@"PreparedJSONFixture" format:@"write"];
    if(preparedJSONFault==3)throw std::runtime_error("write");
    return [_backing writeToFile:path options:options error:error];
}
- (void)dealloc {assert(preparedJSONLive>0);--preparedJSONLive;}
@end
static NSData *storagePreparedJSONData(NSData *data){
    return preparedJSONCapture&&data?[[PreparedJSONData alloc] initWithBacking:data]:data;
}
@interface StorageJSONWriteBeforeRoot : StorageOperationRoot @end
@implementation StorageJSONWriteBeforeRoot
- (TLinkJSNativeResponse *)executeRequest:(TLinkJSNativeRequest *)request context:(id)context error:(NSError **)error {
    if(![request.method isEqual:TLinkJSNativeMethodWriteJSON])return [super executeRequest:request context:context error:error];
    NSString *method=request.method;NSArray *args=request.arguments;
    if(NO){}
#define NSJSONSerialization StorageOperationJSON
#include "StorageJSONWriteBefore-root.inc"
#undef NSJSONSerialization
    return nil;
}
@end
@interface StorageJSONWriteBeforeHelper : StorageOperationHelper @end
@implementation StorageJSONWriteBeforeHelper
#define NSJSONSerialization StorageOperationJSON
#define JSValue StorageOperationJSValue
#include "StorageJSONWriteBefore-helper.inc"
#undef JSValue
#undef NSJSONSerialization
@end
static NSDictionary *storagePreparedJSONRun(unsigned backend,bool before,NSString *path,id input,unsigned policy){
    assert([@"sentinel" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    StorageOperationRuntime *runtime;
    if(backend==0)runtime=before?[StorageJSONWriteBeforeRoot new]:[StorageOperationRoot new];
    else runtime=before?[StorageJSONWriteBeforeHelper new]:[StorageOperationHelper new];
    runtime.path=path;runtime.policy=policy;runtime.trace=[NSMutableArray array];
    NSError *error=nil;NSDictionary *reply=nil;NSString *exception=@"";
    @try {try {reply=storageOperationReply(backend,NO,runtime,@"writeJSON",input,&error);}catch(const std::runtime_error &){exception=@"cpp";}}
    @catch(NSException *caught){exception=caught.name;}
    return @{@"reply":reply?:@{},@"trace":[runtime.trace copy],@"ops":@(runtime.storageOpsCount),@"bytes":[NSData dataWithContentsOfFile:path]?:[NSData data],@"exception":exception,@"error":error?(id)@{@"domain":error.domain,@"code":@(error.code)}:(id)[NSNull null]};
}
static NSDictionary *preparedJSONTargetResult(NSString *text,NSString *target,BOOL atomic,NSStringEncoding encoding){
    NSError *error=nil;BOOL ok=NO;NSString *exception=@"",*reason=@"";
    @try {ok=[text writeToFile:target atomically:atomic encoding:encoding error:&error];}
    @catch(NSException *caught){exception=[caught.name copy]?:@"";reason=[caught.reason copy]?:@"";}
    return @{@"ok":@(ok),@"hasError":@(error!=nil),@"domain":error.domain?:@"",@"code":@(error.code),
             @"description":error.localizedDescription?:@"",@"exception":exception,@"reason":reason};
}
static void storagePreparedJSONInvalidTargetCases(){
    const NSStringEncoding encodings[]={NSUTF8StringEncoding,NSUTF16StringEncoding};
    unsigned comparisons=0;
    for(unsigned kind=0;kind<4;++kind){
        for(BOOL atomic:{NO,YES}){
            for(NSStringEncoding encoding:encodings){
                @autoreleasepool {
                    id target=kind==0?nil:(kind==1?(id)@"":(kind==2?(id)[NSNull null]:(id)@42));
                    PreparedJSONData *bytes=[[PreparedJSONData alloc] initWithBacking:[@"[\"ảnh\"]" dataUsingEncoding:NSUTF8StringEncoding]];
                    NSString *old=[[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding];
                    NSString *now=[[TLinkPreparedJSONText alloc] initWithJSONData:bytes];bytes=nil;
                    preparedJSONWrites=0;preparedJSONWrittenBytes=nil;
                    NSDictionary *expected=preparedJSONTargetResult(old,(NSString *)target,atomic,encoding);
                    NSDictionary *actual=preparedJSONTargetResult(now,(NSString *)target,atomic,encoding);
                    if(![expected isEqual:actual])fprintf(stderr,"Prepared JSON target parity: kind=%u atomic=%d encoding=%lu\nexpected=%s\nactual=%s\n",kind,(int)atomic,(unsigned long)encoding,[[expected description] UTF8String],[[actual description] UTF8String]);
                    assert([expected isEqual:actual]&&preparedJSONWrites==0&&!preparedJSONWrittenBytes);++comparisons;
                }
                assert(preparedJSONLive==0);
            }
        }
    }
    assert(comparisons==16);
    puts("Prepared JSON invalid targets: 16 exact NSString error/exception comparisons for nil/empty/NSNull/number paths, atomic/non-atomic and UTF8/UTF16; no encoded-data writer call or retry.");
}
static void storagePreparedJSONRouteCases(NSString *path){
    unsigned comparisons=0;
    for(unsigned backend=0;backend<2;++backend){
        for(unsigned policy=0;policy<3;++policy){
            for(id object in @[@[@"ảnh\0测试😀",@42,@YES],@{@"empty":@[],@"nul":@"a\0b"},@[],@{},@"invalid",[NSNull null]]){
                @autoreleasepool {
                    preparedJSONCapture=true;preparedJSONWrites=0;preparedJSONWrittenBytes=nil;
                    NSDictionary *old=storagePreparedJSONRun(backend,true,path,object,policy);
                    assert(preparedJSONWrites==0);preparedJSONWrites=0;
                    NSDictionary *now=storagePreparedJSONRun(backend,false,path,object,policy);
                    assert([old isEqual:now]);
                    const bool accepted=[now[@"reply"][@"ok"] boolValue]&&policy==0&&[NSJSONSerialization isValidJSONObject:object];
                    if(policy!=2)assert(preparedJSONWrites==(accepted?1U:0U));
                    else assert(preparedJSONWrites==0);
                    if(accepted){assert(preparedJSONOptions==NSDataWritingAtomic&&[preparedJSONWrittenBytes isEqual:now[@"bytes"]]);}
                    preparedJSONCapture=false;preparedJSONWrittenBytes=nil;++comparisons;
                }
                assert(preparedJSONLive==0);
            }
        }
        for(NSUInteger size:{NSUInteger(524287),NSUInteger(524288),NSUInteger(524289)}){@autoreleasepool {
            NSString *text=[@"" stringByPaddingToLength:size-4 withString:@"x" startingAtIndex:0];
            NSArray *input=@[text];assert([NSJSONSerialization dataWithJSONObject:input options:0 error:nil].length==size);
            preparedJSONCapture=true;preparedJSONWrites=0;
            NSDictionary *old=storagePreparedJSONRun(backend,true,path,input,0);assert(preparedJSONWrites==0);
            NSDictionary *now=storagePreparedJSONRun(backend,false,path,input,0);
            assert([old isEqual:now]&&preparedJSONWrites==(size<=524288?1U:0U));
            preparedJSONCapture=false;preparedJSONWrittenBytes=nil;++comparisons;
        }}
        assert(preparedJSONLive==0);
    }
    assert(comparisons==42);
    for(unsigned backend=0;backend<2;++backend){
        for(unsigned fault=1;fault<4;++fault){
            @autoreleasepool {
                preparedJSONCapture=true;preparedJSONFault=fault;preparedJSONWrites=0;
                NSDictionary *now=storagePreparedJSONRun(backend,false,path,@[@1],0);
                preparedJSONFault=0;preparedJSONCapture=false;
                assert(preparedJSONWrites==1&&[now[@"bytes"] isEqual:[@"sentinel" dataUsingEncoding:NSUTF8StringEncoding]]);
                if(fault==1){
                    NSDictionary *reply=backend==0?now[@"reply"][@"value"]:now[@"reply"];
                    NSString *message=[NSError errorWithDomain:@"PreparedJSONFixture" code:17 userInfo:nil].localizedDescription;
                    assert(![reply[@"ok"] boolValue]&&[reply[@"error"] isEqual:message]&&[now[@"exception"] isEqual:@""]);
                }else assert([now[@"exception"] isEqual:(fault==2?@"PreparedJSONFixture":@"cpp")]);
                assert([now[@"ops"] unsignedIntegerValue]==(backend==1?2U:0U));
                preparedJSONWrittenBytes=nil;
            }
            assert(preparedJSONLive==0);
        }
    }
}
static void storagePreparedJSONStringCases(NSString *root){
    NSString *path=[root stringByAppendingPathComponent:@"prepared-string.json"];
    const uint8_t invalid[]={0xff,0xfe,0x80};
    NSMutableArray *inputs=[NSMutableArray arrayWithArray:@[[NSData data],[NSData dataWithBytes:invalid length:sizeof(invalid)]]];
    for(NSString *text in @[@"[]",@"{\"ảnh\":\"测试😀\"}",@"a\0b",@"\ufeff{}",@"\ufeff\ufeff{}"])[inputs addObject:[text dataUsingEncoding:NSUTF8StringEncoding]];
    for(unsigned n=0;n<1000;++n){
        NSDictionary *object=@{@"n":@(n),@"text":@"ảnh 测试😀\0tail",@"nested":@[@YES,@NO,[NSNull null]]};
        [inputs addObject:[NSJSONSerialization dataWithJSONObject:object options:n%2?NSJSONWritingPrettyPrinted:(NSJSONWritingOptions)0 error:nil]];
    }
    for(NSData *bytes in inputs){@autoreleasepool {
        NSString *old=[[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding];
        NSString *now=[[TLinkPreparedJSONText alloc] initWithJSONData:bytes];
        assert((!old&&!now)||[old isEqual:now]);if(!now)continue;
        assert(now.length==old.length&&[[now copy] isEqual:old]&&[[now mutableCopy] isEqual:old]);
        if(now.length){assert([now characterAtIndex:now.length-1]==[old characterAtIndex:old.length-1]);unichar value=0;[now getCharacters:&value range:NSMakeRange(0,1)];assert(value==[old characterAtIndex:0]);}
        for(NSStringEncoding encoding:{NSUTF8StringEncoding,NSUTF16StringEncoding,NSASCIIStringEncoding}){
            assert([now lengthOfBytesUsingEncoding:encoding]==[old lengthOfBytesUsingEncoding:encoding]);
            NSData *expected=[old dataUsingEncoding:encoding],*actual=[now dataUsingEncoding:encoding];
            assert((!expected&&!actual)||[expected isEqual:actual]);
            for(BOOL atomic:{NO,YES}){
                NSError *oldError=nil,*newError=nil;
                BOOL expectedWrite=[old writeToFile:path atomically:atomic encoding:encoding error:&oldError];
                NSData *expectedFile=[NSData dataWithContentsOfFile:path];
                BOOL actualWrite=[now writeToFile:path atomically:atomic encoding:encoding error:&newError];
                assert(expectedWrite==actualWrite&&[expectedFile isEqual:[NSData dataWithContentsOfFile:path]]);
                assert((!oldError&&!newError)||([oldError.domain isEqual:newError.domain]&&oldError.code==newError.code));
            }
        }
    }}
    // Mutable input changes cannot change either the public string or written bytes.
    NSString *held=nil;NSData *expected=nil;__weak NSData *weak=nil;
    @autoreleasepool {
        NSMutableData *mutableBytes=[NSMutableData dataWithData:[@"{\"n\":1}" dataUsingEncoding:NSUTF8StringEncoding]];
        held=[[TLinkPreparedJSONText alloc] initWithJSONData:mutableBytes];
        expected=[mutableBytes copy];[mutableBytes resetBytesInRange:NSMakeRange(0,mutableBytes.length)];
        weak=[held dataUsingEncoding:NSUTF8StringEncoding];
    }
    @autoreleasepool {
        assert(weak&&[held isEqual:@"{\"n\":1}"]&&[[held dataUsingEncoding:NSUTF8StringEncoding] isEqual:expected]);
        held=nil;expected=nil;
    }
    assert(!weak);
    for(unsigned fault=0;fault<4;++fault){
        @autoreleasepool {
            PreparedJSONData *data=[[PreparedJSONData alloc] initWithBacking:[@"[1]" dataUsingEncoding:NSUTF8StringEncoding]];
            NSString *text=[[TLinkPreparedJSONText alloc] initWithJSONData:data];data=nil;
            assert(preparedJSONLive==1);preparedJSONFault=fault;preparedJSONWrites=0;
            NSError *error=nil;BOOL ok=NO;bool caught=false;
            @try {try {ok=[text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];}catch(const std::runtime_error &){caught=true;}}
            @catch(NSException *exception){assert([exception.name isEqual:@"PreparedJSONFixture"]);caught=true;}
            preparedJSONFault=0;
            assert(preparedJSONWrites==1&&caught==(fault>=2));
            if(fault<2)assert(ok==(fault==0)&&(fault==0||[error.domain isEqual:@"PreparedJSONFixture"]));
            preparedJSONWrittenBytes=nil;
        }
        assert(preparedJSONLive==0);
    }
    // Exercise actual Foundation failure codes rather than inventing a retry.
    for(NSString *target in @[root,[root stringByAppendingPathComponent:@"missing-parent/file.json"]]){
        NSString *old=@"[1]",*now=[[TLinkPreparedJSONText alloc] initWithJSONData:[old dataUsingEncoding:NSUTF8StringEncoding]];
        NSError *a=nil,*b=nil;BOOL expectedWrite=[old writeToFile:target atomically:YES encoding:NSUTF8StringEncoding error:&a];
        BOOL actualWrite=[now writeToFile:target atomically:YES encoding:NSUTF8StringEncoding error:&b];
        assert(expectedWrite==actualWrite&&[a.domain isEqual:b.domain]&&a.code==b.code&&[a.localizedDescription isEqual:b.localizedDescription]);
    }
    // Compare replacement effects/permissions with the original NSString writer.
    for(NSNumber *mode in @[@0600,@0644,@0444]){
        for(BOOL atomic:{NO,YES}){
            NSDictionary *expected=nil;
            for(bool prepared:{false,true}){
                assert([[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:@0644} ofItemAtPath:path error:nil]);
                assert([@"sentinel" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
                assert([[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:mode} ofItemAtPath:path error:nil]);
                NSString *text=prepared?[[TLinkPreparedJSONText alloc] initWithJSONData:[@"[1]" dataUsingEncoding:NSUTF8StringEncoding]]:@"[1]";
                NSError *error=nil;BOOL ok=[text writeToFile:path atomically:atomic encoding:NSUTF8StringEncoding error:&error];
                NSDictionary *attributes=[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
                NSDictionary *actual=@{@"ok":@(ok),@"bytes":[NSData dataWithContentsOfFile:path],@"mode":attributes[NSFilePosixPermissions],@"owner":attributes[NSFileOwnerAccountID],@"group":attributes[NSFileGroupOwnerAccountID],@"domain":error.domain?:@"",@"code":@(error.code)};
                if(!prepared)expected=actual;else assert([expected isEqual:actual]);
            }
        }
    }
    assert([[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:@0644} ofItemAtPath:path error:nil]);
}
static void storagePreparedJSONCases(NSString *root){
    puts("Prepared JSON Foundation: actual NSString adapter and frozen root/helper recursive writes with retained encoded NSData");fflush(stdout);
    storagePreparedJSONInvalidTargetCases();
    storagePreparedJSONRouteCases([root stringByAppendingPathComponent:@"prepared-route.json"]);
    storagePreparedJSONStringCases(root);
    assert(!preparedJSONCapture&&!preparedJSONFault&&!preparedJSONLive);
    puts("Prepared JSON passed: 42 frozen complete root/helper reply/file/path/count/error cases, exact 512-KiB boundaries, 1000 Unicode JSON/string/encoding/atomic-write cases, same encoded-data writer, mutable snapshots, pool lifetime, direct-write faults and real Foundation errors. NSString decoding remains; Foundation internal allocation/device IO pending.");
}
