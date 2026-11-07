#include "FilePlanConstants.inc"
#include <type_traits>
static_assert(!std::is_default_constructible<TLinkJSFileModePlan>::value,"only the validator creates mode plans");
static_assert(std::is_copy_constructible<TLinkJSFileModePlan>::value,"owned mode snapshots can outlive preparation pools");
static NSUInteger filePlanModeOwners=0;
@interface FilePlanModeOwner:NSString {
    NSString *_backing;
}
- (instancetype)initWithMode:(NSString *)mode;
@end
@implementation FilePlanModeOwner
- (instancetype)initWithMode:(NSString *)mode {self=[super init];if(self){_backing=[mode copy];++filePlanModeOwners;}return self;}
- (NSUInteger)length {return _backing.length;}
- (unichar)characterAtIndex:(NSUInteger)index {return [_backing characterAtIndex:index];}
- (void)getCharacters:(unichar *)buffer range:(NSRange)range {[_backing getCharacters:buffer range:range];}
- (NSUInteger)hash {return _backing.hash;}
- (BOOL)isEqual:(id)object {return [_backing isEqual:object];}
- (BOOL)isEqualToString:(NSString *)string {return [_backing isEqualToString:string];}
- (NSString *)lowercaseString {return self;}
- (NSString *)stringByTrimmingCharactersInSet:(NSCharacterSet *)set {(void)set;return self;}
- (id)copyWithZone:(NSZone *)zone {(void)zone;return self;}
- (void)dealloc {assert(filePlanModeOwners>0);--filePlanModeOwners;}
@end
@interface FilePlanHost:NSObject
@property(nonatomic,copy) NSString *path;
@property(nonatomic,strong) NSMutableDictionary *openFileHandles,*activeFileHandles,*fileHandles;
@property(nonatomic) NSUInteger nextOpenFileHandleId,nextFileHandleId,storageOpsCount;
@property(nonatomic,strong) NSCondition *rpcCondition;
@property(nonatomic,copy) NSString *activeSessionId;
@property(nonatomic,strong) NSMutableArray *trace;
@property(nonatomic) BOOL deny;
@property(nonatomic,strong) NSMutableString *mutatingMode;
- (NSDictionary *)resolvedOpenFilePath:(NSString *)path writing:(BOOL)writing;
- (NSDictionary *)bundleStoragePathForRelativePath:(NSString *)path bundlePath:(NSString *)bundle writing:(BOOL)writing createParent:(BOOL)create;
@end
@implementation FilePlanHost
- (instancetype)init {self=[super init];if(self){_openFileHandles=[NSMutableDictionary dictionary];_activeFileHandles=[NSMutableDictionary dictionary];_fileHandles=[NSMutableDictionary dictionary];_trace=[NSMutableArray array];_rpcCondition=[NSCondition new];_activeSessionId=@"session";}return self;}
- (NSDictionary *)resolvedOpenFilePath:(NSString *)path writing:(BOOL)writing {
    [self.trace addObject:@{@"relative":path?:@"",@"writing":@(writing)}];
    if(self.mutatingMode)[self.mutatingMode setString:@"w+"];
    return self.deny?@{@"ok":@NO,@"error":@"controlled_path_denial"}:@{@"ok":@YES,@"path":self.path};
}
- (NSDictionary *)bundleStoragePathForRelativePath:(NSString *)path bundlePath:(NSString *)bundle writing:(BOOL)writing createParent:(BOOL)create {
    [self.trace addObject:@{@"bundle":bundle,@"create":@(create)}];return [self resolvedOpenFilePath:path writing:writing];
}
@end
@interface FilePlanRoot:FilePlanHost
- (JSValue *)openFile:(NSString *)path mode:(NSString *)mode;
@end
@implementation FilePlanRoot
#define TLinkautoDeviceBridge FilePlanRoot
#include "FilePlan-root.inc"
#undef TLinkautoDeviceBridge
@end
@interface FilePlanBeforeRoot:FilePlanRoot @end
@implementation FilePlanBeforeRoot
#define TLinkautoDeviceBridge FilePlanRoot
#include "FilePlanBefore-root.inc"
#undef TLinkautoDeviceBridge
@end
@interface FilePlanHelper:FilePlanHost
- (JSValue *)openFileAtRelativePath:(NSString *)path mode:(NSString *)mode bundlePath:(NSString *)bundle context:(JSContext *)context sessionId:(NSString *)session;
@end
@implementation FilePlanHelper
#define TLinkJSHelperServer FilePlanHelper
#include "FilePlan-helper.inc"
#undef TLinkJSHelperServer
@end
@interface FilePlanBeforeHelper:FilePlanHelper @end
@implementation FilePlanBeforeHelper
#define TLinkJSHelperServer FilePlanHelper
#include "FilePlanBefore-helper.inc"
#undef TLinkJSHelperServer
@end
static NSString *filePlanStoragePath(FilePlanHost *host,NSString *path,BOOL writing,NSString **error){
    NSDictionary *resolved=[host resolvedOpenFilePath:path writing:writing];if(![resolved[@"ok"] boolValue]){if(error)*error=resolved[@"error"];return nil;}return resolved[@"path"];
}
static JSValue *filePlanTrollOpen(bool before,FilePlanHost *host,JSContext *context,NSString *mode){
    __weak FilePlanHost *weakSession=host;NSMutableDictionary *device=[NSMutableDictionary dictionary];
#define TLinkScriptSession FilePlanHost
#define TLinkScriptStoragePath filePlanStoragePath
    if(before){
#include "FilePlanBefore-troll.inc"
    }else{
#include "FilePlan-troll.inc"
    }
#undef TLinkScriptStoragePath
#undef TLinkScriptSession
    JSValue *(^open)(NSString *,NSString *)=device[@"openFile"];return open(@"relative.bin",mode);
}
static NSDictionary *filePlanFrontend(unsigned backend,bool before,NSString *path,NSString *mode,BOOL deny=NO,BOOL mutate=NO){
    fileReset();assert([@"seed\nrest" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    FilePlanHost *host;
    if(backend==0)host=before?[FilePlanBeforeRoot new]:[FilePlanRoot new];
    else if(backend==1)host=before?[FilePlanBeforeHelper new]:[FilePlanHelper new];
    else host=[FilePlanHost new];
    host.path=path;host.deny=deny;if(mutate)host.mutatingMode=(NSMutableString *)mode;
    JSContext *context=[JSContext new];
    context[@"open"] = ^JSValue *{
        if(backend==0)return [(FilePlanRoot *)host openFile:@"relative.bin" mode:mode];
        if(backend==1)return [(FilePlanHelper *)host openFileAtRelativePath:@"relative.bin" mode:mode bundlePath:@"bundle" context:[JSContext currentContext] sessionId:@"session"];
        return filePlanTrollOpen(before,host,[JSContext currentContext],mode);
    };
    fileLifecycleMeasure=true;fileOpening=true;
    JSValue *object=[context evaluateScript:@"var f=open(); f"];
    fileOpening=false;const unsigned normalizations=fileLifecycleNormalizations;fileLifecycleMeasure=false;
    assert(!context.exception);
    NSDictionary *metadata=[@{@"ok":object[@"ok"],@"mode":object[@"mode"],@"path":object[@"path"],@"error":object[@"error"]} copy];
    // JSValues are converted before leaving their context, including undefined.
    NSMutableDictionary *plain=[NSMutableDictionary dictionary];
    for(NSString *key in metadata){JSValue *value=metadata[key];if(!value.isUndefined)plain[key]=[value toObject]?:[NSNull null];}
    const int flags=fileLifecycleLastFlags;
    NSArray *trace=[host.trace copy];const NSUInteger ops=host.storageOpsCount;
    const NSUInteger live=host.openFileHandles.count+host.activeFileHandles.count+host.fileHandles.count;
    if([object[@"ok"] toBool]){[context evaluateScript:@"f.close()"];assert(!context.exception);}
    assert(fileFDs.empty()&&host.openFileHandles.count+host.activeFileHandles.count+host.fileHandles.count==0);
    context[@"open"]=nil;context[@"f"]=nil;
    return @{@"metadata":plain,@"trace":trace,@"ops":@(ops),@"live":@(live),@"normalizations":@(normalizations),@"flags":@(flags),@"bytes":[NSData dataWithContentsOfFile:path]?:[NSData data]};
}
static void filePlanModeCases(NSString *path){
    NSArray *modes=@[@"r",@"rb",@"r+",@"rb+",@"w",@"wb",@"w+",@"wb+",@"a",@"ab",@"a+",@"ab+",@"r+b",@"w+b",@"a+b",@" RB+ \n",@"bad",@"q+",@"",@"ảnh",@"r\0w"];
    for(NSString *mode in modes){
        const auto plan=TLinkJSFilePrepareMode(mode);
        assert(plan.valid()==bool(TLinkJSFileModeIsValid(mode)));
        if(plan.valid())assert(plan.writing()==bool(TLinkJSFileModeWrites(mode)));
        for(unsigned backend=0;backend<3;++backend){
            @autoreleasepool {
                NSDictionary *old=filePlanFrontend(backend,true,path,mode),*now=filePlanFrontend(backend,false,path,mode);
                NSMutableDictionary *before=[old mutableCopy],*after=[now mutableCopy];[before removeObjectForKey:@"normalizations"];[after removeObjectForKey:@"normalizations"];
                assert([before isEqual:after]);
                if([now[@"live"] intValue])assert([old[@"normalizations"] intValue]==3&&[now[@"normalizations"] intValue]==1);
                assert([filePlanFrontend(backend,true,path,mode,YES)[@"metadata"] isEqual:filePlanFrontend(backend,false,path,mode,YES)[@"metadata"]]);
            }
        }
    }
    for(unsigned backend=0;backend<3;++backend){
        NSMutableString *oldMode=[@"r" mutableCopy],*newMode=[@"r" mutableCopy];
        NSDictionary *old=filePlanFrontend(backend,true,path,oldMode,NO,YES),*now=filePlanFrontend(backend,false,path,newMode,NO,YES);
        assert(([old[@"flags"] intValue]&O_TRUNC)!=0&&[old[@"bytes"] length]==0);
        assert(([now[@"flags"] intValue]&(O_TRUNC|O_CREAT))==0&&[now[@"bytes"] length]>0);
        NSDictionary *policy=[now[@"trace"] lastObject];
        assert([now[@"metadata"][@"mode"] isEqual:@"r"]&&[newMode isEqual:@"w+"]&&[policy[@"writing"] isEqual:@NO]);
    }
    NSMutableString *source=[@" A+B " mutableCopy];
    auto copied=TLinkJSFilePrepareMode(@"invalid");
    @autoreleasepool {copied=TLinkJSFilePrepareMode(source);}
    [source setString:@"r"];assert(copied.valid()&&copied.writing()&&[copied.mode() isEqual:@"ab+"]);
    auto owned=TLinkJSFilePrepareMode(@"invalid");
    @autoreleasepool {
        FilePlanModeOwner *owner=[[FilePlanModeOwner alloc] initWithMode:@"r+"];
        owned=TLinkJSFilePrepareMode(owner);assert(owned.valid()&&owned.mode()==owner);owner=nil;
    }
    assert(filePlanModeOwners==1);owned=TLinkJSFilePrepareMode(@"r");assert(filePlanModeOwners==0);
    fileReset();NSString *error=nil;const auto invalid=TLinkJSFilePrepareMode(@"invalid");
    assert(![TLinkJSFileHandle openPath:path preparedMode:invalid handleId:1 maxTransferBytes:32 error:&error]&&[error isEqual:@"invalid_file_mode"]&&fileLifecycleOpenCalls==0);
    for(unsigned fault=0;fault<3;++fault){
        fileReset();NSString *failure=nil;unsigned caught=0;TLinkJSFileHandle *handle=nil;
        if(fault==0)fileLifecycleFactoryFault=1;else{fileLifecycleStage=7;fileLifecycleThrow=fault;}
        const auto plan=TLinkJSFilePrepareMode(@"r+");fileOpening=true;
        @try {try {handle=[FileLifecycleFaultHandle openPath:path preparedMode:plan handleId:1 maxTransferBytes:32 error:&failure];}catch(const std::runtime_error &){caught=2;}}
        @catch(NSException *exception){(void)exception;caught=1;}
        @finally {fileOpening=false;}
        assert(!handle&&fileFDs.empty()&&fileLifecycleOpenCalls==1&&fileLifecycleCloses==1&&caught==fault);
        if(!fault)assert([failure hasPrefix:@"file_open_failed errno="]);
    }
    fileReset();
}

static void filePlanRuntimeCases(NSString *path){
    puts("File mode/bindings Foundation: actual/frozen root/helper/TrollStore open paths, real JSCore/POSIX files and sealed mode snapshots");fflush(stdout);
    filePlanModeCases(path);filePlanBindingCases();
    NSArray *expected=nil;
    for(bool legacy:{true,false}){
        fileReset();assert([@"seed\nrest" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
        JSContext *context=[JSContext new];NSArray *held=nil;
        @autoreleasepool {
            TLinkJSFileHandle *handle=fileOpen(legacy,path,@"r+",64);
            context[@"file"]=legacy?LegacyTLinkJSFileHandleCreateJSObject(context,(LegacyTLinkJSFileHandle *)handle,nil):TLinkJSFileHandleCreateJSObject(context,handle,nil);
        }
        assert(fileFDs.size()==1);
        @autoreleasepool {
            held=[[context evaluateScript:@"[file.write('AB'),file.writeBase64('Qw=='),file.seek('set',0),file.read(2),file.readLine(),file.tell(),file.flush(),file.isClosed(),file.close(),file.isClosed()]"] toObject];
        }
        assert(!context.exception&&held.count==10&&fileFDs.empty());
        if(legacy)expected=held;else assert([held isEqual:expected]);
        context[@"file"]=nil;
    }
    puts("File mode/bindings passed: complete three-frontend mode/flags/file/reply/close/count parity, three-to-one normalization, mutable read-to-write fencing, owned plan across pools, invalid refusal and nine direct binding pool/argument/result/NS-C++ matrices. Foundation/device performance remains unqualified.");
}
