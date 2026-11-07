static unsigned fileOwnerLive=0,fileEncodingCalls=0;
static bool fileForceFallback=false;
@interface FilePayloadString:NSString{
@public NSString *backing;char *ownedBytes;NSUInteger count;
}
-(instancetype)initWithText:(NSString *)text;
@end
@implementation FilePayloadString
-(instancetype)initWithText:(NSString *)text{
    self=[super init];if(self){backing=[text copy];NSData *data=[backing dataUsingEncoding:NSUTF8StringEncoding];count=data.length;ownedBytes=(char *)malloc(count+1);assert(ownedBytes);if(count)memcpy(ownedBytes,data.bytes,count);ownedBytes[count]=0;++fileOwnerLive;}return self;
}
-(NSUInteger)length{return backing.length;}
-(unichar)characterAtIndex:(NSUInteger)index{return [backing characterAtIndex:index];}
-(void)getCharacters:(unichar *)buffer range:(NSRange)range{[backing getCharacters:buffer range:range];}
-(id)copyWithZone:(NSZone *)zone{(void)zone;return self;}
-(NSUInteger)lengthOfBytesUsingEncoding:(NSStringEncoding)encoding{return [backing lengthOfBytesUsingEncoding:encoding];}
-(NSData *)dataUsingEncoding:(NSStringEncoding)encoding{++fileEncodingCalls;return [backing dataUsingEncoding:encoding];}
-(void)dealloc{assert(fileOwnerLive);--fileOwnerLive;free(ownedBytes);}
@end
static const char *fileUTF8Pointer(CFStringRef string,CFStringEncoding encoding){
    if(fileForceFallback)return NULL;
    NSString *value=(__bridge NSString *)string;
    if([value isKindOfClass:[FilePayloadString class]])return ((FilePayloadString *)value)->ownedBytes;
    return CFStringGetCStringPtr(string,encoding);
}
static FileTrace filePayloadTrace(bool legacy,NSString *path,unsigned scenario){
    fileReset();assert([[@"abc\0def\nảnh 测试\r\nmore" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES]);
    TLinkJSFileHandle *handle=fileOpen(legacy,path,@"r+",128);fileMaxRead=3;fileInterrupts=2;if(scenario==1)fileFaultAt=5;
    NSMutableArray *trace=[NSMutableArray array];
    for(id request in @[@0,@3,@"all",@"*a"]){[trace addObject:[handle readRequest:request]];[trace addObject:[handle tell]];}
    [trace addObject:@(fileReads)];fileFaultAt=-1;[handle seekWhence:@"set" offset:0];fileMaxWrite=3;fileWriteInterrupts=2;
    if(scenario==2)fileWriteFaultAt=5;if(scenario==3)fileZeroWrite=true;
    [trace addObject:[handle writeText:@"123456789"]];[trace addObject:[handle tell]];
    [trace addObject:[handle writeBase64:@"YWIAYw=="]];[trace addObject:[handle tell]];[trace addObject:@(fileWrites)];
    fileWriteFaultAt=-1;fileZeroWrite=false;[trace addObject:[handle writeText:@"recovery"]];[trace addObject:[handle close]];
    assert(fileFDs.empty());return {[trace copy],[NSData dataWithContentsOfFile:path],fileReads};
}
static void filePayloadUTF8Cases(NSString *path){
    for(bool fallback:{false,true}){
        for(NSString *text in @[@"",@"ASCII",@"ảnh 测试 😀",@"a\0b",@"\ufeffjson"]){
            NSArray *expected=nil;NSData *expectedBytes=nil;
            for(bool legacy:{true,false}){
                @autoreleasepool{
                    fileReset();fileForceFallback=fallback;fileEncodingCalls=0;
                    TLinkJSFileHandle *handle=fileOpen(legacy,path,@"w+",1024);
                    FilePayloadString *owner=[[FilePayloadString alloc] initWithText:text];
                    NSDictionary *reply=[handle writeText:owner];[handle close];
                    assert([reply[@"ok"] boolValue]&&fileEncodingCalls==((legacy||fallback)?1U:0U));
                    NSData *bytes=[NSData dataWithContentsOfFile:path];
                    if(legacy){expected=@[reply];expectedBytes=bytes;}else assert([expected isEqual:@[reply]]&&[expectedBytes isEqual:bytes]);
                    owner=nil;
                }
                assert(fileOwnerLive==0&&fileFDs.empty());
            }
        }
    }
    fileForceFallback=false;
}
static void filePayloadPoolCases(NSString *path){
    for(unsigned operation=0;operation<4;++operation){
        for(bool legacy:{true,false}){
            NSDictionary *held=nil;
            @autoreleasepool{
                fileReset();TLinkAXFixtureResetOwners();assert([[@"one\ntwo" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES]);
                TLinkJSFileHandle *handle=fileOpen(legacy,path,@"r+",1024);fileTrackPools=true;
                if(operation==0)held=[handle readRequest:@"*a"];
                else if(operation==1)held=[handle readLine];
                else if(operation==2)held=[handle writeText:@"text"];
                else held=[handle writeBase64:@"dGV4dA=="];
                assert([held[@"ok"] boolValue]&&TLinkAXFixtureCreatedOwners()>0);
                assert(legacy?TLinkAXFixtureLiveOwners()>0:TLinkAXFixtureLiveOwners()==0);
                fileTrackPools=false;[handle close];
            }
            assert(TLinkAXFixtureLiveOwners()==0&&TLinkAXFixtureCreatedOwners()==TLinkAXFixtureDroppedOwners()&&fileFDs.empty()&&[held[@"ok"] boolValue]);
            if(operation<2)assert([held[@"data"] length]>0&&[held[@"base64"] length]>0);
        }
    }
}
static void filePayloadCodecCases(NSString *path){
    const unichar invalid=0xd800;NSString *badUTF16=[[NSString alloc] initWithCharacters:&invalid length:1];
    for(NSString *mode in @[@"r",@"r+",@"w+"]){
        for(bool closed:{false,true}){
            for(NSArray *input in @[@[@"12345678",@"MTIzNDU2Nzg="],@[@"123456789",@"MTIzNDU2Nzg5"],@[@"ảnh",@"!!!!"],@[@"a\0b",@""],@[badUTF16,@"YQ==\n"]]){
                NSArray *expected=nil;NSData *expectedBytes=nil;
                for(bool legacy:{true,false}){
                    @autoreleasepool{
                        fileReset();assert([[@"initial" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES]);TLinkJSFileHandle *handle=fileOpen(legacy,path,mode,8);
                        if(closed)[handle close];
                        NSArray *reply=@[[handle writeText:input[0]],[handle writeBase64:input[1]],[handle tell],[handle close]];NSData *bytes=[NSData dataWithContentsOfFile:path];
                        if(legacy){expected=reply;expectedBytes=bytes;}else assert([expected isEqual:reply]&&[expectedBytes isEqual:bytes]);
                    }
                    assert(fileFDs.empty());
                }
            }
        }
    }
}
static void filePayloadFaultCases(NSString *path){
    for(bool reading:{false,true}){
        for(unsigned kind:{1U,2U}){
            @autoreleasepool{
                fileReset();TLinkAXFixtureResetOwners();assert([[@"abc" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES]);
                TLinkJSFileHandle *handle=fileOpen(false,path,@"r+",1024);fileTrackPools=true;fileIOThrow=kind;bool caught=false;
                @try{try{if(reading)[handle readRequest:@"*a"];else [handle writeText:@"abc"];}catch(const std::runtime_error &){caught=kind==2;}}
                @catch(NSException *exception){caught=kind==1&&[exception.name isEqual:@"FilePayloadFixture"];}
                assert(caught);fileIOThrow=0;fileTrackPools=false;
                NSDictionary *reply=reading?[handle readRequest:@"*a"]:[handle writeText:@"abc"];
                assert([reply[@"ok"] boolValue]);[handle close];
            }
            assert(TLinkAXFixtureLiveOwners()==0&&fileFDs.empty());
        }
    }
    fileReset();assert([[@"abc" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES]);TLinkJSFileHandle *handle=fileOpen(false,path,@"r+",1024);
    fileReadOverrun=true;assert(![[handle readRequest:@3][@"ok"] boolValue]);fileReadOverrun=false;
    fileWriteOverrun=true;assert(![[handle writeText:@"abc"][@"ok"] boolValue]);fileWriteOverrun=false;
    assert([[handle tell][@"offset"] longLongValue]==0&&[[handle writeText:@"abc"][@"ok"] boolValue]);[handle close];assert(fileFDs.empty());
}
static void filePayloadRuntimeCases(NSString *path){
    puts("File payload Foundation: complete shared class, real POSIX/UTF8/base64 and explicit MRC operation temporaries");
    for(unsigned scenario=0;scenario<4;++scenario){
        const auto old=filePayloadTrace(true,path,scenario),current=filePayloadTrace(false,path,scenario);
        assert([old.results isEqual:current.results]&&[old.contents isEqual:current.contents]&&old.reads==current.reads);
    }
    filePayloadUTF8Cases(path);filePayloadCodecCases(path);filePayloadPoolCases(path);filePayloadFaultCases(path);
    assert(fileOwnerLive==0&&fileFDs.empty());
    puts("File payload Foundation passed: frozen replies/positions/bytes and syscall counts, short/EINTR/EIO/zero writes, borrowed/fallback UTF8, four normal operation pools, held results, NS/C++ recovery and invalid read/write refusal. Foundation allocation/device performance remains unqualified.");
}
