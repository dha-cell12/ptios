@interface FileLifecycleNilHandle:TLinkJSFileHandle @end
@implementation FileLifecycleNilHandle
- (instancetype)init {self=[super init];self=nil;return self;}
@end
@interface FileLifecycleFaultHandle:TLinkJSFileHandle @end
@implementation FileLifecycleFaultHandle
- (instancetype)init {
    self=[super init];
    if(fileLifecycleInitFault){self=nil;fileLifecycleRaise(fileLifecycleInitFault);}
    return self;
}
- (void)setPath:(NSString *)value {if(fileLifecycleTrip(7))return;[super setPath:value];}
- (void)setMode:(NSString *)value {if(fileLifecycleTrip(8))return;[super setMode:value];}
- (void)setHandleId:(NSUInteger)value {if(fileLifecycleTrip(9))return;[super setHandleId:value];}
- (void)setClosed:(BOOL)value {[super setClosed:value];if(fileLifecycleTrip(10))return;}
@end
static void fileLifecycleRequire(bool condition,unsigned line){
    if(!condition)fprintf(stderr,"File lifecycle failure line %u: stage=%u throw=%u factory=%u init=%u opens=%u closes=%u liveFDs=%zu norm=%u seekNorm=%u owners=%llu liveOwners=%llu\n",line,
        fileLifecycleStage,fileLifecycleThrow,fileLifecycleFactoryFault,fileLifecycleInitFault,fileLifecycleOpenCalls,fileLifecycleCloses,
        fileFDs.size(),fileLifecycleNormalizations,fileLifecycleSeekNormalizations,
        (unsigned long long)TLinkAXFixtureCreatedOwners(),(unsigned long long)TLinkAXFixtureLiveOwners());
    assert(condition);
}
#define FILE_LIFECYCLE_REQUIRE(condition) fileLifecycleRequire((condition),__LINE__)
static TLinkJSFileHandle *fileLifecycleTryOpen(Class klass,NSString *path,NSString *mode,NSString **error,unsigned &caught){
    TLinkJSFileHandle *handle=nil;fileOpening=true;
    @try{try{handle=[klass openPath:path mode:mode handleId:99 maxTransferBytes:128 error:error];}
        catch(const std::runtime_error &){caught=2;}}
    @catch(__unused NSException *exception){caught=1;}
    @finally{fileOpening=false;}
    return handle;
}
static NSDictionary *fileLifecycleModeTrace(bool legacy,NSString *path,NSString *mode){
    fileReset();FILE_LIFECYCLE_REQUIRE([[@"seed\n" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES]);
    NSString *error=nil;unsigned caught=0;
    Class klass=legacy?[LegacyTLinkJSFileHandle class]:[TLinkJSFileHandle class];
    TLinkJSFileHandle *handle=fileLifecycleTryOpen(klass,path,mode,&error,caught);FILE_LIFECYCLE_REQUIRE(!caught);
    NSMutableArray *replies=[NSMutableArray array];
    if(handle){[replies addObject:[handle readRequest:@0]];[replies addObject:[handle tell]];[replies addObject:[handle flush]];[replies addObject:[handle close]];}
    FILE_LIFECYCLE_REQUIRE(fileFDs.empty());
    return @{@"opened":@(handle!=nil),@"error":error?:@"",@"mode":(id)handle.mode?:[NSNull null],@"path":handle.path?:@"",
        @"flags":@(fileLifecycleLastFlags),@"opens":@(fileLifecycleOpenCalls),@"closes":@(fileLifecycleCloses),@"replies":replies,@"contents":[NSData dataWithContentsOfFile:path]};
}
static void fileLifecycleModeCases(NSString *path){
    NSArray *modes=@[@"r",@"rb",@"r+",@"rb+",@"w",@"wb",@"w+",@"wb+",@"a",@"ab",@"a+",@"ab+",@"r+b",@"w+b",@"a+b",
        @" R+B \r\n",@"\u2003WB+\u2003",@"",@"bad",@"r++",@"w_bad",@"r\0tail",@"ảnh",@"ｗ",[NSNull null]];
    for(id input in modes){
        @autoreleasepool{
            NSString *mode=input==[NSNull null]?nil:(NSString *)input;
            FILE_LIFECYCLE_REQUIRE(TLinkJSFileModeIsValid(mode)==LegacyTLinkJSFileModeIsValid(mode));
            FILE_LIFECYCLE_REQUIRE(TLinkJSFileModeWrites(mode)==LegacyTLinkJSFileModeWrites(mode));
            NSDictionary *before=fileLifecycleModeTrace(true,path,mode),*actual=fileLifecycleModeTrace(false,path,mode);
            FILE_LIFECYCLE_REQUIRE([before isEqual:actual]);
        }
    }
    for(bool legacy:{true,false}){
        @autoreleasepool{
            fileReset();TLinkAXFixtureResetOwners();fileLifecycleMeasure=fileLifecycleTextPools=true;
            TLinkJSFileHandle *handle=fileOpen(legacy,path,@"r+",128);
            FILE_LIFECYCLE_REQUIRE(fileLifecycleNormalizations==(legacy?3U:1U));
            FILE_LIFECYCLE_REQUIRE(TLinkAXFixtureCreatedOwners()==(legacy?3U:1U)&&TLinkAXFixtureLiveOwners()==(legacy?3U:0U));
            fileLifecycleMeasure=fileLifecycleTextPools=false;[handle close];
        }
        FILE_LIFECYCLE_REQUIRE(fileFDs.empty()&&TLinkAXFixtureLiveOwners()==0);
    }
}
static void fileLifecycleSeekCases(NSString *path){
    NSArray *whences=@[@"set",@"start",@"cur",@"current",@"end",@" CUR \n",@"\u2003END\u2003",@"",@"bad",@"cur\0tail",@"ảnh",[NSNull null]];
    for(id input in whences){
        NSString *whence=input==[NSNull null]?nil:(NSString *)input;
        for(long long offset:{-1LL,0LL,2LL,LLONG_MAX}){
            NSArray *expected=nil;
            for(bool legacy:{true,false}){
                @autoreleasepool{
                    fileReset();TLinkJSFileHandle *handle=fileOpen(legacy,path,@"r+",128);fileLifecycleMeasure=true;
                    NSDictionary *reply=[handle seekWhence:whence offset:offset];const unsigned normalizations=fileLifecycleSeekNormalizations;
                    fileLifecycleMeasure=false;
                    NSArray *trace=@[reply,[handle tell],[handle close]];
                    const BOOL canonical=[@[@"set",@"start",@"cur",@"current",@"end"] containsObject:whence?:@""];
                    FILE_LIFECYCLE_REQUIRE(normalizations==(legacy||!canonical?1U:0U));
                    if(legacy)expected=trace;else FILE_LIFECYCLE_REQUIRE([expected isEqual:trace]);
                }
                FILE_LIFECYCLE_REQUIRE(fileFDs.empty());
            }
        }
    }
}
static void fileLifecycleFaultCases(NSString *root,NSString *path){
    // No allocated descriptor exists for a directly initialized, unopened object.
    fileReset();@autoreleasepool{
        TLinkJSFileHandle *empty=[TLinkJSFileHandle new];
        FILE_LIFECYCLE_REQUIRE(empty.isClosed&&empty.path&&empty.mode&&![[empty readRequest:@0][@"ok"] boolValue]);
        FILE_LIFECYCLE_REQUIRE([[empty close][@"alreadyClosed"] boolValue]);
    }
    FILE_LIFECYCLE_REQUIRE(fileLifecycleOpenCalls==0&&fileLifecycleCloses==0&&fileFDs.empty());
    for(unsigned scenario=0;scenario<27;++scenario){
        TLinkJSFileHandle *replacement=nil;
        @autoreleasepool{
            fileReset();NSString *candidate=path,*mode=@"r+";Class klass=[FileLifecycleFaultHandle class];
            if(scenario<20){
                fileLifecycleStage=scenario/2+1;fileLifecycleThrow=scenario%2+1;
                if(fileLifecycleStage<=3){candidate=[root stringByAppendingPathComponent:[NSString stringWithFormat:@"construct-%u.bin",scenario]];mode=@"w";}
                if(fileLifecycleStage==4)mode=@"a";
            }else if(scenario<23)fileLifecycleFactoryFault=scenario-19;
            else if(scenario==23)klass=[FileLifecycleNilHandle class];
            else if(scenario<26)fileLifecycleInitFault=scenario-23;
            else{fileLifecycleStage=4;fileLifecycleThrow=3;mode=@"a";}
            NSString *error=nil;unsigned caught=0;
            TLinkJSFileHandle *handle=fileLifecycleTryOpen(klass,candidate,mode,&error,caught);
            FILE_LIFECYCLE_REQUIRE(!handle&&fileLifecycleOpenCalls==1&&fileLifecycleCloses==1&&fileFDs.empty());
            if(scenario==20||scenario==23)FILE_LIFECYCLE_REQUIRE(!caught&&[error hasPrefix:@"file_open_failed errno="]);
            else if(scenario==26)FILE_LIFECYCLE_REQUIRE(!caught&&[error hasPrefix:@"file_seek_failed errno="]);
            else FILE_LIFECYCLE_REQUIRE(caught==((scenario<20)?scenario%2+1:(scenario<23?scenario-20:scenario-23)));
            fileReset();replacement=fileOpen(false,path,@"r+",128);
        }
        // Caller-pool retirement of partial objects cannot close a replacement.
        struct stat info;FILE_LIFECYCLE_REQUIRE(fileFDs.size()==1&&::fstat(fileLastFD,&info)==0);
        [replacement close];FILE_LIFECYCLE_REQUIRE(fileFDs.empty());
    }
    for(unsigned n=0;n<64;++n){
        @autoreleasepool{
            fileReset();fileLifecycleStage=7;fileLifecycleThrow=n%2+1;NSString *error=nil;unsigned caught=0;
            FILE_LIFECYCLE_REQUIRE(!fileLifecycleTryOpen([FileLifecycleFaultHandle class],path,@"r+",&error,caught)&&caught==n%2+1&&fileFDs.empty()&&fileLifecycleCloses==1);
        }
    }
}
static void fileLifecyclePoolCases(NSString *path){
    for(unsigned operation=0;operation<3;++operation){
        for(bool fault:{false,true}){
            NSDictionary *expected=nil;
            for(bool legacy:{true,false}){
                NSDictionary *held=nil;
                @autoreleasepool{
                    fileReset();TLinkJSFileHandle *handle=fileOpen(legacy,path,@"r+",128);TLinkAXFixtureResetOwners();fileLifecyclePools=true;
                    fileLifecycleSeekFault=fault&&operation==0;fileLifecycleSyncFault=fault&&operation==1;fileLifecycleCloseFault=fault&&operation==2;
                    if(operation==0)held=[handle seekWhence:@"cur" offset:0];
                    if(operation==1)held=[handle flush];
                    if(operation==2)held=[handle close];
                    FILE_LIFECYCLE_REQUIRE(TLinkAXFixtureCreatedOwners()==1&&TLinkAXFixtureLiveOwners()==(legacy?1U:0U));
                    fileLifecyclePools=fileLifecycleSeekFault=fileLifecycleSyncFault=fileLifecycleCloseFault=false;
                    [handle close];
                }
                FILE_LIFECYCLE_REQUIRE(held&&fileFDs.empty()&&TLinkAXFixtureLiveOwners()==0);
                if(legacy)expected=held;else FILE_LIFECYCLE_REQUIRE([expected isEqual:held]);
            }
        }
    }
}
static void fileLifecycleRuntimeCases(NSString *root,NSString *path){
    fputs("File lifecycle Foundation: complete actual/frozen classes, single mode preparation and scoped descriptor handoff\n",stderr);
    fileLifecycleModeCases(path);fileLifecycleSeekCases(path);fileLifecycleFaultCases(root,path);fileLifecyclePoolCases(path);fileReset();
    puts("File lifecycle passed: frozen mode/flags/file/reply and seek parity, open normalization3 versus1, canonical seek normalization0 versus1, 27 construction fault stages, safe unopened init, caller-pool replacement safety, 64 fault recoveries and owned seek/flush/close success/error pools. Device allocation/latency remains unqualified.");
}
#undef FILE_LIFECYCLE_REQUIRE
