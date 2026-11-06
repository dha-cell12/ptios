#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <cassert>
#include <cstdio>
#include <cstring>
#include <limits>
#include <initializer_list>
#include <stdexcept>
#include "../shared/TLinkNativeBudget.h"
#include "../shared/TLinkAXWireOutput.h"
#include "../shared/TLinkAXWireBudget.h"
#include "../shared/TLinkAXJSONOutput.mm"
#include "BeforeStopJSONWriter.inc"
#include "BeforeOutputJSONWriter.inc"
#include "BeforeStorageJSONWriter.inc"
#include "ax-node-pool-owner.h"
enum class WireFault {Normal,Empty,Probe,ThrowNS,ThrowCPP};
static WireFault jsonFault=WireFault::Normal,base64Fault=WireFault::Normal;
static unsigned jsonCalls=0,base64Calls=0;
static bool useBeforeOutputJSON=false,useBeforeStorageJSON=false;
static NSData *captured,*lastJSON;
static unsigned wireNotifyCalls=0;
static bool wirePublishChurn=false;
static unsigned wirePoolStages=0,wirePoolDrainAction=0,wirePoolActionCalls=0,wirePoolThrowKind=0;
static std::weak_ptr<TLinkNativeBudget> wirePoolBudget;
static std::shared_ptr<TLinkNativeCancellation> wirePoolCancellation;
extern "C" void TLinkAXFixtureOwnerDidDrain(void){
    if(!wirePoolDrainAction)return;
    auto budget=wirePoolBudget.lock();if(!budget)return;
    ++wirePoolActionCalls;
    if(wirePoolDrainAction==1){assert(wirePoolCancellation);wirePoolCancellation->cancel();}
    else{
        size_t wire=0;assert(lastJSON&&TLinkAXWireOutput::SuccessSize(lastJSON.length,wire));
        const size_t count=budget->outputLimit()-wire+1;
        std::vector<uint8_t> bytes(count+1,'x');bytes.back()=0;
        assert(budget->appendCString(bytes.data())==(int)count);
    }
}
static void observeWireTemporary(unsigned stage){
    if(!(wirePoolStages&stage))return;
    TLinkAXFixtureAutoreleaseOwner();
    if(wirePoolThrowKind==1)[NSException raise:@"WirePoolFixture" format:@"phase"];
    if(wirePoolThrowKind==2)throw std::runtime_error("wire pool");
}
static unsigned wireEffectStage=0,wireEffectKind=0,wireEffectCalls=0,wireFinalCalls=0;
static std::weak_ptr<TLinkNativeBudget> wireEffectBudget;
static std::shared_ptr<TLinkNativeCancellation> wireEffectCancellation;
static std::unique_ptr<TLinkNativeBudgetScope> wireLateScope;
static void applyWireEffect(unsigned stage){
    if(stage!=wireEffectStage)return;
    ++wireEffectCalls;auto budget=wireEffectBudget.lock();assert(budget&&wireEffectCancellation);
    if(wireEffectKind==0||wireEffectKind==4)wireEffectCancellation->cancel();
    if(wireEffectKind==1){
        assert(budget->deadline());
        std::this_thread::sleep_until(TLinkNativeClock::time_point(std::chrono::nanoseconds(budget->deadline())));
        assert(budget->reason()==TLinkNativeStop::Deadline);
    }
    if(wireEffectKind==2||wireEffectKind==3){
        size_t wire=0;assert(lastJSON&&TLinkAXWireOutput::SuccessSize(lastJSON.length,wire));
        const size_t count=budget->outputLimit()-wire+1;
        std::vector<uint8_t> bytes(count+1,'x');bytes.back()=0;
        assert(budget->appendCString(bytes.data())==(int)count);
        if(wireEffectKind==3){assert(!budget->outputAllowed(wire));wireEffectCancellation->cancel();}
    }
    if(wireEffectKind==4||wireEffectKind==5){
        auto alternateCancel=std::make_shared<TLinkNativeCancellation>();
        if(wireEffectKind==5)alternateCancel->cancel();
        auto alternate=std::make_shared<TLinkNativeBudget>(alternateCancel,0,1024*1024);
        wireLateScope.reset(new TLinkNativeBudgetScope(alternate));
    }
    if(wireEffectKind==6)[NSException raise:@"WireEffectFixture" format:@"effect"];
    if(wireEffectKind==7)throw std::runtime_error("wire effect");
}
static NSDictionary *fixtureCapability,*fixtureForeground;
static unsigned capabilityCalls=0,foregroundCalls=0,capabilityEffectSite=0,capabilityEffectKind=0,capabilityEffectCalls=0,capabilityFaultKind=0;
static std::weak_ptr<TLinkNativeBudget> capabilityBudget;
static std::shared_ptr<TLinkNativeCancellation> capabilityCancellation;
static void applyCapabilityEffect(unsigned site){
    if(site!=capabilityEffectSite)return;
    ++capabilityEffectCalls;auto budget=capabilityBudget.lock();assert(budget&&capabilityCancellation);
    if(capabilityEffectKind==0||capabilityEffectKind==3)capabilityCancellation->cancel();
    if(capabilityEffectKind==1){
        assert(budget->deadline());
        std::this_thread::sleep_until(TLinkNativeClock::time_point(std::chrono::nanoseconds(budget->deadline())));
        assert(budget->reason()==TLinkNativeStop::Deadline);
    }
    if(capabilityEffectKind==2)assert(!budget->outputAllowed(budget->outputLimit()+1));
    if(capabilityEffectKind==3){
        auto alternate=std::make_shared<TLinkNativeBudget>(std::make_shared<TLinkNativeCancellation>(),0,1024*1024);
        wireLateScope.reset(new TLinkNativeBudgetScope(alternate));
    }
    if(capabilityFaultKind==1)[NSException raise:@"CapabilityPreflightFixture" format:@"provider"];
    if(capabilityFaultKind==2)throw std::runtime_error("capability provider");
}
static uint64_t sTLinkUITreeContextGeneration=7;
static BOOL sTLinkUITreeLegacyForegroundUnavailable=NO;
static NSString *sTLinkAXSpringBoardState=@"ready",*sTLinkAXSpringBoardError=@"",*sTLinkAXSpringBoardDiagnostic=@"";
static NSInteger sTLinkAXSpringBoardLastResolveMs=0,sTLinkAXSpringBoardLastFocusedPid=123,sTLinkAXSpringBoardLastTopEventPid=0;
enum {TASK_UI_TREE_CAPABILITY=77};
@interface WireLengthProbe:NSObject
-(NSUInteger)length;
@end
@implementation WireLengthProbe
-(NSUInteger)length{return std::numeric_limits<NSUInteger>::max();}
@end
static NSData *fixtureJSON(id object){
    ++jsonCalls;
    if(jsonFault==WireFault::ThrowNS)[NSException raise:@"WireFixture" format:@"JSON"];
    if(jsonFault==WireFault::ThrowCPP)throw std::runtime_error("JSON");
    if(jsonFault==WireFault::Empty)return nil;
    if(jsonFault==WireFault::Probe)return (NSData *)(id)[WireLengthProbe new];
    lastJSON=[NSJSONSerialization dataWithJSONObject:object options:0 error:NULL];return lastJSON;
}
static NSData *fixtureBoundedJSONWithStop(id object,BOOL *tooLarge,BOOL *stopped){
    if(stopped)*stopped=NO;
    if(tooLarge)*tooLarge=NO;
    if(jsonFault!=WireFault::Normal)return fixtureJSON(object);
    ++jsonCalls;lastJSON=useBeforeStorageJSON?BeforeStorageTLinkAXBoundedJSONDataWithStop(object,tooLarge,stopped):(useBeforeOutputJSON?BeforeOutputTLinkAXBoundedJSONDataWithStop(object,tooLarge,stopped):
        TLinkAXBoundedJSONDataWithStop(object,tooLarge,stopped));return lastJSON;
}
static NSData *fixtureBeforeStopJSON(id object,BOOL *tooLarge){
    if(tooLarge)*tooLarge=NO;
    if(jsonFault!=WireFault::Normal)return fixtureJSON(object);
    ++jsonCalls;lastJSON=BeforeStopTLinkAXBoundedJSONData(object,tooLarge);return lastJSON;
}
static NSString *fixtureBase64(NSData *data){
    observeWireTemporary(1);
    ++base64Calls;
    if(base64Fault==WireFault::ThrowNS)[NSException raise:@"WireFixture" format:@"base64"];
    if(base64Fault==WireFault::ThrowCPP)throw std::runtime_error("base64");
    if(base64Fault==WireFault::Empty)return nil;
    NSString *value=[data base64EncodedStringWithOptions:0];applyWireEffect(1);return value;
}
static const char *fixtureWireUTF8(NSString *value){
    observeWireTemporary(4);
    const char *bytes=value.UTF8String;++wireFinalCalls;applyWireEffect(2);return bytes;
}
static NSString *fixtureWireFormat(NSString *base64){
    observeWireTemporary(2);return [NSString stringWithFormat:@"0;;%@\r\n",base64];
}
static BOOL TLinkAXResultSucceeded(NSDictionary *value){return [value isKindOfClass:[NSDictionary class]]&&[value[@"ok"] boolValue];}
static NSDictionary *TLinkAXCapabilitySnapshot(){++capabilityCalls;applyCapabilityEffect(1);return fixtureCapability;}
static NSDictionary *TLinkUITreeFrontmostContext(){++foregroundCalls;applyCapabilityEffect(2);return fixtureForeground;}
static CFAbsoluteTime fixtureWireWall(){return 1000;}
static void notifyClient(UInt8 *bytes,CFWriteStreamRef stream){
    ++wireNotifyCalls;observeWireTemporary(8);
    assert(bytes&&!stream);captured=[NSData dataWithBytes:bytes length:std::strlen((const char *)bytes)];
    if(wirePublishChurn){
        @autoreleasepool{
            NSMutableArray *scratch=[NSMutableArray array];
            for(unsigned n=0;n<16;++n)[scratch addObject:[NSMutableData dataWithLength:4096+n]];
            assert(scratch.count==16);
        }
        assert(captured.length==std::strlen((const char *)bytes));
        assert(std::memcmp(captured.bytes,bytes,captured.length)==0);
    }
}
#include "WireTrollFormatter.inc"
static NSData *fixtureWireSuccess(NSString *value){
    observeWireTemporary(2);
    NSData *data=TLinkSuccess(value);++wireFinalCalls;applyWireEffect(2);return data;
}
#include "CurrentRootResponse.inc"
#include "LegacyRootResponse.inc"
#include "CurrentTrollResponse.inc"
#include "LegacyTrollResponse.inc"
#include "BeforeBoundedRootResponse.inc"
#include "BeforeBoundedTrollResponse.inc"
#include "BeforeJSONStopRootResponse.inc"
#include "BeforeJSONStopTrollResponse.inc"
#include "BeforeWireBudgetRootResponse.inc"
#include "BeforeWireBudgetTrollResponse.inc"
#include "BeforeWirePoolRootResponse.inc"
#include "BeforeWirePoolTrollResponse.inc"
#include "BeforeWirePublishRootResponse.inc"
static void CurrentRootCapability(CFWriteStreamRef stream){int taskType=77;
#include "CurrentRootCapability.inc"
}
static void LegacyRootCapability(CFWriteStreamRef stream){int taskType=77;
#include "LegacyRootCapability.inc"
}
static NSData *CurrentTrollCapability(){int taskType=77;
#include "CurrentTrollCapability.inc"
    return nil;
}
static NSData *LegacyTrollCapability(){int taskType=77;
#include "LegacyTrollCapability.inc"
    return nil;
}
static void BeforeBoundedRootCapability(CFWriteStreamRef stream){int taskType=77;
#include "BeforeBoundedRootCapability.inc"
}
static NSData *BeforeBoundedTrollCapability(){int taskType=77;
#include "BeforeBoundedTrollCapability.inc"
    return nil;
}
static void BeforeJSONStopRootCapability(CFWriteStreamRef stream){int taskType=77;
#include "BeforeJSONStopRootCapability.inc"
}
static NSData *BeforeJSONStopTrollCapability(){int taskType=77;
#include "BeforeJSONStopTrollCapability.inc"
    return nil;
}
static void BeforeWireBudgetRootCapability(CFWriteStreamRef stream){int taskType=77;
#include "BeforeWireBudgetRootCapability.inc"
}
static NSData *BeforeWireBudgetTrollCapability(){int taskType=77;
#include "BeforeWireBudgetTrollCapability.inc"
    return nil;
}
static void BeforeWirePoolRootCapability(CFWriteStreamRef stream){int taskType=77;
#include "BeforeWirePoolRootCapability.inc"
}
static NSData *BeforeWirePoolTrollCapability(){int taskType=77;
#include "BeforeWirePoolTrollCapability.inc"
    return nil;
}
static void BeforeWirePublishRootCapability(CFWriteStreamRef stream){int taskType=77;
#include "BeforeWirePublishRootCapability.inc"
}
static void BeforeCapabilityPreflightRoot(CFWriteStreamRef stream){int taskType=77;
#include "BeforeCapabilityPreflightRoot.inc"
}
static NSData *BeforeCapabilityPreflightTroll(){int taskType=77;
#include "BeforeCapabilityPreflightTroll.inc"
    return nil;
}
static void reset(){
    capabilityCalls=foregroundCalls=capabilityEffectSite=capabilityEffectKind=capabilityEffectCalls=capabilityFaultKind=0;capabilityBudget.reset();capabilityCancellation.reset();
    wireNotifyCalls=0;wirePublishChurn=false;
    wirePoolStages=wirePoolDrainAction=wirePoolActionCalls=wirePoolThrowKind=0;wirePoolBudget.reset();wirePoolCancellation.reset();
    assert(!wireLateScope);wireEffectStage=wireEffectKind=wireEffectCalls=wireFinalCalls=0;wireEffectBudget.reset();wireEffectCancellation.reset();
    assert(!TLinkCurrentNativeBudget());useBeforeOutputJSON=useBeforeStorageJSON=false;jsonCalls=base64Calls=0;jsonFault=base64Fault=WireFault::Normal;captured=lastJSON=nil;
    fixtureCapability=@{@"ok":@YES,@"payload":@""};fixtureForeground=@{@"ok":@YES,@"bundle_id":@"fixture.bundle",@"pid":@123};
}
static NSData *call(bool root,bool capability,bool current,NSDictionary *value){
    if(root){
        if(capability){if(current)CurrentRootCapability(NULL);else LegacyRootCapability(NULL);}
        else if(current)CurrentRootResponse(value,NULL);else LegacyRootResponse(value,NULL);
        return captured;
    }
    if(capability)return current?CurrentTrollCapability():LegacyTrollCapability();
    return current?CurrentTrollResponse(value):LegacyTrollResponse(value);
}
static NSString *line(NSData *data){return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];}
static void errorReply(NSData *data,NSString *code){
    NSString *expected=[NSString stringWithFormat:@"-1;;%@\r\n",code];assert([line(data) isEqualToString:expected]);
}
static NSDictionary *decoded(NSData *data){
    NSString *text=line(data);assert([text hasPrefix:@"0;;"]&&[text hasSuffix:@"\r\n"]);
    NSString *body=[text substringWithRange:NSMakeRange(3,text.length-5)];
    NSData *json=[[NSData alloc] initWithBase64EncodedString:body options:0];
    assert(json&&[json isEqualToData:lastJSON]);
    id value=[NSJSONSerialization JSONObjectWithData:json options:0 error:NULL];assert([value isKindOfClass:[NSDictionary class]]);
    size_t wire=0;assert(TLinkAXWireOutput::SuccessSize(json.length,wire)&&data.length==wire);return value;
}
static NSDictionary *sizedGraph(bool root,bool capability,size_t bytes){
    fixtureCapability=@{@"ok":@YES,@"payload":@""};
    if(capability){call(root,true,true,nil);assert(lastJSON);}
    else lastJSON=[NSJSONSerialization dataWithJSONObject:fixtureCapability options:0 error:NULL];
    const size_t overhead=lastJSON.length;assert(bytes>=overhead);
    NSString *payload=[@"" stringByPaddingToLength:bytes-overhead withString:@"x" startingAtIndex:0];
    fixtureCapability=@{@"ok":@YES,@"payload":payload};jsonCalls=base64Calls=0;captured=lastJSON=nil;return fixtureCapability;
}
static void goldenCases(){
    for(bool root:{false,true})for(bool capability:{false,true}){
        for(unsigned n=0;n<128;++n){
            NSDictionary *expected=nil;
            for(bool current:{false,true}){@autoreleasepool{
                reset();NSDictionary *graph=@{@"ok":@((n&1)!=0||!capability),@"n":@(n),@"text":@"Ứng dụng 测试😀\n\"\\",@"rows":@[@1,@{},[NSNull null]]};
                fixtureCapability=graph;NSData *reply=call(root,capability,current,graph);
                NSDictionary *value=decoded(reply);if(current)assert([value isEqual:expected]);else expected=value;
                assert(jsonCalls==1&&base64Calls==1&&reply.length<=TLinkAXWireOutput::MaxSuccessWireBytes);
            }}
        }
    }
}
static void boundaryCases(){
    const size_t maxJSON=((TLinkAXWireOutput::MaxSuccessWireBytes-5)/4)*3;
    for(bool root:{false,true})for(bool capability:{false,true})for(bool oversize:{false,true}){
        for(bool current:{false,true}){@autoreleasepool{
            reset();NSDictionary *graph=sizedGraph(root,capability,maxJSON+(oversize?1:0));
            NSData *reply=call(root,capability,current,graph);assert(jsonCalls==1);
            if(current&&oversize)assert(!lastJSON);else assert(lastJSON.length==maxJSON+(oversize?1:0));
            if(current&&oversize){errorReply(reply,@"ui_response_too_large");assert(base64Calls==0);}
            else{
                assert(base64Calls==1&&[line(reply) hasPrefix:@"0;;"]);
                assert(reply.length==(oversize?1048577U:1048573U));
                if(!oversize)decoded(reply);
            }
        }}
    }
    for(bool root:{false,true})for(bool capability:{false,true}){@autoreleasepool{
        reset();jsonFault=WireFault::Probe;base64Fault=WireFault::ThrowNS;
        errorReply(call(root,capability,true,@{@"ok":@YES}),@"ui_response_too_large");assert(jsonCalls==1&&base64Calls==0);
    }}
}
static void budgetCases(){
    for(bool root:{false,true})for(bool capability:{false,true})for(unsigned kind=0;kind<5;++kind){@autoreleasepool{
        reset();NSDictionary *graph=@{@"ok":@YES,@"payload":@"small"};fixtureCapability=graph;
        NSData *before=call(root,capability,false,graph);const size_t wire=before.length;
        jsonCalls=base64Calls=0;captured=lastJSON=nil;
        const size_t cap=kind==0?wire:(kind==1?wire-1:(kind==2?0:(kind==3?wire+3:wire+2)));
        auto budget=std::make_shared<TLinkNativeBudget>(std::make_shared<TLinkNativeCancellation>(),0,cap,false,true);
        if(kind>=3)assert(budget->appendCString((const uint8_t *)"old")==3);
        auto child=std::make_shared<TLinkNativeBudget>(0,budget);TLinkNativeBudgetScope scope(child);
        NSData *reply=call(root,capability,true,graph);
        if(kind==1||kind==4){
            errorReply(reply,@"ui_response_too_large");assert(base64Calls==0&&budget->reason()==TLinkNativeStop::OutputLimit&&child->stopped());
        }else{decoded(reply);assert(base64Calls==1&&budget->reason()==TLinkNativeStop::None);}
        assert(jsonCalls==1);
    }}
}
static void failureCases(){
    for(bool root:{false,true})for(bool capability:{false,true})for(bool current:{false,true}){
        @autoreleasepool{
            reset();jsonFault=WireFault::Empty;
            errorReply(call(root,capability,current,@{@"ok":@YES}),capability?@"ui_capability_json_failed":@"ui_result_json_failed");
            assert(jsonCalls==1&&base64Calls==0);
        }
        @autoreleasepool{
            reset();base64Fault=WireFault::Empty;NSData *reply=call(root,capability,current,@{@"ok":@YES});
            assert([line(reply) isEqualToString:(root?@"0;;\r\n":@"0\r\n")]&&jsonCalls==1&&base64Calls==1);
        }
        for(unsigned site=0;site<2;++site)for(unsigned kind=0;kind<2;++kind){@autoreleasepool{
            reset();const WireFault fault=kind?WireFault::ThrowCPP:WireFault::ThrowNS;
            if(site)base64Fault=fault;else jsonFault=fault;bool caught=false;
            @try{try{call(root,capability,current,@{@"ok":@YES});}catch(const std::runtime_error &){caught=kind==1;}}
            @catch(NSException *exception){caught=kind==0&&[exception.name isEqualToString:@"WireFixture"];}
            assert(caught&&jsonCalls==1&&base64Calls==site);
        }}
    }
    for(bool root:{false,true})for(bool current:{false,true})for(NSDictionary *value in @[@{@"ok":@NO,@"error":@"fixture_error"},@{@"ok":@NO,@"error":@42}]){
        reset();errorReply(call(root,false,current,value),[value[@"error"] isKindOfClass:[NSString class]]?@"fixture_error":@"ui_operation_failed");
        assert(jsonCalls==0&&base64Calls==0);
    }
    reset();errorReply(call(false,false,true,(NSDictionary *)(id)@42),@"ui_result_invalid");assert(jsonCalls==0);
}
#include "ax-bounded-json-runtime-fixture.inc"
#include "ax-json-stop-runtime-fixture.inc"
#include "ax-json-budget-runtime-fixture.inc"
#include "ax-json-buffer-runtime-fixture.inc"
#include "ax-wire-budget-runtime-fixture.inc"
#include "ax-wire-pool-runtime-fixture.inc"
#include "ax-wire-publish-runtime-fixture.inc"
#include "ax-capability-preflight-runtime-fixture.inc"
int main(){@autoreleasepool{
    std::puts("AX wire Foundation: actual/frozen root/TrollStore result/capability codecs, real JSON/base64/formatter and native budget; AX/frontmost/notify controlled");
    goldenCases();boundaryCases();budgetCases();failureCases();boundedJSONCases();jsonStopCases();jsonBudgetCases();jsonStorageCases();wireLateAdmissionCases();wirePhasePoolCases();wirePublishPoolCases();capabilityPreflightCases();
    for(unsigned n=0;n<128;++n){@autoreleasepool{
        reset();jsonFault=WireFault::Probe;
        errorReply(call(n%2!=0,n%3!=0,true,@{@"ok":@YES}),@"ui_response_too_large");assert(base64Calls==0);
        reset();decoded(call(n%2!=0,n%3!=0,true,@{@"ok":@YES}));
    }}
    reset();assert(!TLinkCurrentNativeBudget());
    std::puts("AX wire passed: four actual/frozen routes, Unicode/graph/base64 parity, exact 1-MiB boundary, zero rejected encodes, native sticky/remaining/parent/unlimited budgets, legacy errors/nil fallbacks/NS-C++ faults and 128 recovery cycles. JSON allocation, error wires and device/transport qualification remain pending.");
}return 0;}
