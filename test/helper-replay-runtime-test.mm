#import <Foundation/Foundation.h>
#include "../shared/TLinkHelperRPCReplay.h"
#include <cassert>
#include <algorithm>
#include <cstdio>
#include <stdexcept>
using Cache=TLinkHelperRPCReplay;using D=Cache::Decision;
static void errorIs(NSDictionary *reply,NSString *message){assert(![reply[@"ok"] boolValue]);assert([reply[@"error"] isEqualToString:message]);}
int main(){@autoreleasepool {
    Cache cache;D decision;__block unsigned effects=0;
    NSDictionary *(^execute)(void)=^NSDictionary *{++effects;return @{@"ok":@(true),@"parts":@[@"0",@"42"],@"raw":@"0;;42\r\n"};};
    NSDictionary *first=TLinkHelperRPCDispatch(cache,@"one",@"tap",@[@1,@"x"],execute,decision);assert(decision==D::Execute&&effects==1);
    NSDictionary *again=TLinkHelperRPCDispatch(cache,@"one",@"tap",@[@1,@"x"],execute,decision);assert(decision==D::Replay&&effects==1&&[first isEqual:again]);
    errorIs(TLinkHelperRPCDispatch(cache,@"one",@"swipe",@[@1,@"x"],execute,decision),@"duplicate native RPC requestId collision");
    errorIs(TLinkHelperRPCDispatch(cache,@"one",@"tap",@[@2,@"x"],execute,decision),@"duplicate native RPC requestId collision");assert(effects==1);
    NSMutableDictionary *a=[NSMutableDictionary dictionary];a[@"z"]=@1;a[@"a"]=@2;
    NSMutableDictionary *b=[NSMutableDictionary dictionary];b[@"a"]=@2;b[@"z"]=@1;
    Cache::Digest da,db;assert(TLinkHelperRPCFingerprint(@[a],da));assert(TLinkHelperRPCFingerprint(@[b],db));assert(da==db);
    // Known SHA-256 for [] and type/content distinctions, including NUL and Unicode.
    assert(TLinkHelperRPCFingerprint(@[],da));const uint8_t golden[32]={0x4f,0x53,0xcd,0xa1,0x8c,0x2b,0xaa,0x0c,0x03,0x54,0xbb,0x5f,0x9a,0x3e,0xcb,0xe5,0xed,0x12,0xab,0x4d,0x8e,0x11,0xba,0x87,0x3c,0x2f,0x11,0x16,0x12,0x02,0xb9,0x45};
    assert(std::equal(da.begin(),da.end(),golden));
    for(NSArray *args in @[@[@1],@[@"1"],@[@(true)],@[[NSNull null]],@[@"\u00e9"],@[@"x\0y"]]){
        static unsigned n=0;NSString *key=[NSString stringWithFormat:@"types-%u",n++];
        NSDictionary *reply=TLinkHelperRPCDispatch(cache,key,@"tap",args,execute,decision);assert([reply[@"ok"] boolValue]&&decision==D::Execute);
        assert([TLinkHelperRPCDispatch(cache,key,@"tap",args,execute,decision) isEqual:reply]&&decision==D::Replay);
    }
    NSString *argumentLimit=[@"" stringByPaddingToLength:1024*1024-4 withString:@"x" startingAtIndex:0];
    assert(TLinkHelperRPCFingerprint(@[argumentLimit],da));
    assert(!TLinkHelperRPCFingerprint(@[[argumentLimit stringByAppendingString:@"x"]],da));
    unsigned before=effects;
    errorIs(TLinkHelperRPCDispatch(cache,@"",@"tap",@[],execute,decision),@"invalid native RPC identity or arguments");
    errorIs(TLinkHelperRPCDispatch(cache,@"bad",@"tap",@[[NSData data]],execute,decision),@"invalid native RPC arguments");assert(effects==before);
    // Embedded NUL identities must not alias their prefix; non-ASCII byte limits are explicit.
    unichar units[3]={'a',0,'b'};NSString *nulId=[NSString stringWithCharacters:units length:3];
    TLinkHelperRPCDispatch(cache,@"a",@"tap",@[],execute,decision);assert(decision==D::Execute);
    TLinkHelperRPCDispatch(cache,nulId,@"tap",@[],execute,decision);assert(decision==D::Execute);
    before=effects;TLinkHelperRPCDispatch(cache,nulId,@"tap",@[],execute,decision);assert(decision==D::Replay&&effects==before);
    // Capture a pointer: Blocks copy C++ locals as const; reentry must use the original ledger.
    Cache *const reentryCache=&cache;
    // An execution reentering the same identity cannot recursively repeat its effect.
    TLinkHelperRPCDispatch(cache,@"nested",@"tap",@[],^NSDictionary *{
        D nested;NSDictionary *blocked=TLinkHelperRPCDispatch(*reentryCache,@"nested",@"tap",@[],execute,nested);
        assert(nested==D::InFlight);errorIs(blocked,@"native RPC request already in flight");return @{@"ok":@(true)};
    },decision);assert(effects==before);
    // A denied policy reply is replayed; toggling policy later cannot authorize an old ID.
    TLinkHelperRPCDispatch(cache,@"denied",@"shell",@[],^NSDictionary *{return TLinkHelperRPCError(@"helper RPC method blocked by policy");},decision);
    errorIs(TLinkHelperRPCDispatch(cache,@"denied",@"shell",@[],execute,decision),@"helper RPC method blocked by policy");assert(effects==before);
    // Cache wire snapshots rather than mutable object graphs, across autorelease pools.
    NSMutableDictionary *mutableResult=[@{@"ok":@(true),@"value":@"old"} mutableCopy];NSDictionary *held=nil;
    @autoreleasepool{held=TLinkHelperRPCDispatch(cache,@"mutable",@"info",@[],^NSDictionary *{return mutableResult;},decision);}
    assert(held==mutableResult);mutableResult[@"value"]=@"new";
    NSDictionary *snapshot=TLinkHelperRPCDispatch(cache,@"mutable",@"info",@[],execute,decision);assert([snapshot[@"value"] isEqualToString:@"old"]);
    cache.clear();assert([snapshot[@"value"] isEqualToString:@"old"]);
    Cache::Limits limits;limits.bytes=160;Cache small(limits);
    for(unsigned n=0;n<20;++n){NSString *key=[NSString stringWithFormat:@"e%u",n];TLinkHelperRPCDispatch(small,key,@"tap",@[],execute,decision);assert(decision==D::Execute&&small.bytes()<=160);}
    before=effects;errorIs(TLinkHelperRPCDispatch(small,@"e0",@"tap",@[],execute,decision),@"native RPC replay unavailable; request already handled");assert(decision==D::Unavailable&&effects==before);
    errorIs(TLinkHelperRPCDispatch(small,@"e0",@"tap",@[@1],execute,decision),@"duplicate native RPC requestId collision");
    // At most one execution even when execution or encoding fails.
    for(unsigned mode=0;mode<4;++mode){NSString *key=[NSString stringWithFormat:@"fault%u",mode];
        NSDictionary *fault=TLinkHelperRPCDispatch(cache,key,@"tap",@[],^NSDictionary *{
            ++effects;if(mode==0)@throw [NSException exceptionWithName:@"fault" reason:nil userInfo:nil];
            if(mode==1)throw std::runtime_error("fault");
            if(mode==2)return @{@"ok":@(true),@"bad":[NSData data]};
            return @{@"ok":@(true),@"large":[@"x" stringByPaddingToLength:1024*1024 withString:@"x" startingAtIndex:0]};
        },decision);assert(![fault[@"ok"] boolValue]);before=effects;
        assert([TLinkHelperRPCDispatch(cache,key,@"tap",@[],execute,decision) isEqual:fault]);assert(effects==before&&decision==D::Replay);
    }
    limits.identities=1;Cache bounded(limits);
    TLinkHelperRPCDispatch(bounded,@"first",@"tap",@[],execute,decision);before=effects;
    errorIs(TLinkHelperRPCDispatch(bounded,@"second",@"tap",@[],execute,decision),@"native RPC session identity limit reached");assert(decision==D::Capacity&&effects==before);
    assert([TLinkHelperRPCDispatch(bounded,@"first",@"tap",@[],execute,decision)[@"ok"] boolValue]&&effects==before);
    bounded.clear();TLinkHelperRPCDispatch(bounded,@"second",@"tap",@[],execute,decision);assert(decision==D::Execute&&effects==before+1);
    puts("Helper replay Foundation passed: actual SHA/JSON dispatcher, sorted keys, immutable wire snapshots/pools, eviction without repeated effects, identity cap, NS/C++/encoding/oversize faults and session reset.");
}return 0;}
