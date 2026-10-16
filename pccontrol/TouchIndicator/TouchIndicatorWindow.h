#ifndef TOUCH_INDICATOR_H
#define TOUCH_INDICATOR_H

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Lifecycle entry points complete synchronously on main; NSError** is never retained by async work.
void handleTouchIndicatorTaskWithRawData(UInt8* eventData, NSError **error);
void stopTouchIndicator(NSError **error);
void startTouchIndicator(NSError **error);

// Window methods are main-thread-only; use the lifecycle entry points from other threads.
@interface TouchIndicatorWindow : NSObject
{

}

- (id)init;
- (void)hideIndicator:(int)index;
- (void)showIndicator:(int)index withX:(CGFloat)x andY:(CGFloat)y majorRadius:(CGFloat)radius;
- (void)show;
- (void)hide;
- (void)moveIndicator:(int)index x:(CGFloat)x y:(CGFloat)y majorRadius:(CGFloat)radius;
- (void)setIndicatorColorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha;

@end

#endif