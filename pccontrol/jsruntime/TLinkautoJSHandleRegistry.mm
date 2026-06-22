#import "TLinkautoJSHandleRegistry.h"
#import <os/lock.h>

@implementation TLinkautoJSHandleRegistry {
    NSMutableDictionary *_frames;
    NSMutableDictionary *_images;
    int _nextFrameId;
    int _nextImageId;
    os_unfair_lock _lock;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _frames = [NSMutableDictionary dictionary];
        _images = [NSMutableDictionary dictionary];
        _nextFrameId = 1;
        _nextImageId = 1;
        _lock = OS_UNFAIR_LOCK_INIT;
    }
    return self;
}

- (int)registerFrame:(id)frame {
    if (!frame) return 0;
    os_unfair_lock_lock(&_lock);
    int frameId = _nextFrameId++;
    _frames[@(frameId)] = frame;
    os_unfair_lock_unlock(&_lock);
    return frameId;
}

- (id)frameForId:(int)frameId {
    os_unfair_lock_lock(&_lock);
    id frame = _frames[@(frameId)];
    os_unfair_lock_unlock(&_lock);
    return frame;
}

- (void)releaseFrame:(int)frameId {
    os_unfair_lock_lock(&_lock);
    [_frames removeObjectForKey:@(frameId)];
    os_unfair_lock_unlock(&_lock);
}

- (void)releaseAllFrames {
    os_unfair_lock_lock(&_lock);
    [_frames removeAllObjects];
    os_unfair_lock_unlock(&_lock);
}

- (int)registerImage:(id)image {
    if (!image) return 0;
    os_unfair_lock_lock(&_lock);
    int imageId = _nextImageId++;
    _images[@(imageId)] = image;
    os_unfair_lock_unlock(&_lock);
    return imageId;
}

- (id)imageForId:(int)imageId {
    os_unfair_lock_lock(&_lock);
    id image = _images[@(imageId)];
    os_unfair_lock_unlock(&_lock);
    return image;
}

- (void)releaseImage:(int)imageId {
    os_unfair_lock_lock(&_lock);
    [_images removeObjectForKey:@(imageId)];
    os_unfair_lock_unlock(&_lock);
}

- (void)releaseAllImages {
    os_unfair_lock_lock(&_lock);
    [_images removeAllObjects];
    os_unfair_lock_unlock(&_lock);
}

- (void)releaseAll {
    [self releaseAllFrames];
    [self releaseAllImages];
}

@end
