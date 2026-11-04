#import <Foundation/Foundation.h>
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <stdexcept>

struct Counts {size_t selectors=0,services=0,equalities=0,lookups=0;};
static Counts counts;
static id fallbackNames;
@interface RecordConfig : NSObject
@property(nonatomic,strong) id name;
@property(nonatomic,strong) id identifier;
@end
@implementation RecordConfig
@end
@interface RecordService : NSObject
@property(nonatomic,strong) id identifier;
@property(nonatomic,copy) void (^onRead)(void);
@end
@implementation RecordService
@end
@interface RecordStore : NSObject
@property(nonatomic,strong) id configurations;
+(id)createAllVPNByUserDefinedNamesDictionary;
@end
@implementation RecordStore
+(id)createAllVPNByUserDefinedNamesDictionary {return fallbackNames;}
@end
// Controlled dictionary-shaped provider: fixed order, invalid names and duplicate IDs.
// Ordinary NSDictionary is also exercised below; no class-cluster subclass is needed.
@interface OrderedNames : NSObject
@property(nonatomic,copy) NSArray<NSArray *> *pairs;
@end
@implementation OrderedNames
-(BOOL)isKindOfClass:(Class)type {return type==[NSDictionary class]||[super isKindOfClass:type];}
-(void)enumerateKeysAndObjectsUsingBlock:(void (^)(id,id,BOOL *))block {
    BOOL stop=NO;
    for(NSArray *pair in self.pairs){block(pair[0],pair[1],&stop);if(stop)break;}
}
@end
static RecordConfig *config(id name,id identifier) {
    RecordConfig *value=[RecordConfig new];value.name=name;value.identifier=identifier;return value;
}
static RecordService *service(id identifier) {
    RecordService *value=[RecordService new];value.identifier=identifier;return value;
}
static OrderedNames *ordered(NSArray<NSArray *> *pairs) {
    OrderedNames *value=[OrderedNames new];value.pairs=pairs;return value;
}
static id TLinkVPNPrivateSendId(id target,SEL selector) {
    ++counts.selectors;
    if(!target||![target respondsToSelector:selector])return nil;
    return ((id(*)(id,SEL))[target methodForSelector:selector])(target,selector);
}
#include "VPNIdentifierUnderTest.inc"
static NSString *TLinkVPNPrivateServiceIdentifier(id object) {
    ++counts.services;
    if(![object isKindOfClass:[RecordService class]])return @"";
    RecordService *value=object;
    if(value.onRead)value.onRead();
    return [value.identifier isKindOfClass:[NSString class]]?value.identifier:@"";
}
static BOOL fixtureDuplicateEqual(NSString *left,NSString *right) {
    ++counts.equalities;return [left isEqualToString:right];
}
static BOOL fixtureSeenContains(NSMutableSet<NSString *> *seen,NSString *identifier) {
    ++counts.lookups;return [seen containsObject:identifier];
}
#include "VPNRecordsUnderTest.inc"
#include "VPNRecordsLegacy.inc"
static NSArray *compare(id primary,id names) {
    RecordStore *store=[RecordStore new];store.configurations=primary;fallbackNames=names;
    counts={};NSArray *expected=LegacyPrivateConfigurationRecords(store);Counts old=counts;
    counts={};NSArray *actual=TLinkVPNPrivateConfigurationRecords(store);
    assert([actual isEqualToArray:expected]);
    assert(counts.selectors==old.selectors&&counts.services==old.services);
    return actual;
}
static void basicCases() {
    assert(compare(nil,nil).count==0);
    assert(compare(@42,@[]).count==0);
    assert(compare(@[],@{}).count==0);
    assert(TLinkVPNPrivateConfigurationRecords([NSObject new]).count==0);
    NSUUID *uuid=[[NSUUID alloc] initWithUUIDString:@"00000000-0000-0000-0000-000000000001"];
    NSArray *primary=@[config(@"first",@"same"),config(@"second",@"same"),config(@"uuid",uuid),
        config(@"",@"empty-name"),config(@42,@"invalid-name"),config(@"missing",@42),config(@"empty",@"")];
    NSArray *pairs=@[@[@"skip",service(@"same")],@[@"third",service(@"other")],
        @[@"duplicate",service(@"other")],@[@"",service(@"invalid")],@[@42,service(@"invalid2")],
        @[@"invalid-id",service(@42)],@[@"empty-id",service(@"")]];
    NSArray *records=compare(primary,ordered(pairs));
    assert(records.count==4);
    assert([records[0][@"name"] isEqualToString:@"first"]);
    assert([records[1][@"name"] isEqualToString:@"second"]);
    assert(records[2][@"raw_identifier"]==uuid);
    assert([records[3][@"name"] isEqualToString:@"third"]);
    assert(counts.equalities==0&&counts.lookups==3);
    compare([NSSet setWithArray:primary],@{@"real-dictionary":service(@"new")});
    // No retained cache: fresh provider contents are read on every call.
    RecordStore *store=[RecordStore new];store.configurations=@[config(@"old",@"old")];fallbackNames=nil;
    assert(TLinkVPNPrivateConfigurationRecords(store).count==1);
    store.configurations=@[config(@"new",@"new"),config(@"new2",@"new2")];
    assert(TLinkVPNPrivateConfigurationRecords(store).count==2);
}
static uint32_t seed=0x42a06acU;
static uint32_t nextValue() {seed=seed*1664525U+1013904223U;return seed;}
static void goldenCases() {
    for(unsigned iteration=0;iteration<3000;++iteration){@autoreleasepool{
        NSMutableArray *primary=[NSMutableArray array],*pairs=[NSMutableArray array];
        unsigned primaryCount=nextValue()%17,fallbackCount=nextValue()%21;
        for(unsigned n=0;n<primaryCount;++n){
            NSString *name=nextValue()%5?[NSString stringWithFormat:@"primary-%u",n]:@"";
            NSString *identifier=[NSString stringWithFormat:@"id-%u",nextValue()%13];
            [primary addObject:config(name,identifier)];
        }
        for(unsigned n=0;n<fallbackCount;++n){
            NSString *name=nextValue()%7?[NSString stringWithFormat:@"fallback-%u",n]:@"";
            NSString *identifier=nextValue()%7?[NSString stringWithFormat:@"id-%u",nextValue()%23]:@"";
            [pairs addObject:@[name,service(identifier)]];
        }
        compare(primary,ordered(pairs));assert(counts.equalities==0);
    }}
}
static NSArray *snapshot(NSArray *records) {
    NSMutableArray *values=[NSMutableArray array];
    for(NSDictionary *record in records)[values addObject:@[[record[@"name"] copy],[record[@"identifier"] copy]]];
    return values;
}
static NSArray *mutableCase(bool legacy,unsigned kind) {
    NSMutableString *identifier=[@"before" mutableCopy];
    RecordStore *store=[RecordStore new];
    RecordService *trigger=service(@"after");trigger.onRead=^{[identifier setString:@"after"];};
    if(kind==0){
        store.configurations=@[config(@"primary",identifier)];
        fallbackNames=ordered(@[@[@"same-after-mutation",trigger],@[@"new",service(@"new")]]);
    }else if(kind==1){
        store.configurations=@[];
        fallbackNames=ordered(@[@[@"mutable-fallback",service(identifier)],@[@"same-after-mutation",trigger],@[@"new",service(@"new")]]);
    }else{
        // Rejected mutable query is not retained; subsequent immutable query uses the index.
        [identifier setString:@"same"];store.configurations=@[config(@"primary",@"same")];
        fallbackNames=ordered(@[@[@"duplicate",service(identifier)],@[@"new",service(@"new")]]);
    }
    counts={};NSArray *records=legacy?LegacyPrivateConfigurationRecords(store):TLinkVPNPrivateConfigurationRecords(store);
    assert(records.count==2);
    if(kind<2){assert(records[0][@"identifier"]==identifier);assert(records[0][@"raw_identifier"]==identifier);}
    if(!legacy){assert(counts.equalities>0);assert(counts.lookups==(kind==2?1U:0U));}
    return snapshot(records);
}
static void mutableCases() {
    for(unsigned kind=0;kind<3;++kind){
        NSArray *expected=mutableCase(true,kind),*actual=mutableCase(false,kind);
        assert([actual isEqualToArray:expected]);
    }
}
static void operationCounts() {
    NSMutableArray *primary=[NSMutableArray array],*pairs=[NSMutableArray array];
    for(unsigned n=0;n<1000;++n){
        [primary addObject:config(@"primary",[NSString stringWithFormat:@"primary-%u",n])];
        [pairs addObject:@[[NSString stringWithFormat:@"fallback-%u",n],service([NSString stringWithFormat:@"fallback-%u",n])]];
    }
    RecordStore *store=[RecordStore new];store.configurations=primary;fallbackNames=ordered(pairs);
    counts={};NSArray *expected=LegacyPrivateConfigurationRecords(store);Counts old=counts;
    counts={};NSArray *actual=TLinkVPNPrivateConfigurationRecords(store);
    assert([actual isEqualToArray:expected]);assert(actual.count==2000);
    assert(old.equalities==1499500&&counts.equalities==0&&counts.lookups==1000);
    assert(old.selectors==counts.selectors&&old.services==counts.services);
    std::puts("VPN records fixture: 1,499,500 legacy duplicate comparisons versus 1000 real set lookups; provider calls unchanged.");
}
static void lifetimeAndFaultCases() {
    NSArray *held;
    @autoreleasepool{held=compare(@[config([@"name" mutableCopy],@"held")],ordered(@[@[@"fallback",service(@"second")]]));}
    assert(held.count==2&&[held[0][@"name"] isEqualToString:@"name"]);
    for(unsigned kind=0;kind<2;++kind){
        for(unsigned legacy=0;legacy<2;++legacy){
            RecordService *entry=service(@"error");entry.onRead=^{
                if(kind==0)@throw [NSException exceptionWithName:@"fixture" reason:nil userInfo:nil];
                throw std::runtime_error("fixture");
            };
            fallbackNames=ordered(@[@[@"error",entry]]);RecordStore *store=[RecordStore new];store.configurations=@[config(@"primary",@"id")];
            bool caught=false;
            try{@try{if(legacy)LegacyPrivateConfigurationRecords(store);else TLinkVPNPrivateConfigurationRecords(store);}
                @catch(NSException *error){assert([error.name isEqualToString:@"fixture"]);caught=true;}}
            catch(const std::runtime_error &error){assert(error.what()[0]=='f');caught=true;}
            assert(caught);assert(compare(@[],@{}).count==0);
        }
    }
    for(unsigned n=0;n<1000;++n){@autoreleasepool{compare(@[config(@"cycle",@"id")],ordered(@[@[@"dup",service(@"id")],@[@"new",service(@"other")]]));}}
    fallbackNames=nil;
}
int main(){@autoreleasepool{
    std::puts("VPN records Foundation: actual/frozen collector with real arrays/dictionaries/sets and controlled private providers");
    basicCases();goldenCases();mutableCases();operationCounts();lifetimeAndFaultCases();
    std::puts("VPN records passed: 3000 ordered golden cases, primary duplicates, fallback first-wins, UUID/raw identity, mutable alias/mutation fallback, fresh calls, pool lifetime, NS/C++ faults and 1000 cycles. Private VPN/device qualification pending.");
}return 0;}
