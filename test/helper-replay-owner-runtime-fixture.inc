static unsigned replayViewFault=0,replayJSONFault=0,replayParseFault=0,replayParseAction=0,replayViewCalls=0,replayNestedEffects=0;
static Cache *replayParserCache=nullptr;
static bool replayHoldData=false;
static NSData *replayHeldData=nil;
static std::weak_ptr<const std::string> replayObservedOwner;
static const char *replayObservedBytes=nullptr;
static NSData *FixtureReplayData(const Cache::Reply &owner){
    ++replayViewCalls;replayObservedOwner=owner;replayObservedBytes=owner->data();
    if(replayViewFault==1)return nil;
    if(replayViewFault==2)[NSException raise:@"ReplayViewFixture" format:@"factory"];
    if(replayViewFault==3)throw std::runtime_error("view");
    if(replayViewFault==4)return [NSData dataWithBytes:owner->data() length:owner->size()];
    return FixtureReplayOriginalData(owner);
}
static NSData *FixtureReplayJSON(id result){
    if(replayJSONFault==1)return nil;
    if(replayJSONFault==2)return [NSData data];
    return [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
}
static id FixtureReplayParse(NSData *data){
    if(replayHoldData)replayHeldData=data;
    if(replayParseAction){
        const unsigned action=replayParseAction;replayParseAction=0;assert(replayParserCache);
        if(action==1)replayParserCache->clear();
        else {
            D nested;
            NSDictionary *reply=TLinkHelperRPCDispatch(*replayParserCache,@"nested",@"tap",@[],^NSDictionary *{
                ++replayNestedEffects;return @{@"ok":@(true),@"nested":@YES};
            },nested);
            assert(nested==D::Execute&&[reply[@"ok"] boolValue]);
        }
    }
    if(replayParseFault==1)[NSException raise:@"ReplayParseFixture" format:@"parse"];
    if(replayParseFault==2)throw std::runtime_error("parse");
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}
@interface ReplayIdentityString : NSString {
@public NSString *backing;unsigned encodings,cStrings;BOOL failEncoding,mutateAfterEncoding;
}
- (instancetype)initWithText:(NSString *)text;
@end
@implementation ReplayIdentityString
- (instancetype)initWithText:(NSString *)text {self=[super init];if(self)backing=[text copy];return self;}
- (NSUInteger)length {return backing.length;}
- (unichar)characterAtIndex:(NSUInteger)index {return [backing characterAtIndex:index];}
- (void)getCharacters:(unichar *)buffer range:(NSRange)range {[backing getCharacters:buffer range:range];}
- (id)copyWithZone:(NSZone *)zone {(void)zone;return self;}
- (const char *)UTF8String {++cStrings;return backing.UTF8String;}
- (NSData *)dataUsingEncoding:(NSStringEncoding)encoding {
    ++encodings;if(failEncoding)return nil;
    NSData *data=[backing dataUsingEncoding:encoding];
    if(mutateAfterEncoding)backing=@"changed-after-encoding";
    return data;
}
@end
static void replayIdentityCases(){
    for(bool modern:{false,true}){
        ReplayIdentityString *request=[[ReplayIdentityString alloc] initWithText:@"request\0tail"];
        ReplayIdentityString *method=[[ReplayIdentityString alloc] initWithText:@"tap"];
        __block unsigned effects=0;
        NSDictionary *(^execute)(void)=^NSDictionary *{++effects;return @{@"ok":@YES};};
        if(modern){Cache cache;D decision;(void)TLinkHelperRPCDispatch(cache,request,method,@[],execute,decision);assert(decision==D::Execute);}
        else {BeforeTLinkHelperRPCReplay cache;BeforeTLinkHelperRPCReplay::Decision decision;(void)BeforeTLinkHelperRPCDispatch(cache,request,method,@[],execute,decision);assert(decision==BeforeTLinkHelperRPCReplay::Decision::Execute);}
        assert(effects==1&&request->encodings==1&&method->encodings==1);
        assert(request->cStrings==(modern?0U:1U)&&method->cStrings==(modern?0U:1U));
    }
    Cache cache;D decision;__block unsigned effects=0;
    NSDictionary *(^execute)(void)=^NSDictionary *{++effects;return @{@"ok":@YES};};
    ReplayIdentityString *request=[[ReplayIdentityString alloc] initWithText:@"stable-id"];
    request->mutateAfterEncoding=YES;
    assert([TLinkHelperRPCDispatch(cache,request,@"tap",@[],execute,decision)[@"ok"] boolValue]&&effects==1&&request->cStrings==0);
    Cache::Digest digest;assert(TLinkHelperRPCFingerprint(@[],digest));
    assert(cache.begin("stable-id","tap",digest).decision==D::Replay);
    assert([TLinkHelperRPCDispatch(cache,@"stable-id",@"tap",@[],execute,decision)[@"ok"] boolValue]&&effects==1);
    request=[[ReplayIdentityString alloc] initWithText:@"failed"];request->failEncoding=YES;
    errorIs(TLinkHelperRPCDispatch(cache,request,@"tap",@[],execute,decision),@"invalid native RPC identity or arguments");
    assert(effects==1&&decision==D::Invalid);
}
static void replayOwnerDispatchParity(){
    for(NSString *identity in @[@"id",@"ảnh",@"a\0b",[@"x" stringByPaddingToLength:64 withString:@"x" startingAtIndex:0],[@"x" stringByPaddingToLength:65 withString:@"x" startingAtIndex:0],[@"ả" stringByPaddingToLength:22 withString:@"ả" startingAtIndex:0]]){
        for(NSString *method in @[@"tap",@"capturé",@"t\0p",[@"ả" stringByPaddingToLength:43 withString:@"ả" startingAtIndex:0]]){
            for(unsigned mode=0;mode<3;++mode){@autoreleasepool {
                Cache now;BeforeTLinkHelperRPCReplay before;D current;BeforeTLinkHelperRPCReplay::Decision prior;
                __block unsigned a=0,b=0;
                NSDictionary *(^oldExecute)(void)=^NSDictionary *{++a;return @{@"ok":@YES,@"value":@[@"ảnh\0测试😀",@(mode)]};};
                NSDictionary *(^newExecute)(void)=^NSDictionary *{++b;return @{@"ok":@YES,@"value":@[@"ảnh\0测试😀",@(mode)]};};
                for(unsigned call=0;call<3;++call){
                    NSArray *arguments=call==2&&mode==1?@[@1]:@[];
                    NSString *selected=call==2&&mode==2?@"other":method;
                    NSDictionary *expected=BeforeTLinkHelperRPCDispatch(before,identity,selected,arguments,oldExecute,prior);
                    NSDictionary *actual=TLinkHelperRPCDispatch(now,identity,selected,arguments,newExecute,current);
                    assert([expected isEqual:actual]&&unsigned(prior)==unsigned(current)&&a==b);
                    assert(now.bytes()==before.bytes()&&now.replies()==before.replies()&&now.identities()==before.identities());
                }
            }}
        }
    }
}
static void replayDataOwnerCases(){
    for(unsigned factory:{0U,4U}){
        for(unsigned action=1;action<=2;++action){
            Cache::Limits limits;limits.replies=1;Cache cache(limits);D decision;__block unsigned effects=0;
            NSDictionary *(^execute)(void)=^NSDictionary *{++effects;return @{@"ok":@YES,@"value":@"held\0ảnh测试😀"};};
            NSDictionary *first=TLinkHelperRPCDispatch(cache,@"held",@"tap",@[],execute,decision);
            @autoreleasepool {
                replayViewFault=factory;replayParserCache=&cache;replayParseAction=action;replayHoldData=true;
                NSDictionary *again=TLinkHelperRPCDispatch(cache,@"held",@"tap",@[],execute,decision);
                assert([first isEqual:again]&&decision==D::Replay&&effects==1&&replayHeldData);
                if(replayHeldData.bytes==replayObservedBytes)assert(!replayObservedOwner.expired());
                replayHoldData=false;replayParserCache=nullptr;replayViewFault=0;
                cache.clear();
            }
            @autoreleasepool {
                NSDictionary *parsed=[NSJSONSerialization JSONObjectWithData:replayHeldData options:0 error:nil];
                assert([parsed isEqual:first]);replayHeldData=nil;
            }
            assert(replayObservedOwner.expired()&&!cache.bytes()&&!cache.identities());
        }
    }
    assert(replayNestedEffects==2);
    for(unsigned fault=1;fault<=5;++fault){
        Cache cache;D decision;__block unsigned effects=0;
        NSDictionary *(^execute)(void)=^NSDictionary *{++effects;return @{@"ok":@YES};};
        (void)TLinkHelperRPCDispatch(cache,@"fault",@"tap",@[],execute,decision);
        const auto bytes=cache.bytes();bool caught=false;NSDictionary *failed=nil;
        @autoreleasepool {
            replayViewFault=fault<=3?fault:0;replayParseFault=fault==4?1:(fault==5?2:0);
            @try {try {failed=TLinkHelperRPCDispatch(cache,@"fault",@"tap",@[],execute,decision);}catch(const std::runtime_error &){caught=true;}}
            @catch(NSException *exception){(void)exception;caught=true;}
            replayViewFault=replayParseFault=0;
        }
        assert((caught||(fault==1&&!failed))&&effects==1&&cache.bytes()==bytes&&decision==D::Replay);
        assert([TLinkHelperRPCDispatch(cache,@"fault",@"tap",@[],execute,decision)[@"ok"] boolValue]&&effects==1);
        cache.clear();
    }
    for(unsigned fault=1;fault<=2;++fault){@autoreleasepool {
        Cache cache;D decision;__block unsigned effects=0;replayJSONFault=fault;
        errorIs(TLinkHelperRPCDispatch(cache,@"encode-nil",@"tap",@[],^NSDictionary *{++effects;return @{@"ok":@YES};},decision),@"native RPC result exceeds replay limit or is invalid");
        replayJSONFault=0;
        errorIs(TLinkHelperRPCDispatch(cache,@"encode-nil",@"tap",@[],^NSDictionary *{++effects;return @{@"ok":@YES};},decision),@"native RPC replay unavailable; request already handled");
        assert(effects==1&&decision==D::Unavailable&&!cache.bytes());
    }}
    assert(!replayHeldData&&!replayParserCache&&!replayViewFault&&!replayParseFault&&!replayJSONFault);
}
static void replayOwnerRuntimeCases(){
    puts("Helper replay owner Foundation: exact previous dispatcher, single identity encodings and captured immutable NSData owners");fflush(stdout);
    replayIdentityCases();replayOwnerDispatchParity();replayDataOwnerCases();
    puts("Helper replay owner Foundation passed: 216 complete previous decision/reply/quota cases, UTF8 identity/NUL/byte fences with zero borrowed CString calls, stable encoding under mutation, held data across clear/nested eviction, factory/parse NS/C++ faults, copied data fallback and nil serialization without repeat effects. Foundation copy behavior/device latency remain pending.");
}
