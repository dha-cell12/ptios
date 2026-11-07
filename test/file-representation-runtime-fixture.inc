// Compare new opt-in representations to projections of the complete frozen
// reader. File bytes, offsets, read/rewind calls and errors stay authoritative.
static NSDictionary *fileRepresentationProjection(NSDictionary *reply,unsigned representation){
    if(![reply[@"ok"] boolValue]||representation==0)return reply;
    NSMutableDictionary *result=[reply mutableCopy];
    if(representation==1)[result removeObjectForKey:@"base64"];
    else {
        [result removeObjectForKey:@"data"];[result removeObjectForKey:@"line"];
        result[@"encoding"]=@"base64";
    }
    return result;
}
static NSDictionary *fileRepresentationRun(bool legacy,NSString *path,NSData *bytes,id request,
                                          NSUInteger cap,unsigned representation,unsigned scenario){
    fileReset();assert([bytes writeToFile:path atomically:YES]);
    fileStatFails=scenario==3;
    TLinkJSFileHandle *handle=fileOpen(legacy,path,scenario==5?@"w":@"r",cap);
    if(scenario==1){fileMaxRead=3;fileInterrupts=2;}
    if(scenario==2)fileFaultAt=2;
    if(scenario==4)fileRewindFails=true;
    if(scenario==6)[handle close];
    fileRepresentationDecodes=fileRepresentationEncodes=0;
    NSDictionary *reply=nil;
    @autoreleasepool {
        if(legacy||representation==0)reply=[handle readRequest:request];
        else if(representation==1)reply=[handle readTextRequest:request];
        else reply=[handle readBase64Request:request];
    }
    if(!legacy){
        const bool ok=[reply[@"ok"] boolValue];
        assert(fileRepresentationDecodes==(ok&&representation!=2?1U:0U));
        assert(fileRepresentationEncodes==(ok&&representation!=1?1U:0U));
    }
    NSDictionary *position=[handle tell];[handle close];
    assert(fileFDs.empty());
    return @{@"reply":reply,@"position":position,@"reads":@(fileReads),@"rewinds":@(fileRewinds)};
}
static void fileRepresentationParityCases(NSString *path){
    const uint8_t raw[]={0,0xff,0xfe,'a','\r','\n','z'};
    NSMutableArray *inputs=[NSMutableArray arrayWithArray:@[
        [NSData data],[@"\n\r\nlast\r" dataUsingEncoding:NSUTF8StringEncoding],
        [@"ảnh\0测试😀\r\nsecond\n" dataUsingEncoding:NSUTF8StringEncoding],
        [NSData dataWithBytes:raw length:sizeof(raw)]]];
    const std::string large=std::string(512*1024,'x')+"\nlast";
    [inputs addObject:[NSData dataWithBytes:large.data() length:large.size()]];
    NSArray *requests=@[@0,@1,@3,@8,@"*a",@"all",@"",@"line",@"*l",@"bad",@(-1),[NSNull null]];
    for(NSData *bytes in inputs){
        for(NSUInteger cap:{NSUInteger(1),NSUInteger(8),NSUInteger(512*1024)}){
            for(id request in requests){
                for(unsigned scenario=0;scenario<7;++scenario){@autoreleasepool {
                    NSDictionary *old=fileRepresentationRun(true,path,bytes,request,cap,0,scenario);
                    for(unsigned representation=0;representation<3;++representation){
                        NSDictionary *now=fileRepresentationRun(false,path,bytes,request,cap,representation,scenario);
                        NSMutableDictionary *expected=[old mutableCopy];
                        expected[@"reply"]=fileRepresentationProjection(old[@"reply"],representation);
                        const bool same=[expected isEqual:now];
                        if(!same){fprintf(stderr,"File representation parity: %s\n",[NSString stringWithFormat:@"rep=%u cap=%lu scenario=%u request=%@ expected=%@ actual=%@",representation,(unsigned long)cap,scenario,request,expected,now].UTF8String);}
                        assert(same);
                    }
                }}
            }
        }
    }
}
static void fileRepresentationFaultCases(NSString *path){
    for(unsigned representation=1;representation<=2;++representation){
        for(unsigned fault=1;fault<=2;++fault){
            fileReset();assert([[@"first\nnext" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES]);
            TLinkJSFileHandle *handle=fileOpen(false,path,@"r",1024);
            // An unused codec must never be called, even if it would throw.
            fileRepresentationDecodeFault=representation==2?fault:0;
            fileRepresentationEncodeFault=representation==1?fault:0;
            NSDictionary *held=nil;
            @autoreleasepool {
                TLinkAXFixtureResetOwners();fileRepresentationPools=true;
                held=representation==1?[handle readTextRequest:@"line"]:[handle readBase64Request:@"line"];
                fileRepresentationPools=false;
                assert([held[@"ok"] boolValue]&&TLinkAXFixtureCreatedOwners()==1&&TLinkAXFixtureLiveOwners()==0);
            }
            assert([held[@"bytes"] unsignedIntegerValue]==5&&[[handle tell][@"offset"] unsignedIntegerValue]==6);
            [handle seekWhence:@"set" offset:0];
            fileRepresentationDecodeFault=representation==1?fault:0;
            fileRepresentationEncodeFault=representation==2?fault:0;
            bool caught=false;
            @autoreleasepool {
                TLinkAXFixtureResetOwners();fileRepresentationPools=true;
                @try {try {
                    if(representation==1)(void)[handle readTextRequest:@3];
                    else (void)[handle readBase64Request:@3];
                }catch(const std::runtime_error &){caught=true;}}
                @catch(NSException *exception){assert([exception.name isEqual:@"FileRepresentationFixture"]);caught=true;}
                fileRepresentationPools=false;
            }
            fileRepresentationDecodeFault=fileRepresentationEncodeFault=0;
            assert(caught&&TLinkAXFixtureLiveOwners()==0&&[[handle tell][@"offset"] intValue]==3);
            held=representation==1?[handle readTextRequest:@"*a"]:[handle readBase64Request:@"*a"];
            assert([held[@"ok"] boolValue]);[handle close];assert(fileFDs.empty());
        }
    }
    // The reader still owns syscall failures/unwind before any codec starts.
    for(unsigned representation=1;representation<=2;++representation){
        for(unsigned fault=1;fault<=2;++fault){
            fileReset();assert([[@"one\ntwo" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES]);
            TLinkJSFileHandle *handle=fileOpen(false,path,@"r",1024);fileIOThrow=fault;
            fileRepresentationDecodes=fileRepresentationEncodes=0;bool caught=false;
            @autoreleasepool {
                @try {try {
                    if(representation==1)(void)[handle readTextRequest:@"*l"];
                    else (void)[handle readBase64Request:@"*l"];
                }catch(const std::runtime_error &){caught=true;}}
                @catch(NSException *exception){assert([exception.name isEqual:@"FilePayloadFixture"]);caught=true;}
            }
            fileIOThrow=0;
            assert(caught&&!fileRepresentationDecodes&&!fileRepresentationEncodes&&[[handle tell][@"offset"] intValue]==0);
            [handle close];assert(fileFDs.empty());
        }
    }
}
static void fileRepresentationJSAndPipeCases(NSString *path){
    fileReset();int fds[2];assert(::pipe(fds)==0);
    assert(::write(fds[1],"one\r\ntwo",8)==8&&::close(fds[1])==0);fileInjected=fds[0];
    TLinkJSFileHandle *pipeHandle=fileOpen(false,@"representation-pipe",@"r",1024);
    NSDictionary *line=[pipeHandle readTextRequest:@"*l"];
    assert([line[@"line"] isEqual:@"one"]&&!line[@"base64"]);
    NSDictionary *rest=[pipeHandle readBase64Request:@"*a"];
    assert([rest[@"base64"] isEqual:@"dHdv"]&&[rest[@"eof"] boolValue]&&!rest[@"data"]&&!rest[@"line"]);
    [pipeHandle close];assert(fileFDs.empty());
    for(unsigned n=0;n<64;++n){@autoreleasepool {
        fileReset();assert([[@"ảnh\0line\r\nnext" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES]);
        TLinkJSFileHandle *handle=fileOpen(false,path,@"r",1024);JSContext *context=[JSContext new];
        @autoreleasepool {context[@"file"]=TLinkJSFileHandleCreateJSObject(context,handle,nil);}
        for(NSString *method in @[@"readText",@"readBase64"]){
            for(NSString *request in @[@"",@"undefined",@"null",@"0",@"3",@"'line'",@"'*a'",@"'invalid'"]){
                [handle seekWhence:@"set" offset:0];NSDictionary *old=[handle readRequest:([request isEqual:@"0"]?@0:[request isEqual:@"3"]?@3:[request isEqual:@"'line'"]?@"line":[request isEqual:@"'invalid'"]?@"invalid":@"*a")];
                [handle seekWhence:@"set" offset:0];
                NSString *script=[NSString stringWithFormat:@"file.%@(%@)",method,request];
                NSDictionary *reply=[[context evaluateScript:script] toDictionary];
                const unsigned representation=[method isEqual:@"readText"]?1:2;
                assert([reply isEqual:fileRepresentationProjection(old,representation)]&&!context.exception);
            }
        }
        [context evaluateScript:@"file.close()"];assert(!context.exception&&fileFDs.empty());context[@"file"]=nil;
    }}
}
static void fileRepresentationRuntimeCases(NSString *path){
    puts("File selected reads Foundation: actual shared POSIX reader, frozen reply projections and real JSCore");fflush(stdout);
    fileRepresentationParityCases(path);fileRepresentationFaultCases(path);fileRepresentationJSAndPipeCases(path);
    assert(fileFDs.empty()&&!fileRepresentationPools&&!fileRepresentationDecodeFault&&!fileRepresentationEncodeFault);
    puts("File selected reads passed: 3780 frozen byte/line/limit/error/offset/syscall cases with three representations, zero unused codec calls, exact 512-KiB bounds, binary/Unicode/NUL/CR/EOF, pipe, codec/syscall NS/C++ unwind, held results, real JSCore defaults and 64 balanced lifecycles. Legacy read replies remain complete; device memory/latency pending.");
}
