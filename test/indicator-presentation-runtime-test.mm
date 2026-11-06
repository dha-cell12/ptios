#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <cassert>
#include <cstdio>
#include <limits>
#include <stdexcept>
#include "../shared/TLinkTouchPayload.h"
#include "../shared/TLinkIndicatorPresentation.h"
static const CGFloat screenBoundsWidth=390,screenBoundsHeight=844,scale=3;
static const CGFloat UIWindowLevelAlert=2000;
static const NSUInteger UIViewAutoresizingFlexibleWidth=1,UIViewAutoresizingFlexibleHeight=2;
#define COORDINATE_VIEW_HEIGHT 20
#define SIZE_INDIACTOR_TOUCH_RADIUS_RATIO 1590
#define NSFontAttributeName @"FixtureFont"
static bool zx_indicatorValidFingerIndex(int index){return index>=0&&index<kTLinkTouchMaxFingerCount;}
static unsigned views=0,frameWrites=0,labelWrites=0,widthQueries=0,scheduledLinks=0;
static unsigned linkMode=0,viewFault=0,viewFaultAfter=0;
static dispatch_block_t onFrame;
static void viewStage(){
    dispatch_block_t action=onFrame;onFrame=nil;if(action)action();
    if(viewFaultAfter&&--viewFaultAfter)return;
    unsigned fault=viewFault;viewFault=0;
    if(fault==1)[NSException raise:@"IndicatorFixture" format:@"view"];
    if(fault==2)throw std::runtime_error("view");
}
@interface UIColor:NSObject
@property(nonatomic,copy) NSArray *components;
+(instancetype)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
+(instancetype)clearColor;
+(instancetype)whiteColor;
@end
@implementation UIColor
+(instancetype)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a{UIColor *color=[self new];color.components=@[@(r),@(g),@(b),@(a)];return color;}
+(instancetype)clearColor{return [self colorWithRed:0 green:0 blue:0 alpha:0];}
+(instancetype)whiteColor{return [self colorWithRed:1 green:1 blue:1 alpha:1];}
@end
@interface UIFont:NSObject
+(instancetype)fontWithName:(NSString *)name size:(CGFloat)size;
+(instancetype)systemFontOfSize:(CGFloat)size;
@end
@implementation UIFont
+(instancetype)fontWithName:(NSString *)name size:(CGFloat)size{(void)name;(void)size;return [self new];}
+(instancetype)systemFontOfSize:(CGFloat)size{(void)size;return [self new];}
@end
@interface IndicatorLayer:NSObject
@property(nonatomic) CGFloat cornerRadius;
@end
@implementation IndicatorLayer
@end
@interface UIView:NSObject
@property(nonatomic) CGRect frame;
@property(nonatomic,strong) IndicatorLayer *layer;
@property(nonatomic,strong) UIColor *backgroundColor;
@property(nonatomic,weak) UIView *superview;
@property(nonatomic,strong) NSMutableArray<UIView *> *subviews;
@property(nonatomic) BOOL hidden;
@property(nonatomic) BOOL userInteractionEnabled;
@property(nonatomic) NSUInteger autoresizingMask;
-(instancetype)initWithFrame:(CGRect)frame;
-(void)addSubview:(UIView *)view;
-(void)removeFromSuperview;
@end
@implementation UIView
@synthesize frame=_frame;
-(instancetype)initWithFrame:(CGRect)frame{self=[super init];if(self){++views;_frame=frame;_layer=[IndicatorLayer new];_subviews=[NSMutableArray array];}return self;}
-(void)setFrame:(CGRect)frame{++frameWrites;viewStage();_frame=frame;}
-(void)addSubview:(UIView *)view{[view removeFromSuperview];[self.subviews addObject:view];view.superview=self;}
-(void)removeFromSuperview{[self.superview.subviews removeObjectIdenticalTo:self];self.superview=nil;}
-(void)dealloc{assert(views);--views;}
@end
@interface UIWindow:UIView
@property(nonatomic) CGFloat windowLevel;
@end
@implementation UIWindow
@end
@interface UILabel:UIView
@property(nonatomic,copy) NSString *text;
@property(nonatomic,strong) UIColor *textColor;
@property(nonatomic,strong) UIFont *font;
@end
@implementation UILabel
@synthesize text=_text;
-(void)setText:(NSString *)text{++labelWrites;_text=[text copy];}
@end
@interface TouchIndicatorView:UIView
@end
@implementation TouchIndicatorView
@end
@interface TouchIndicatorCoordinateView:UIView
@property(nonatomic,strong) UILabel *coordinateLabel;
@end
@implementation TouchIndicatorCoordinateView
@end
@interface NSString (IndicatorMeasure)
-(CGSize)sizeWithAttributes:(NSDictionary *)attributes;
@end
@implementation NSString (IndicatorMeasure)
-(CGSize)sizeWithAttributes:(NSDictionary *)attributes{assert(attributes[NSFontAttributeName]);++widthQueries;return CGSizeMake(self.length*7,11);}
@end

@class IndicatorFixtureDisplayLink;
@protocol IndicatorFixtureTick
-(void)tick:(IndicatorFixtureDisplayLink *)link;
@end
@interface IndicatorFixtureDisplayLink:NSObject
@property(nonatomic,strong) id target;
@property(nonatomic) SEL selector;
@property(nonatomic) BOOL paused;
@property(nonatomic) BOOL scheduled;
+(instancetype)displayLinkWithTarget:(id)target selector:(SEL)selector;
-(void)addToRunLoop:(NSRunLoop *)loop forMode:(NSString *)mode;
-(void)invalidate;
-(void)fire;
@end
@implementation IndicatorFixtureDisplayLink
+(instancetype)displayLinkWithTarget:(id)target selector:(SEL)selector{
    if(linkMode==1)return nil;
    if(linkMode==2)[NSException raise:@"IndicatorFixture" format:@"factory"];
    if(linkMode==3)throw std::runtime_error("factory");
    IndicatorFixtureDisplayLink *link=[self new];link.target=target;link.selector=selector;return link;
}
-(void)addToRunLoop:(NSRunLoop *)loop forMode:(NSString *)mode{
    assert(loop==[NSRunLoop mainRunLoop]&&[mode isEqual:NSRunLoopCommonModes]&&!self.scheduled);
    self.scheduled=YES;++scheduledLinks;
    if(linkMode==4)[NSException raise:@"IndicatorFixture" format:@"registration"];
    if(linkMode==5)throw std::runtime_error("registration");
}
-(void)invalidate{if(self.scheduled){assert(scheduledLinks);--scheduledLinks;self.scheduled=NO;}self.target=nil;}
-(void)fire{if(self.scheduled&&!self.paused){assert(self.selector==@selector(tick:));[(id<IndicatorFixtureTick>)self.target tick:self];}}
-(void)dealloc{assert(!self.scheduled);}
@end
#include "BeforeIndicatorWindow.inc"
#include "CurrentIndicatorWindow.inc"

static IndicatorFixtureDisplayLink *linkFor(id window){return [window valueForKey:@"_displayLink"];}
static NSArray *rect(CGRect value){return @[@(value.origin.x),@(value.origin.y),@(value.size.width),@(value.size.height)];}
static NSDictionary *snapshot(id window){
    UIWindow *root=[window valueForKey:@"_window"];NSMutableArray *rows=[NSMutableArray array];
    for(UIView *view in root.subviews){
        if([view isKindOfClass:[TouchIndicatorCoordinateView class]]){
            UILabel *label=((TouchIndicatorCoordinateView *)view).coordinateLabel;
            [rows addObject:@[@"label",rect(view.frame),view.backgroundColor.components,label.text,rect(label.frame)]];
        }else [rows addObject:@[@"touch",rect(view.frame),view.backgroundColor.components,@(view.layer.cornerRadius)]];
    }
    return @{@"hidden":@(root.hidden),@"rows":rows};
}
static void reset(){assert(views==0&&scheduledLinks==0&&!onFrame);frameWrites=labelWrites=widthQueries=0;linkMode=viewFault=viewFaultAfter=0;}
static void parityCases(){
    for(unsigned n=0;n<128;++n){
        @autoreleasepool{
            reset();BeforeIndicatorWindow *old=[BeforeIndicatorWindow new];CurrentIndicatorWindow *current=[CurrentIndicatorWindow new];[old show];[current show];
            for(int index=0;index<20;++index){[old showIndicator:index withX:index andY:n majorRadius:.01];[current showIndicator:index withX:index andY:n majorRadius:.01];}
            assert([snapshot(old) isEqual:snapshot(current)]);
            for(unsigned move=0;move<80;++move){int index=int(move%20);CGFloat x=CGFloat(n+move)/3,y=-CGFloat(move)/7,radius=.001+double(move%9)/1000;
                [old moveIndicator:index x:x y:y majorRadius:radius];[current moveIndicator:index x:x y:y majorRadius:radius];
            }
            [linkFor(current) fire];assert([snapshot(old) isEqual:snapshot(current)]&&linkFor(current).paused);
            [old setIndicatorColorWithRed:12 green:34 blue:56 alpha:.5];[current setIndicatorColorWithRed:12 green:34 blue:56 alpha:.5];
            for(int index:{0,19}){[old hideIndicator:index];[current hideIndicator:index];}
            assert([snapshot(old) isEqual:snapshot(current)]);[old hide];[current hide];
        }
        assert(views==0&&scheduledLinks==0);
    }
}
static void cadenceCases(){
    @autoreleasepool{
        reset();CurrentIndicatorWindow *window=[CurrentIndicatorWindow new];[window show];[window showIndicator:0 withX:1 andY:2 majorRadius:.01];
        unsigned before=frameWrites,labels=labelWrites,widths=widthQueries;
        for(unsigned n=0;n<1000;++n)[window moveIndicator:0 x:double(n+1)/10 y:double(n+2)/10 majorRadius:.02];
        assert(frameWrites==before&&labelWrites==labels&&widthQueries==widths&&scheduledLinks==1);
        IndicatorFixtureDisplayLink *link=linkFor(window);[link fire];
        assert(frameWrites==before+3&&labelWrites==labels+1&&widthQueries==widths+1&&link.paused);
        before=frameWrites;labels=labelWrites;widths=widthQueries;
        [window moveIndicator:0 x:100 y:100.1 majorRadius:.02];assert(link.paused);[link fire];assert(frameWrites==before);
        [window moveIndicator:0 x:100.01 y:100.11 majorRadius:.03];[link fire];
        assert(frameWrites==before+2&&labelWrites==labels&&widthQueries==widths);
        [window moveIndicator:0 x:9 y:9 majorRadius:.02];[window hideIndicator:0];[link fire];assert([snapshot(window)[@"rows"] count]==0&&link.paused);
        [window showIndicator:0 withX:4 andY:5 majorRadius:.01];[window moveIndicator:0 x:10 y:11 majorRadius:.02];
        id oldTarget=link.target;[window hide];[window show];[window showIndicator:0 withX:6 andY:7 majorRadius:.01];NSDictionary *shown=snapshot(window);
        [oldTarget tick:link];assert([snapshot(window) isEqual:shown]&&scheduledLinks==0);
        [window moveIndicator:0 x:12 y:13 majorRadius:.02];assert(linkFor(window)!=link);[oldTarget tick:link];assert([snapshot(window) isEqual:shown]);
        [linkFor(window) fire];[window hide];
    }
    assert(views==0&&scheduledLinks==0);
}
static void failureCases(){
    for(unsigned mode=1;mode<=5;++mode){
        @autoreleasepool{
            reset();CurrentIndicatorWindow *window=[CurrentIndicatorWindow new];BeforeIndicatorWindow *old=[BeforeIndicatorWindow new];[window show];[old show];
            [window showIndicator:19 withX:1 andY:2 majorRadius:.01];[old showIndicator:19 withX:1 andY:2 majorRadius:.01];
            linkMode=mode;[window moveIndicator:19 x:3 y:4 majorRadius:.02];[old moveIndicator:19 x:3 y:4 majorRadius:.02];
            assert([snapshot(window) isEqual:snapshot(old)]&&!linkFor(window)&&scheduledLinks==0);
            linkMode=0;[window moveIndicator:19 x:5 y:6 majorRadius:.03];[linkFor(window) fire];[old moveIndicator:19 x:5 y:6 majorRadius:.03];
            assert([snapshot(window) isEqual:snapshot(old)]);[window hide];[old hide];
        }
        assert(views==0&&scheduledLinks==0);
    }
    for(unsigned kind:{1U,2U}){
        @autoreleasepool{
            reset();CurrentIndicatorWindow *window=[CurrentIndicatorWindow new];[window show];[window showIndicator:0 withX:1 andY:2 majorRadius:.01];
            NSDictionary *original=snapshot(window);
            [window moveIndicator:0 x:3 y:4 majorRadius:.02];viewFault=kind;viewFaultAfter=3;bool caught=false;
            @try{try{[linkFor(window) fire];}catch(const std::runtime_error &){caught=kind==2;}}
            @catch(NSException *exception){caught=kind==1&&[exception.name isEqual:@"IndicatorFixture"];}
            assert(caught&&!linkFor(window).paused);
            [window moveIndicator:0 x:1 y:2 majorRadius:.01];[linkFor(window) fire];
            assert(linkFor(window).paused&&[snapshot(window) isEqual:original]);[window hide];
        }
        assert(views==0&&scheduledLinks==0);
    }
}
static void lifecycleCases(){
    __weak CurrentIndicatorWindow *weak;
    for(unsigned n=0;n<128;++n){
        @autoreleasepool{
            reset();CurrentIndicatorWindow *window=[CurrentIndicatorWindow new];weak=window;[window show];[window showIndicator:0 withX:1 andY:2 majorRadius:.01];
            NSDictionary *shown=snapshot(window);
            for(int index:{-1,20,INT_MIN,INT_MAX})[window moveIndicator:index x:3 y:4 majorRadius:.02];
            for(double bad:{std::numeric_limits<double>::quiet_NaN(),std::numeric_limits<double>::infinity(),double(INT_MAX)+1})[window moveIndicator:0 x:bad y:4 majorRadius:.02];
            [window moveIndicator:0 x:3 y:4 majorRadius:-.01];assert(!linkFor(window)&&[snapshot(window) isEqual:shown]);
            [window moveIndicator:0 x:5 y:6 majorRadius:.02];
            __weak CurrentIndicatorWindow *reentrant=window;
            onFrame=^{[reentrant moveIndicator:0 x:7 y:8 majorRadius:.03];};
            [linkFor(window) fire];assert(!linkFor(window).paused);[linkFor(window) fire];assert(linkFor(window).paused);
            [window moveIndicator:0 x:9 y:10 majorRadius:.02];
            __block NSDictionary *replacement;
            onFrame=^{[reentrant hideIndicator:0];[reentrant showIndicator:0 withX:22 andY:23 majorRadius:.04];replacement=snapshot(reentrant);};
            [linkFor(window) fire];assert([snapshot(window) isEqual:replacement]&&linkFor(window).paused);
            // No explicit hide: weak display target must not retain the window.
        }
        assert(!weak&&views==0&&scheduledLinks==0);
    }
}
int main(){@autoreleasepool{
    puts("Indicator presentation Foundation: complete actual/frozen window classes, controlled UIKit/display scheduler and real ARC/weak/pools");
    parityCases();cadenceCases();failureCases();lifecycleCases();reset();
    puts("Indicator presentation Foundation passed: 128 frozen 20-finger graphs, 1000-to-one move layout, integer label reuse, DOWN/UP/stop/stale ticks, scheduler refusal/unwind, render retry/reentry and 128 weak-owner lifecycles. UIKit/HID/display cadence/device qualification pending.");
}return 0;}
