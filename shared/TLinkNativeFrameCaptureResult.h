#ifndef TLINK_NATIVE_FRAME_CAPTURE_RESULT_H
#define TLINK_NATIVE_FRAME_CAPTURE_RESULT_H
#import <Foundation/Foundation.h>
#include "TLinkNativeFrameCapture.h"
// RAW keeps its historical single formatter and precision.
static inline NSString *TLinkNativeFrameCaptureBody(const TLinkNativeFrameCaptureValue &v){
    return [NSString stringWithFormat:@"%u;;%d;;%d;;%d;;%.3f;;pixel;;BGRA;;%d;;%d;;%llu;;%.3f;;%.3f;;%.3f;;%.3f",
        v.id,v.width,v.height,v.bytesPerRow,v.scale,v.hasBGRA?1:0,v.hasGray?1:0,
        (unsigned long long)v.capturedAtMs,v.captureMs,v.bgraMs,v.grayMs,v.totalMs];
}
static inline NSDictionary *TLinkNativeFrameCaptureResult(const TLinkNativeFrameCaptureValue &v){
    // Keep the public numbers rounded exactly as the old wire -> JS conversion.
    NSString *scale=[NSString stringWithFormat:@"%.3f",v.scale];
    NSString *capture=[NSString stringWithFormat:@"%.3f",v.captureMs];
    NSString *bgra=[NSString stringWithFormat:@"%.3f",v.bgraMs];
    NSString *gray=[NSString stringWithFormat:@"%.3f",v.grayMs];
    NSString *total=[NSString stringWithFormat:@"%.3f",v.totalMs];
    NSString *identifier=[NSString stringWithFormat:@"%u",v.id];
    NSString *created=[NSString stringWithFormat:@"%llu",(unsigned long long)v.capturedAtMs];
    NSArray *parts=@[@"0",identifier,[NSString stringWithFormat:@"%d",v.width],
        [NSString stringWithFormat:@"%d",v.height],[NSString stringWithFormat:@"%d",v.bytesPerRow],
        scale,@"pixel",@"BGRA",v.hasBGRA?@"1":@"0",v.hasGray?@"1":@"0",created,capture,bgra,gray,total];
    NSString *raw=[[parts componentsJoinedByString:@";;"] stringByAppendingString:@"\r\n"];
    return @{@"ok":@(true),@"raw":raw,@"parts":parts,@"id":@(identifier.intValue),
        @"width":@(v.width),@"height":@(v.height),@"bytesPerRow":@(v.bytesPerRow),
        @"scale":@(scale.doubleValue),@"coord":@"pixel",@"format":@"BGRA",
        @"hasBGRA":@(v.hasBGRA),@"hasGray":@(v.hasGray),@"createdAtMs":@(created.longLongValue),
        @"captureMs":@(capture.doubleValue),@"bgraMs":@(bgra.doubleValue),
        @"grayMs":@(gray.doubleValue),@"totalMs":@(total.doubleValue)};
}
#endif
