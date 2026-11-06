#include "TouchIndicatorWindow.h"
#include "../Screen.h"
#include "../Common.h"
#include "../../shared/TLinkTouchPayload.h"
#include "../../shared/TLinkIndicatorPresentation.h"
#import <QuartzCore/QuartzCore.h>
#import "TouchIndicatorView.h"
#import "TouchIndicatorCoordinateView.h"
#include "../headers/IOHIDEventSystemClient.h"
#include <stdint.h>
#include <math.h>

#define COORDINATE_VIEW_HEIGHT 20

// All lifecycle state, HID callbacks and UIKit objects have the main run loop as owner.
enum TLinkIndicatorState {
    TLinkIndicatorStopped,
    TLinkIndicatorStarting,
    TLinkIndicatorRunning,
    TLinkIndicatorStopping,
};
static TLinkIndicatorState indicatorState = TLinkIndicatorStopped;
static uintptr_t indicatorGeneration = 0;
static IOHIDEventSystemClientRef ioHIDEventSystemClient = NULL;
static TouchIndicatorWindow *touchIndicatorWindow = nil;
static CGFloat screenBoundsWidth = 0;
static CGFloat screenBoundsHeight = 0;
static CGFloat scale = 0;

static void IOHIDEventCallbackForTouchIndicator(void *target, void *refcon, IOHIDEventQueueRef queue, IOHIDEventRef event);

// BEGIN indicator HID ownership core (also compiled by the host regression harness).
static bool zx_indicatorValidFingerIndex(int index)
{
    return index >= 0 && index < kTLinkTouchMaxFingerCount;
}

static bool zx_indicatorAcceptsCallback(void *refcon)
{
    return indicatorState == TLinkIndicatorRunning && ioHIDEventSystemClient != NULL &&
           (uintptr_t)refcon == indicatorGeneration;
}

static bool zx_indicatorStartClientOnMain(void)
{
    if (indicatorState != TLinkIndicatorStarting || ioHIDEventSystemClient != NULL) return false;
    ioHIDEventSystemClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!ioHIDEventSystemClient) return false;
    if (++indicatorGeneration == 0) ++indicatorGeneration;
    IOHIDEventSystemClientRegisterEventCallback(ioHIDEventSystemClient,
        IOHIDEventCallbackForTouchIndicator,
        NULL, (void *)indicatorGeneration);
    IOHIDEventSystemClientScheduleWithRunLoop(ioHIDEventSystemClient, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    indicatorState = TLinkIndicatorRunning;
    return true;
}

static void zx_indicatorStopClientOnMain(void)
{
    indicatorState = TLinkIndicatorStopping; // Reject callbacks before unregistering/releasing ownership.
    if (ioHIDEventSystemClient) {
        IOHIDEventSystemClientUnregisterEventCallback(ioHIDEventSystemClient);
        IOHIDEventSystemClientUnscheduleWithRunLoop(ioHIDEventSystemClient, CFRunLoopGetMain(), kCFRunLoopCommonModes);
        CFRelease(ioHIDEventSystemClient);
        ioHIDEventSystemClient = NULL;
    }
    indicatorState = TLinkIndicatorStopped;
}
// END indicator HID ownership core.

static void zx_indicatorPerformOnMain(dispatch_block_t operation)
{
    if ([NSThread isMainThread]) operation();
    else dispatch_sync(dispatch_get_main_queue(), operation);
}

static NSError *zx_indicatorError(NSString *message)
{
    return [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999
        userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;%@\r\n", message]}];
}

struct TLinkIndicatorColor {
    CGFloat red = 255;
    CGFloat green = 0;
    CGFloat blue = 0;
    CGFloat alpha = 0.7;
};

static NSError *zx_indicatorLoadColor(BOOL requireFile, TLinkIndicatorColor *color)
{
    NSString *path = getCommonConfigFilePath();
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return requireFile ? zx_indicatorError(@"Touch indicator configuration file is missing.") : nil;
    }
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:path];
    if (!config) return zx_indicatorError(@"Unable to read touch indicator configuration.");
    id settings = config[@"touch_indicator"];
    if (!settings) return nil;
    if (![settings isKindOfClass:[NSDictionary class]]) return zx_indicatorError(@"Invalid touch indicator configuration.");
    id values = settings[@"color"];
    if (!values) return nil;
    if (![values isKindOfClass:[NSDictionary class]]) return zx_indicatorError(@"Invalid touch indicator color configuration.");
    NSString *keys[] = {@"r", @"g", @"b", @"alpha"};
    CGFloat *components[] = {&color->red, &color->green, &color->blue, &color->alpha};
    for (int i = 0; i < 4; i++) {
        id value = values[keys[i]];
        if (!value) continue;
        if (![value respondsToSelector:@selector(doubleValue)] || !isfinite([value doubleValue])) {
            return zx_indicatorError(@"Invalid touch indicator color component.");
        }
        *components[i] = (CGFloat)[value doubleValue];
    }
    return nil;
}

static void zx_indicatorStopOnMain(void)
{
    zx_indicatorStopClientOnMain();
    [touchIndicatorWindow hide];
    touchIndicatorWindow = nil;
}

static NSError *zx_indicatorStartOnMain(void)
{
    if (indicatorState != TLinkIndicatorStopped) return zx_indicatorError(@"Touch indicator is already showing.");
    indicatorState = TLinkIndicatorStarting;
    TLinkIndicatorColor color;
    NSError *failure = zx_indicatorLoadColor(NO, &color);
    if (!failure) {
        CGRect bounds = [Screen getBounds];
        scale = [Screen getScale];
        screenBoundsWidth = MIN(CGRectGetWidth(bounds), CGRectGetHeight(bounds));
        screenBoundsHeight = MAX(CGRectGetWidth(bounds), CGRectGetHeight(bounds));
        if (!isfinite(screenBoundsWidth) || !isfinite(screenBoundsHeight) || !isfinite(scale) ||
            screenBoundsWidth <= 0 || screenBoundsHeight <= 0 || scale <= 0) {
            failure = zx_indicatorError(@"Cannot get screen bounds for the touch indicator.");
        }
    }
    if (!failure) {
        touchIndicatorWindow = [[TouchIndicatorWindow alloc] init];
        if (!touchIndicatorWindow) failure = zx_indicatorError(@"Unable to create the touch indicator window.");
    }
    if (!failure) {
        [touchIndicatorWindow setIndicatorColorWithRed:color.red green:color.green blue:color.blue alpha:color.alpha];
        if (!zx_indicatorStartClientOnMain()) failure = zx_indicatorError(@"Unable to create the touch indicator HID client.");
    }
    if (failure) {
        zx_indicatorStopOnMain();
        return failure;
    }
    [touchIndicatorWindow show];
    return nil;
}

void startTouchIndicator(NSError **error)
{
    // Only an owned NSError object crosses this synchronous boundary, never the caller's NSError**.
    __block NSError *result = nil;
    zx_indicatorPerformOnMain(^{ result = zx_indicatorStartOnMain(); });
    if (error) *error = result;
}

void stopTouchIndicator(NSError **error)
{
    zx_indicatorPerformOnMain(^{ zx_indicatorStopOnMain(); });
    if (error) *error = nil;
}

void handleTouchIndicatorTaskWithRawData(UInt8 *eventData, NSError **error)
{
    NSString *raw = eventData ? [NSString stringWithUTF8String:(const char *)eventData] : nil;
    NSString *action = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    int value = [action isEqualToString:@"0"] ? 0 : [action isEqualToString:@"1"] ? 1 : [action isEqualToString:@"2"] ? 2 : -1;
    handleTouchIndicatorAction(value, error);
}

void handleTouchIndicatorAction(int action, NSError **error)
{
    if (action == 0) {
        stopTouchIndicator(error);
    } else if (action == 1) {
        startTouchIndicator(error);
    } else if (action == 2) {
        __block NSError *result = nil;
        zx_indicatorPerformOnMain(^{
            if (indicatorState != TLinkIndicatorRunning) {
                result = zx_indicatorError(@"Cannot reload configuration while the touch indicator is stopped.");
                return;
            }
            TLinkIndicatorColor color;
            result = zx_indicatorLoadColor(YES, &color);
            if (!result) [touchIndicatorWindow setIndicatorColorWithRed:color.red green:color.green blue:color.blue alpha:color.alpha];
        });
        if (error) *error = result;
    } else {
        if (error) *error = zx_indicatorError(@"Unknown touch indicator action; expected 0, 1 or 2.");
    }
}

static void IOHIDEventCallbackForTouchIndicator(void *target, void *refcon, IOHIDEventQueueRef queue, IOHIDEventRef parentEvent)
{
    if (!zx_indicatorAcceptsCallback(refcon) || !touchIndicatorWindow || !parentEvent ||
        IOHIDEventGetType(parentEvent) != kIOHIDEventTypeDigitizer) return;
    @autoreleasepool {
        CFArrayRef children = IOHIDEventGetChildren(parentEvent);
        if (!children) return;
        for (CFIndex i = 0; i < CFArrayGetCount(children); i++) {
            IOHIDEventRef event = (IOHIDEventRef)CFArrayGetValueAtIndex(children, i);
            if (!event || IOHIDEventGetType(event) != kIOHIDEventTypeDigitizer) continue;
            CFIndex rawIndex = IOHIDEventGetIntegerValue(event, (IOHIDEventField)kIOHIDEventFieldDigitizerIndex);
            if (rawIndex < 0 || rawIndex >= kTLinkTouchMaxFingerCount) continue;
            int index = (int)rawIndex;
            int mask = IOHIDEventGetIntegerValue(event, (IOHIDEventField)kIOHIDEventFieldDigitizerEventMask);
            int touch = IOHIDEventGetIntegerValue(event, (IOHIDEventField)kIOHIDEventFieldDigitizerTouch);
            CGFloat x = IOHIDEventGetFloatValue(event, (IOHIDEventField)kIOHIDEventFieldDigitizerX) * screenBoundsWidth;
            CGFloat y = IOHIDEventGetFloatValue(event, (IOHIDEventField)kIOHIDEventFieldDigitizerY) * screenBoundsHeight;
            CGFloat radius = IOHIDEventGetFloatValue(event, 0xb0014);
            if (!touch && (mask & 2)) [touchIndicatorWindow hideIndicator:index];
            else if (isfinite(x) && isfinite(y) && isfinite(radius) && radius >= 0) {
                if (touch && (mask & 2)) [touchIndicatorWindow showIndicator:index withX:x andY:y majorRadius:radius];
                else if (touch && (mask & 4)) [touchIndicatorWindow moveIndicator:index x:x y:y majorRadius:radius];
            }
        }
    }
}

// BEGIN indicator presentation.
@interface TouchIndicatorWindow (Presentation)
- (void)flushIndicatorMoves:(CADisplayLink *)link;
- (void)flushPendingIndicatorMoves;
- (void)scheduleIndicatorMoves;
- (BOOL)applyIndicator:(int)index point:(const TLinkIndicatorPresentation::Point &)point;
@end

@interface TLinkIndicatorDisplayTarget : NSObject
@property(nonatomic,weak) TouchIndicatorWindow *window;
- (void)tick:(CADisplayLink *)link;
@end
@implementation TLinkIndicatorDisplayTarget
- (void)tick:(CADisplayLink *)link
{
    TouchIndicatorWindow *window=self.window;
    if(window)[window flushIndicatorMoves:link];
    else [link invalidate];
}
@end

@implementation TouchIndicatorWindow {
    UIWindow *_window;
    TouchIndicatorView *touchIndicatorViewList[kTLinkTouchMaxFingerCount];
    TouchIndicatorCoordinateView *coordinateView[kTLinkTouchMaxFingerCount];
    UIColor *indicatorColor;
    UIFont *_coordinateFont;
    NSDictionary *_coordinateAttributes;
    CADisplayLink *_displayLink;
    TLinkIndicatorPresentation::Slots<kTLinkTouchMaxFingerCount> _moves;
    struct {bool valid=false;int x=0,y=0;CGFloat width=0;} _labels[kTLinkTouchMaxFingerCount];
    BOOL _visible;
}

- (id)init
{
    NSAssert([NSThread isMainThread], @"Touch indicator UI must be owned by main.");
    self = [super init];
    if (self) {
        _window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, screenBoundsWidth, screenBoundsHeight)];
        if (!_window) return nil;
        _window.windowLevel = UIWindowLevelAlert;
        _window.backgroundColor = [UIColor clearColor];
        _window.userInteractionEnabled = NO;
        _window.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _window.hidden = YES;
        indicatorColor = [UIColor colorWithRed:1 green:0 blue:0 alpha:0.7];
        _coordinateFont = [UIFont fontWithName:@"Trebuchet MS" size:11.0] ?: [UIFont systemFontOfSize:11.0];
        _coordinateAttributes = @{NSFontAttributeName:_coordinateFont};
    }
    return self;
}

- (void)hideIndicator:(int)index
{
    NSAssert([NSThread isMainThread], @"Touch indicator UI must be owned by main.");
    if (!zx_indicatorValidFingerIndex(index)) return;
    _moves.hide(index);
    _labels[index].valid=false;
    if(!_moves.pending())_displayLink.paused=YES;
    [touchIndicatorViewList[index] removeFromSuperview];
    touchIndicatorViewList[index] = nil;
    [coordinateView[index] removeFromSuperview];
    coordinateView[index] = nil;
}

- (void)showIndicator:(int)index withX:(CGFloat)x andY:(CGFloat)y majorRadius:(CGFloat)radius
{
    NSAssert([NSThread isMainThread], @"Touch indicator UI must be owned by main.");
    if (!zx_indicatorValidFingerIndex(index) || !_visible) return;
    TLinkIndicatorPresentation::Point point(x,y,radius);int labelX=0,labelY=0;
    if(!TLinkIndicatorPresentation::Layout(point,scale,SIZE_INDIACTOR_TOUCH_RADIUS_RATIO,labelX,labelY))return;
    [self hideIndicator:index];
    CGFloat size = radius * SIZE_INDIACTOR_TOUCH_RADIUS_RATIO;
    CGFloat half = size / 2;
    TouchIndicatorView *indicator = [[TouchIndicatorView alloc] initWithFrame:CGRectMake(x - half, y - half, size, size)];
    indicator.layer.cornerRadius = half;
    indicator.backgroundColor = indicatorColor;
    NSString *text = [NSString stringWithFormat:@"(%d, %d)", labelX, labelY];
    CGFloat width = [text sizeWithAttributes:_coordinateAttributes].width + 5;
    TouchIndicatorCoordinateView *coordinate = [[TouchIndicatorCoordinateView alloc] initWithFrame:CGRectMake(x + half + 5, y, width, COORDINATE_VIEW_HEIGHT)];
    coordinate.backgroundColor = indicatorColor;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, width, COORDINATE_VIEW_HEIGHT)];
    label.text = text;
    label.textColor = [UIColor whiteColor];
    label.backgroundColor = [UIColor clearColor];
    label.font = _coordinateFont;
    [coordinate addSubview:label];
    coordinate.coordinateLabel = label;
    touchIndicatorViewList[index] = indicator;
    coordinateView[index] = coordinate;
    [_window addSubview:indicator];
    [_window addSubview:coordinate];
    _labels[index].valid=true;_labels[index].x=labelX;_labels[index].y=labelY;_labels[index].width=width;
    _moves.show(index,point);
}

- (void)show
{
    NSAssert([NSThread isMainThread], @"Touch indicator UI must be owned by main.");
    _visible = YES;
    _window.hidden = NO;
}

- (void)hide
{
    NSAssert([NSThread isMainThread], @"Touch indicator UI must be owned by main.");
    [_displayLink invalidate];_displayLink=nil;
    _moves.clear();
    _visible = NO;
    _window.hidden = YES;
    for (int i = 0; i < kTLinkTouchMaxFingerCount; i++) [self hideIndicator:i];
}

- (void)setIndicatorColorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha
{
    NSAssert([NSThread isMainThread], @"Touch indicator UI must be owned by main.");
    indicatorColor = [UIColor colorWithRed:red/255 green:green/255 blue:blue/255 alpha:alpha];
    for (int i = 0; i < kTLinkTouchMaxFingerCount; i++) {
        touchIndicatorViewList[i].backgroundColor = indicatorColor;
        coordinateView[i].backgroundColor = indicatorColor;
    }
}

- (void)moveIndicator:(int)index x:(CGFloat)x y:(CGFloat)y majorRadius:(CGFloat)radius
{
    NSAssert([NSThread isMainThread], @"Touch indicator UI must be owned by main.");
    if (!zx_indicatorValidFingerIndex(index) || !_visible || !touchIndicatorViewList[index]) return;
    TLinkIndicatorPresentation::Point point(x,y,radius);int labelX=0,labelY=0;
    if(!TLinkIndicatorPresentation::Layout(point,scale,SIZE_INDIACTOR_TOUCH_RADIUS_RATIO,labelX,labelY))return;
    if(_moves.move(index,point))[self scheduleIndicatorMoves];
    else if(!_moves.pending())_displayLink.paused=YES;
}

- (BOOL)applyIndicator:(int)index point:(const TLinkIndicatorPresentation::Point &)point
{
    if (!zx_indicatorValidFingerIndex(index) || !_visible || !touchIndicatorViewList[index]) return NO;
    int labelX=0,labelY=0;
    if(!TLinkIndicatorPresentation::Layout(point,scale,SIZE_INDIACTOR_TOUCH_RADIUS_RATIO,labelX,labelY))return NO;
    TouchIndicatorView *indicator=touchIndicatorViewList[index];
    TouchIndicatorCoordinateView *coordinate=coordinateView[index];
    UILabel *label=coordinate.coordinateLabel;
    CGFloat x=point.x,y=point.y;
    CGFloat size = point.radius * SIZE_INDIACTOR_TOUCH_RADIUS_RATIO;
    CGFloat half = size / 2;
    CGFloat width=_labels[index].width;
    BOOL updateLabel=!_labels[index].valid||_labels[index].x!=labelX||_labels[index].y!=labelY;
    NSString *text=nil;
    if(updateLabel){
        text=[NSString stringWithFormat:@"(%d, %d)",labelX,labelY];
        width=[text sizeWithAttributes:_coordinateAttributes].width+5;
        if(touchIndicatorViewList[index]==indicator&&coordinateView[index]==coordinate)_labels[index].valid=false;
    }
    // Keep the reached views alive; a reentrant UP/DOWN must not redirect old writes to its replacement.
    indicator.frame=CGRectMake(x-half,y-half,size,size);
    indicator.layer.cornerRadius=half;
    if(updateLabel){
        label.text=text;label.frame=CGRectMake(0,0,width,COORDINATE_VIEW_HEIGHT);
        if(touchIndicatorViewList[index]==indicator&&coordinateView[index]==coordinate){
            _labels[index].valid=true;_labels[index].x=labelX;_labels[index].y=labelY;_labels[index].width=width;
        }
    }
    coordinate.frame=CGRectMake(x+half+5,y,width,COORDINATE_VIEW_HEIGHT);
    return YES;
}

- (void)scheduleIndicatorMoves
{
    if(_displayLink){_displayLink.paused=NO;return;}
    // Display scheduling is optional: allocation/setup refusal keeps immediate feedback.
    BOOL scheduled=NO;
    @try{try{
        TLinkIndicatorDisplayTarget *target=[TLinkIndicatorDisplayTarget new];target.window=self;
        CADisplayLink *link=target?[CADisplayLink displayLinkWithTarget:target selector:@selector(tick:)]:nil;
        if(link){_displayLink=link;[link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];scheduled=YES;}
    }catch(...){scheduled=NO;}}
    @catch(NSException *exception){(void)exception;scheduled=NO;}
    if(!scheduled){[_displayLink invalidate];_displayLink=nil;[self flushPendingIndicatorMoves];}
}

- (void)flushPendingIndicatorMoves
{
    @autoreleasepool{
        for(int index=0;index<kTLinkTouchMaxFingerCount;++index){
            TLinkIndicatorPresentation::Slots<kTLinkTouchMaxFingerCount>::Ticket ticket;
            if(!_moves.peek(index,ticket)||!_moves.begin(index,ticket))continue;
            if([self applyIndicator:index point:ticket.point])_moves.complete(index,ticket);
            else _moves.hide(index);
        }
        if(!_moves.pending())_displayLink.paused=YES;
    }
}

- (void)flushIndicatorMoves:(CADisplayLink *)link
{
    NSAssert([NSThread isMainThread], @"Touch indicator UI must be owned by main.");
    if(link!=_displayLink||!_visible)return;
    [self flushPendingIndicatorMoves];
}

- (void)dealloc
{
    [_displayLink invalidate];
}

@end
// END indicator presentation.
