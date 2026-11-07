static NSDictionary *fileLineFillRead(TLinkJSFileHandle *handle,unsigned entry){
    if(entry==0)return [handle readLine];
    if(entry==1)return [handle readRequest:@"*l"];
    if(entry==2)return [handle readTextRequest:@"line"];
    return [handle readBase64Request:@"*l"];
}
static NSDictionary *fileLineFillTrace(bool before,NSString *path,NSData *bytes,NSUInteger cap,unsigned entry,unsigned scenario){
    fileReset();assert([bytes writeToFile:path atomically:YES]);fileStatFails=scenario==3;
    TLinkJSFileHandle *handle=before?filePreviousLineOpen(path,@"r",cap):fileOpen(false,path,@"r",cap);
    if(scenario==1){fileMaxRead=3;fileInterrupts=2;}if(scenario==2)fileFaultAt=2;
    fileRewindFails=scenario==4;fileLineTrack=!before;fileLineGrows=0;
    fileRepresentationDecodes=fileRepresentationEncodes=0;
    NSDictionary *reply=nil;
    @autoreleasepool {reply=fileLineFillRead(handle,entry);}
    fileLineTrack=false;
    if(!before){
        assert(fileLineGrows==fileReads);
        const bool ok=[reply[@"ok"] boolValue];
        assert(fileRepresentationDecodes==(ok&&entry!=3?1U:0U));
        assert(fileRepresentationEncodes==(ok&&entry!=2?1U:0U));
    }
    if([reply[@"ok"] boolValue]){
        assert([reply isKindOfClass:[NSMutableDictionary class]]);
        NSMutableDictionary *mutableReply=(NSMutableDictionary *)reply;
        mutableReply[@"fixture"]=@"held";[mutableReply removeObjectForKey:@"fixture"];
        if(entry!=3)assert(reply[@"data"]==reply[@"line"]);
    }
    NSDictionary *position=[handle tell];[handle close];assert(fileFDs.empty());
    return @{@"reply":reply,@"position":position,@"reads":@(fileReads),@"rewinds":@(fileRewinds)};
}
static void fileLineFillRuntimeCases(NSString *path){
    puts("Direct line Foundation: preceding/current complete classes, actual NSData read destinations and mutable final replies");fflush(stdout);
    unsigned comparisons=0;
    for(NSUInteger length:{NSUInteger(0),NSUInteger(1),NSUInteger(127),NSUInteger(128),NSUInteger(129),NSUInteger(8191),NSUInteger(8192),NSUInteger(8321),NSUInteger(524287)}){
        std::string body(length,'x');body+="\r\nremaining";
        NSData *bytes=[NSData dataWithBytes:body.data() length:body.size()];
        for(NSUInteger cap:{NSUInteger(1),NSUInteger(129),NSUInteger(524288)}){
            for(unsigned entry=0;entry<4;++entry){
                for(unsigned scenario=0;scenario<5;++scenario){@autoreleasepool {
                    NSDictionary *old=fileLineFillTrace(true,path,bytes,cap,entry,scenario);
                    NSDictionary *now=fileLineFillTrace(false,path,bytes,cap,entry,scenario);
                    assert([old isEqual:now]);++comparisons;
                }}
            }
        }
    }
    assert(comparisons==540);
    for(unsigned fault=1;fault<=2;++fault){
        fileReset();assert([[@"abc\nrest" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES]);
        TLinkJSFileHandle *handle=fileOpen(false,path,@"r",1024);
        fileLineTrack=true;fileLineGrows=0;fileLineGrowFault=fault;bool caught=false;
        @autoreleasepool {
            @try {try {(void)[handle readLine];}catch(const std::runtime_error &){caught=true;}}
            @catch(NSException *exception){assert([exception.name isEqual:@"FileLineGrowFixture"]);caught=true;}
        }
        fileLineTrack=false;fileLineGrowFault=0;
        assert(caught&&fileReads==1&&fileLineGrows==2&&[[handle tell][@"offset"] intValue]==1);
        NSDictionary *recovered=[handle readTextRequest:@"*l"];
        assert([recovered[@"line"] isEqual:@"bc"]&&[[handle tell][@"offset"] intValue]==4);
        [handle close];assert(fileFDs.empty());
    }
    // Legacy line codec ordering stays decode-before-base64 on failures too.
    for(unsigned stage=0;stage<2;++stage){
        fileReset();assert([[@"abc\nrest" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES]);
        TLinkJSFileHandle *handle=fileOpen(false,path,@"r",1024);
        fileRepresentationDecodeFault=stage==0?1:0;fileRepresentationEncodeFault=2;
        fileRepresentationDecodes=fileRepresentationEncodes=0;bool caught=false;
        @autoreleasepool {
            @try {try {(void)[handle readLine];}catch(const std::runtime_error &){assert(stage==1);caught=true;}}
            @catch(NSException *exception){assert(stage==0&&[exception.name isEqual:@"FileRepresentationFixture"]);caught=true;}
        }
        fileRepresentationDecodeFault=fileRepresentationEncodeFault=0;
        assert(caught&&fileRepresentationDecodes==1&&fileRepresentationEncodes==stage&&[[handle tell][@"offset"] intValue]==4);
        [handle close];assert(fileFDs.empty());
    }
    assert(!fileLineTrack&&!fileLineGrowFault&&fileFDs.empty());
    puts("Direct line Foundation passed: 540 complete preceding/current replies/offsets/read/rewind cases across four entries, direct read destinations, mutable field identity, chunk/CR/limit/fault boundaries, grow NS/C++ recovery and preserved decode-before-base64 failure order. Opaque Foundation allocation/device performance pending.");
}
