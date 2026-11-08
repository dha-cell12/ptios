static TLinkJSFileHandle *fileBeforeReadStorageOpen(NSString *path,NSUInteger cap){
    NSString *error=nil;fileOpening=true;
    BeforeReadStorageTLinkJSFileHandle *handle=[BeforeReadStorageTLinkJSFileHandle openPath:path mode:@"r" handleId:1 maxTransferBytes:cap error:&error];
    fileOpening=false;assert(handle&&!error);return (TLinkJSFileHandle *)handle;
}
static NSDictionary *fileRawReadEntry(TLinkJSFileHandle *handle,unsigned entry,NSUInteger cap){
    if(entry==9)return [handle readLine];
    id request=entry%3==0?(id)@(cap):(entry%3==1?(id)@"all":(id)@"line");
    if(entry<3)return [handle readRequest:request];
    if(entry<6)return [handle readTextRequest:request];
    return [handle readBase64Request:request];
}
static NSDictionary *fileRawReadTrace(bool before,NSString *path,NSData *bytes,NSUInteger cap,unsigned entry,unsigned scenario){
    fileReset();assert([bytes writeToFile:path atomically:YES]);
    TLinkJSFileHandle *handle=before?fileBeforeReadStorageOpen(path,cap):fileOpen(false,path,@"r",cap);
    if(scenario==1){fileMaxRead=257;fileInterrupts=2;}
    if(scenario==2)fileFaultAt=2;
    if(scenario==3)fileReadOverrun=true;
    NSDictionary *reply=nil;
    @autoreleasepool {reply=fileRawReadEntry(handle,entry,cap);}
    NSDictionary *position=[handle tell];[handle close];assert(fileFDs.empty());
    return @{@"reply":reply,@"position":position,@"reads":@(fileReads),@"rewinds":@(fileRewinds)};
}
static void fileRawDataLifetimeCases(){
    const std::string payload="owned raw read bytes";
    for(unsigned mode:{0U,1U,2U,3U,4U,5U}){
        fileRawTrack=true;fileRawFactoryFault=mode;fileRawFactories=0;fileRawOwner.reset();
        NSData *held=nil;bool objcThrown=false,cppThrown=false;
        @autoreleasepool {
            TLinkJSFileReadStorage::Buffer storage(65536);
            uint8_t *bytes=storage.destination(0,payload.size());assert(bytes);memcpy(bytes,payload.data(),payload.size());
            @try {try {held=TLinkJSFileReadFinish(std::move(storage),payload.size());}
                catch(const std::runtime_error &){cppThrown=true;}}
            @catch(NSException *exception){assert([exception.name isEqual:@"FileReadStorageFixture"]);objcThrown=true;}
            assert((held!=nil)==(mode==0||mode==5));
            assert(fileRawFactories==1&&objcThrown==(mode==3)&&cppThrown==(mode==4));
            assert(!TLinkJSFileReadFinish(std::move(storage),0));
        }
        @autoreleasepool {
            if(held){assert(held.length==payload.size());assert(memcmp(held.bytes,payload.data(),payload.size())==0);}
            held=nil;
        }
        assert(fileRawOwner.expired());fileRawFactoryFault=0;fileRawTrack=false;
    }
    fileRawTrack=true;fileRawFactories=0;fileRawOwner.reset();
    @autoreleasepool {
        TLinkJSFileReadStorage::Buffer empty(0);NSData *data=TLinkJSFileReadFinish(std::move(empty),0);
        assert(data&&data.length==0&&fileRawFactories==1);
    }
    assert(fileRawOwner.expired());fileRawTrack=false;
}
static void fileRawFactoryFaultCases(NSString *path){
    NSData *body=[@"abc\r\nremaining" dataUsingEncoding:NSUTF8StringEncoding];
    for(unsigned entry:{0U,1U,2U,3U,4U,5U,6U,7U,8U,9U}){
        NSDictionary *expected=fileRawReadTrace(true,path,body,64,entry,0);
        for(unsigned fault=1;fault<=5;++fault){
            fileReset();assert([body writeToFile:path atomically:YES]);
            TLinkJSFileHandle *handle=fileOpen(false,path,@"r",64);
            fileRawTrack=true;fileRawFactoryFault=fault;fileRawFactories=0;fileRawOwner.reset();
            fileRepresentationDecodes=fileRepresentationEncodes=0;
            bool objcThrown=false,cppThrown=false;
            @autoreleasepool {
                NSDictionary *reply=nil;
                @try {try {reply=fileRawReadEntry(handle,entry,64);}
                    catch(const std::runtime_error &){cppThrown=true;}}
                @catch(NSException *exception){assert([exception.name isEqual:@"FileReadStorageFixture"]);objcThrown=true;}
                assert(fileRawFactories==1&&objcThrown==(fault==3)&&cppThrown==(fault==4));
                if(fault==5){assert([reply isEqual:expected[@"reply"]]);}
                else {
                    assert(fileRepresentationDecodes==0&&fileRepresentationEncodes==0);
                    if(fault<=2)assert(![reply[@"ok"] boolValue]&&[reply[@"error"] hasPrefix:@"file_read_failed errno="]);
                }
                assert([[handle tell] isEqual:expected[@"position"]]&&fileReads==[expected[@"reads"] unsignedLongLongValue]&&fileRewinds==[expected[@"rewinds"] unsignedLongLongValue]);
                reply=nil;
            }
            fileRawTrack=false;fileRawFactoryFault=0;
            assert(fileRawOwner.expired());[handle close];assert(fileFDs.empty());
        }
    }
}
static void fileReadStorageRuntimeCases(NSString *path){
    puts("File raw reads Foundation: complete preceding/current classes, real POSIX IO and sealed NSData owners");fflush(stdout);
    const std::string medium=std::string(8193,'x')+"\r\nremaining";
    const std::string large=std::string(524289,'x')+"\r\nremaining";
    NSArray<NSData *> *inputs=@[[NSData data],[@"\r\nrest" dataUsingEncoding:NSUTF8StringEncoding],
        [@"ảnh\0测试😀\r\nnext" dataUsingEncoding:NSUTF8StringEncoding],
        [NSData dataWithBytes:medium.data() length:medium.size()],
        [NSData dataWithBytes:large.data() length:large.size()]];
    unsigned comparisons=0;
    for(NSData *body in inputs){
        for(NSUInteger cap:{NSUInteger(1),NSUInteger(129),NSUInteger(524288)}){
            for(unsigned entry=0;entry<10;++entry){
                for(unsigned scenario=0;scenario<4;++scenario){
                    @autoreleasepool {
                        NSDictionary *before=fileRawReadTrace(true,path,body,cap,entry,scenario);
                        NSDictionary *now=fileRawReadTrace(false,path,body,cap,entry,scenario);
                        if(![before isEqual:now])fprintf(stderr,"File raw read mismatch: cap=%lu entry=%u scenario=%u before=%.2048s now=%.2048s\n",(unsigned long)cap,entry,scenario,[before.description UTF8String]?:"<unencodable>",[now.description UTF8String]?:"<unencodable>");
                        assert([before isEqual:now]);++comparisons;
                    }
                }
            }
        }
    }
    assert(comparisons==600);
    fileRawDataLifetimeCases();fileRawFactoryFaultCases(path);
    fileReset();assert(!fileRawTrack&&!fileRawFactoryFault&&fileRawOwner.expired()&&fileFDs.empty());
    puts("File raw reads passed: 600 complete frozen numeric/all/line/text/base64 replies, exact cursor/syscall/rewind and limits, CR/chunk/Unicode/NUL/EOF/IO/over-return cases, 50 accepted factory failure/copy/NS/C++ outcomes without replay, detached NSData across pools and zero final owners. Foundation internal copies/device performance remain unqualified.");
}
