// OpenCV headers in this repo's opencv2.framework are exposed flat under:
//   frameworks/opencv2.framework/Headers/
// The original project code includes <opencv.hpp> and <imgcodecs/ios.h>.
// For tool builds (zxtouchd/zxtouchb), we add explicit -I to that Headers/
// directory in zxtouch-binary/Makefile, so these includes resolve reliably.

#ifndef TEMPLATE_MATCH_H
#define TEMPLATE_MATCH_H

#ifdef __cplusplus
  // Keep the include style consistent with the previously working build.
  // The bundled opencv2.framework in this repo exposes headers via a flat
  // Headers/ layout where <opencv.hpp> is the supported umbrella header.
  #undef NO
  #undef YES
  #import <opencv.hpp>
  #import <imgcodecs/ios.h>
#endif


//
//  TemplateMatch.hpp
//  OpenCVTest
//
//  Created by Yun CHEN on 2018/2/8.
//  Copyright © 2018年 Yun CHEN. All rights reserved.
//


#import <UIKit/UIKit.h>
#import <CoreMedia/CoreMedia.h>

@interface TemplateMatch : NSObject

@property(nonatomic,strong) UIImage *templateImage;     //模板图片。由于匹配方法会被多次调用，所以模板图片适合单次设定。

//在Buffer中匹配预设的模板，如果成功则返回位置以及区域大小。
//这里返回的Rect基于AVCapture Metadata的坐标系统，即值在0.0-1.0之间，方便AVCaptureVideoPreviewLayer类进行转换。
- (CGRect)templateMatchWithPath:(NSString*)imgPath templatePath:(NSString*)templatePath error:(NSError**)err;
- (CGRect)templateMatchWithUIImage:(UIImage*)img template:(UIImage*)templ;
- (CGRect)templateMatchWithCGImage:(CGImageRef)img templatePath:(NSString*)templatePath error:(NSError**)err;

- (void)setScaleRation:(float)sr;
- (void)setAcceptableValue:(float)av;
- (void)setMaxTryTimes:(int)mtt;

@end

#endif /* TEMPLATE_MATCH_H */
