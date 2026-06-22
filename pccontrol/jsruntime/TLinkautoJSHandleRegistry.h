#ifndef TLINKAUTO_JS_HANDLE_REGISTRY_H
#define TLINKAUTO_JS_HANDLE_REGISTRY_H

#import <Foundation/Foundation.h>

@interface TLinkautoJSHandleRegistry : NSObject

- (int)registerFrame:(id)frame;
- (id)frameForId:(int)frameId;
- (void)releaseFrame:(int)frameId;
- (void)releaseAllFrames;

- (int)registerImage:(id)image;
- (id)imageForId:(int)imageId;
- (void)releaseImage:(int)imageId;
- (void)releaseAllImages;

- (void)releaseAll;

@end

#endif /* TLINKAUTO_JS_HANDLE_REGISTRY_H */
