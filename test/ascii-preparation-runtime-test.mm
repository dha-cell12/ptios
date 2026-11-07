#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <cerrno>
#include <cstdint>
#include <vector>
#include "../shared/TLinkASCIIPreparation.h"
#include "../shared/TLinkEventPollCore.h"
static NSString *const TLinkEventChannelSchemaV1=@"event_channel_v1";
static const NSUInteger kTLinkEventPollMaxEvents=32;
#include "PreparationCursor.inc"
#include "PreparationTopic.inc"
#include "BeforePreparationToken.inc"
#include "CurrentPreparationToken.inc"
#include "BeforePreparationSanitize.inc"
#include "CurrentPreparationSanitize.inc"
#include "BeforePreparationInteger.inc"
#include "CurrentPreparationInteger.inc"
#include "BeforePreparationBatch.inc"
#include "CurrentPreparationBatch.inc"
static void tokenCases(){
    for(id value in @[@"",@"Script.RUN-1_2",@" ảnh;测试😀 A/B.. \n",@"a\0b",@42,[NSNull null]]){
        NSString *text=(NSString *)value;
        assert([BeforeToken(text,@"fallback") isEqual:CurrentToken(text,@"fallback")]);
        assert([BeforeSanitize(text) isEqual:CurrentSanitize(text)]);
    }
    for(unsigned n=0;n<2000;++n){
        @autoreleasepool{
            std::vector<unichar> units(n%257);
            for(unsigned i=0;i<units.size();++i){unichar value=unichar((n*71+i*233)%65536);units[i]=value>=0xd800&&value<=0xdfff?'?':value;}
            NSString *text=units.empty()?@"":[[NSString alloc] initWithCharacters:units.data() length:units.size()];
            assert([BeforeToken(text,@"fallback") isEqual:CurrentToken(text,@"fallback")]);
            assert([BeforeSanitize(text) isEqual:CurrentSanitize(text)]);
        }
    }
    for(NSUInteger length:{0U,63U,64U,65U,95U,96U,97U,4096U}){
        NSString *text=[@"" stringByPaddingToLength:length withString:@"Ab_9.-!?" startingAtIndex:0];
        assert([BeforeToken(text,@"fallback") isEqual:CurrentToken(text,@"fallback")]);
        assert([BeforeSanitize(text) isEqual:CurrentSanitize(text)]);
    }
}
static void integerCases(){
    NSArray *values=@[@0,@1,@(-1),@(UINT64_MAX),@(INT64_MAX),@1.0,@1.5,@(-0.0),@1e20,@YES,@NO,@"123",[NSNull null],[NSDecimalNumber decimalNumberWithString:@"18446744073709551616"]];
    for(id value in values){
        uint64_t oldValue=777,newValue=777;errno=EINTR;BOOL old=BeforeInteger(value,&oldValue);int oldError=errno;
        errno=EINTR;BOOL current=CurrentInteger(value,&newValue);assert(old==current&&oldValue==newValue&&errno==oldError);
        errno=EINTR;old=BeforeInteger(value,NULL);oldError=errno;errno=EINTR;current=CurrentInteger(value,NULL);assert(old==current&&errno==oldError);
    }
    for(uint64_t n=0;n<10000;++n){uint64_t oldValue=0,newValue=0;NSNumber *value=@(n*987654321ULL);assert(BeforeInteger(value,&oldValue)&&CurrentInteger(value,&newValue)&&oldValue==newValue);}
}
static void batchCases(){
    NSMutableArray *events=[NSMutableArray array];
    for(unsigned n=1;n<=256;++n)[events addObject:@{@"sequence":@(n),@"topic":n%2?@"a":@"b",@"payload":@{@"n":@(n)}}];
    NSDictionary *journal=@{@"next_sequence":@257,@"events":events};
    for(uint64_t cursor:{uint64_t(0),uint64_t(1),uint64_t(127),uint64_t(255),uint64_t(256),uint64_t(257),UINT64_MAX}){
        for(NSUInteger limit:{NSUInteger(0),NSUInteger(1),NSUInteger(16),NSUInteger(32),NSUInteger(256),NSUIntegerMax}){
            for(NSSet *topics in @[[NSSet set],[NSSet setWithObject:@"a"],[NSSet setWithObject:@"*"],[NSSet setWithObject:@"missing"]]){
                for(bool timeout:{false,true}){
                    NSDictionary *old=BeforeBatch(journal,cursor,topics,limit,timeout),*current=CurrentBatch(journal,cursor,topics,limit,timeout);
                    assert([old isEqual:current]);
                    for(NSUInteger i=0;i<[old[@"events"] count];++i)assert(old[@"events"][i]==current[@"events"][i]);
                }
            }
        }
    }
}
int main(){@autoreleasepool{
    puts("Preparation Foundation: actual/frozen token/history sanitizer/journal number and batch helpers with real Unicode/Foundation/CF");
    tokenCases();integerCases();batchCases();
    puts("Preparation Foundation passed: 2000 frozen UTF16 token/path cases, exact 64/96 caps, 10k journal numbers/errno/refusal, 336 cursor/filter/limit/timeout batch graphs and held event identity. Device allocation/latency remains unqualified.");
}return 0;}
