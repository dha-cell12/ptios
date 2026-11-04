#pragma once
#include <stdint.h>
@class NSMutableDictionary;
#ifdef __cplusplus
extern "C" {
#endif
void TLinkAXFixtureAttachOwner(NSMutableDictionary *row);
void TLinkAXFixtureResetOwners(void);
uint64_t TLinkAXFixtureLiveOwners(void);
uint64_t TLinkAXFixturePeakOwners(void);
uint64_t TLinkAXFixtureCreatedOwners(void);
uint64_t TLinkAXFixtureDroppedOwners(void);
void TLinkAXFixtureOwnerDidDrain(void);
#ifdef __cplusplus
}
#endif
