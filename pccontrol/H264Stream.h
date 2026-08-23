#ifndef H264Stream_h
#define H264Stream_h

#import <Foundation/Foundation.h>
#include <stdint.h>

void startH264StreamServer(void);
uint64_t TLinkH264LicenseDeniedAcceptCount(void);
uint64_t TLinkH264LicenseRevokedClientCount(void);
int TLinkH264LicenseHeartbeatActive(void);
NSDictionary *TLinkH264AdaptiveStreamingStatus(void);

#endif
