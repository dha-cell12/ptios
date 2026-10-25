#ifndef TLINK_NATIVE_IMAGE_RESULT_H
#define TLINK_NATIVE_IMAGE_RESULT_H
#import <Foundation/Foundation.h>
#include "TLinkNativeImageValue.h"
static inline NSString *TLinkNativeImageBody(const TLinkNativeImageValue &v){
    return [NSString stringWithFormat:@"%u;;%d;;%d",v.id,v.width,v.height];
}
static inline NSDictionary *TLinkNativeImageResult(const TLinkNativeImageValue &v){
    NSString *identifier=[NSString stringWithFormat:@"%u",v.id];
    NSArray *parts=@[@"0",identifier,[NSString stringWithFormat:@"%d",v.width],[NSString stringWithFormat:@"%d",v.height]];
    NSString *raw=[[parts componentsJoinedByString:@";;"] stringByAppendingString:@"\r\n"];
    // Preserve the old NSString intValue conversion of the unsigned ID.
    return @{@"ok":@(true),@"raw":raw,@"parts":parts,@"id":@(identifier.intValue),@"width":@(v.width),@"height":@(v.height)};
}
#endif
