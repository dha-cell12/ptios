#ifndef H264Stream_h
#define H264Stream_h

#import <Foundation/Foundation.h>

void startH264StreamServer(void);
NSDictionary *TLinkH264AdaptiveStreamingStatus(void);
NSDictionary *TLinkH264HandleStreamControl(NSString *base64Body, NSString **error);

#endif
