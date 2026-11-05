#import <Foundation/Foundation.h>
#include <assert.h>
#include "ax-node-pool-owner.h"
// Compile under MRC: explicitly pending autoreleases avoid ARC return-value
// elision and Foundation class-cluster lifetime assumptions in pool tests.
static uint64_t liveOwners,peakOwners,createdOwners,droppedOwners;
@interface TLinkAXFixtureNodeOwner:NSObject
@end
@implementation TLinkAXFixtureNodeOwner
-(instancetype)init {
    self=[super init];
    if(self){++liveOwners;++createdOwners;if(liveOwners>peakOwners)peakOwners=liveOwners;}
    return self;
}
-(void)dealloc {
    assert(liveOwners>0);--liveOwners;++droppedOwners;
    TLinkAXFixtureOwnerDidDrain();
    [super dealloc];
}
@end
void TLinkAXFixtureAttachOwner(NSMutableDictionary *row) {
    TLinkAXFixtureNodeOwner *owner=[[TLinkAXFixtureNodeOwner alloc] init];
    [owner autorelease];
    row[@"fixture_owner"]=owner;
}
void TLinkAXFixtureAutoreleaseOwner(void) {
    [[[TLinkAXFixtureNodeOwner alloc] init] autorelease];
}
void TLinkAXFixtureResetOwners(void){assert(liveOwners==0);peakOwners=createdOwners=droppedOwners=0;}
uint64_t TLinkAXFixtureLiveOwners(void){return liveOwners;}
uint64_t TLinkAXFixturePeakOwners(void){return peakOwners;}
uint64_t TLinkAXFixtureCreatedOwners(void){return createdOwners;}
uint64_t TLinkAXFixtureDroppedOwners(void){return droppedOwners;}
