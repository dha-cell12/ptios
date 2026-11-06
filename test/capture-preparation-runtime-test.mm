#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <sys/utsname.h>
#include <cassert>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <memory>
#include <stdexcept>
#include <thread>
#include <vector>
#include <atomic>
#include "../shared/TLinkCapturePlan.h"
#include "../shared/TLinkCaptureOwnership.h"
#include "ax-node-pool-owner.h"
using std::isfinite;
using CaptureKey=TLinkCapturePlan::Key;
static std::atomic<unsigned> builds{0},regexes{0},unames{0};
static bool makeNil=false;static unsigned makeFault=0;
static NSDictionary *fixtureProperties(const CaptureKey &key);
static NSRange fixtureRegex(NSString *device);
#include "CapturePreparationUnderTest.inc"
static MeasuredCapturePreparation::Properties *reentryCache=nullptr;
static bool makeReentry=false;
static NSDictionary *fixtureProperties(const CaptureKey &key){
    ++builds;if(makeFault==1)[NSException raise:@"CapturePreparation" format:@"factory"];
    if(makeFault==2)throw std::runtime_error("factory");if(makeNil)return nil;
    if(makeReentry){makeReentry=false;assert(reentryCache);assert(reentryCache->get(CaptureKey(29,31,128,128*31,true,false)));}
    return MeasuredCapturePreparation::MakeProperties(key);
}
static NSRange fixtureRegex(NSString *device){++regexes;return [device rangeOfString:@"^iPad[8-9]|iPad[1-9][0-9]+" options:NSRegularExpressionSearch];}
static bool unameFailure=false,unterminated=false;
static NSData *machineBytes;
static int fixtureUname(struct utsname *out){
    ++unames;if(unameFailure)return -1;std::memset(out,0,sizeof(*out));
    if(unterminated){std::memset(out->machine,'x',sizeof(out->machine));return 0;}
    assert(machineBytes.length<sizeof(out->machine));if(machineBytes.length)std::memcpy(out->machine,machineBytes.bytes,machineBytes.length);return 0;
}
#include "CurrentDeviceUnderTest.inc"
#include "BeforeDeviceUnderTest.inc"
static CGFloat boundsWidth=390,boundsHeight=844,screenScale=3;
static unsigned screenReads=0,boundsReads=0,scaleReads=0,captureCalls=0,legacyBuilds=0;
static bool trackCaptureOwner=false,captureFails=false,globalFails=false,privateFails=false;
static NSDictionary *lastProperties;
static bool lastRotation=false;
static NSMutableArray *attempts;
static int imageToken;
extern "C" void TLinkAXFixtureOwnerDidDrain(void){}
@interface CaptureFixtureScreen:NSObject
+(instancetype)mainScreen;
@property(nonatomic,readonly) CGRect bounds;
@property(nonatomic,readonly) CGFloat scale;
@end
@implementation CaptureFixtureScreen
+(instancetype)mainScreen{++screenReads;static CaptureFixtureScreen *value;static dispatch_once_t once;dispatch_once(&once,^{value=[CaptureFixtureScreen new];});return value;}
-(CGRect)bounds{++boundsReads;return CGRectMake(0,0,boundsWidth,boundsHeight);}
-(CGFloat)scale{++scaleReads;return screenScale;}
@end
#include "RootGeometryUnderTest.inc"
static CGImageRef fixtureCapture(CFDictionaryRef raw,bool rotate){
    ++captureCalls;lastProperties=[(__bridge NSDictionary *)raw copy];lastRotation=rotate;
    if(trackCaptureOwner)TLinkAXFixtureAutoreleaseOwner();
    return captureFails?NULL:reinterpret_cast<CGImageRef>(&imageToken);
}
static std::unique_ptr<TLinkCapturePlan::BoolMemo> rootDeviceMemo;
static std::unique_ptr<MeasuredCapturePreparation::Properties> rootProperties,trollProperties;
#include "CurrentRootEntry.inc"
#include "BeforeRootEntry.inc"
struct FixtureSurface {__strong NSDictionary *properties;explicit FixtureSurface(NSDictionary *value):properties([value copy]){}};
static unsigned liveSurfaces=0,resolves=0;
static size_t alignmentOverride=0;
static size_t fixtureAlign(CFStringRef name,size_t minimum){assert(CFEqual(name,CFSTR("IOSurfaceBytesPerRow")));return alignmentOverride?alignmentOverride:((minimum+127)&~size_t(127));}
static size_t(*sSCIOSurfaceAlignProperty)(CFStringRef,size_t)=&fixtureAlign;
static void SCResolveSurfaceAcceleratorSymbols(){++resolves;}
static FixtureSurface *fixtureSurface(CFDictionaryRef raw){
    NSDictionary *properties=(__bridge NSDictionary *)raw;[attempts addObject:[properties copy]];
    if([properties[@"IOSurfaceIsGlobal"] boolValue]?globalFails:privateFails)return nullptr;
    ++liveSurfaces;return new FixtureSurface(properties);
}
#include "CurrentTrollSurface.inc"
#include "BeforeTrollSurface.inc"
static void drop(FixtureSurface *surface){if(surface){assert(liveSurfaces);--liveSurfaces;delete surface;}}
static void reset(NSString *device=@"iPhone15,2"){
    assert(liveSurfaces==0);builds=regexes=unames=0;makeNil=false;makeFault=0;makeReentry=false;reentryCache=nullptr;
    unameFailure=unterminated=false;machineBytes=[device dataUsingEncoding:NSUTF8StringEncoding];
    boundsWidth=390;boundsHeight=844;screenScale=3;screenReads=boundsReads=scaleReads=captureCalls=legacyBuilds=resolves=0;
    trackCaptureOwner=captureFails=globalFails=privateFails=false;alignmentOverride=0;sSCIOSurfaceAlignProperty=&fixtureAlign;
    lastProperties=nil;attempts=[NSMutableArray array];
    rootDeviceMemo.reset(new TLinkCapturePlan::BoolMemo);rootProperties.reset(new MeasuredCapturePreparation::Properties);trollProperties.reset(new MeasuredCapturePreparation::Properties);
}
static void cacheCases(){
    reset();MeasuredCapturePreparation::Properties cache;CaptureKey key(12,20,64,1280,true,false);
    NSDictionary *held=cache.get(key);assert(held&&![held isKindOfClass:[NSMutableDictionary class]]);
    for(unsigned n=0;n<10000;++n){assert(cache.get(key)==held);}
    assert(builds==1);
    CaptureKey privateKey=key;privateKey.global=false;NSDictionary *privateValue=cache.get(privateKey);
    assert(privateValue!=held&&![privateValue[@"IOSurfaceIsGlobal"] boolValue]&&[held[@"IOSurfaceIsGlobal"] boolValue]);
    NSDictionary *copy=[held copy];
    for(unsigned n=1;n<=8;++n){assert(cache.get(CaptureKey(12+n,20,128,2560,true,false)));}
    assert([held isEqual:copy]);unsigned previous=builds;assert(cache.get(key)&&builds==previous+1);
    CaptureKey invalid=key;invalid.row=0;previous=builds;assert(!cache.get(invalid)&&builds==previous);
    for(unsigned fault=0;fault<3;++fault){MeasuredCapturePreparation::Properties fresh;makeNil=fault==0;makeFault=fault;bool caught=false;
        @try{try{assert(!fresh.get(key));}catch(const std::runtime_error &){caught=fault==2;}}
        @catch(NSException *exception){caught=fault==1&&[exception.name isEqual:@"CapturePreparation"];}
        assert(fault==0||caught);makeNil=false;makeFault=0;assert(fresh.get(key));
    }
    MeasuredCapturePreparation::Properties reentrant;reentryCache=&reentrant;makeReentry=true;assert(reentrant.get(key)&&!makeReentry);
    MeasuredCapturePreparation::Properties concurrent;builds=0;std::vector<std::thread> threads;
    for(unsigned t=0;t<8;++t)threads.emplace_back([&]{for(unsigned n=0;n<1000;++n){@autoreleasepool{assert([concurrent.get(key) isEqual:held]);}}});
    for(auto &thread:threads){thread.join();}
    assert(builds>=1&&builds<=8);
    __weak NSDictionary *weak;NSDictionary *reader=nil;
    @autoreleasepool{auto owner=std::unique_ptr<MeasuredCapturePreparation::Properties>(new MeasuredCapturePreparation::Properties);reader=owner->get(key);weak=reader;owner.reset();assert([reader isEqual:held]);reader=nil;}
    assert(!weak);
}
static void deviceCases(){
    for(NSString *name in @[@"iPhone15,2",@"iPad7,4",@"iPad8,1",@"iPad9,1",@"iPad10,2",@"iPad100,1",@"prefixiPad12",@"iPad08",@"arm64",@"Ảnh"]){@autoreleasepool{
        reset(name);assert([CurrentGetDeviceName() isEqual:BeforeGetDeviceName()]);TLinkCapturePlan::BoolMemo memo;
        const bool expected=[name rangeOfString:@"^iPad[8-9]|iPad[1-9][0-9]+" options:NSRegularExpressionSearch].location!=NSNotFound;
        regexes=unames=0;
        for(unsigned n=0;n<10000;++n){assert(MeasuredCapturePreparation::RotateIPad(memo,[]{return CurrentGetDeviceName();})==expected);}
        assert(regexes==1&&unames==1);
    }}
    reset();TLinkCapturePlan::BoolMemo retry;unameFailure=true;assert(!MeasuredCapturePreparation::RotateIPad(retry,[]{return CurrentGetDeviceName();}));
    unameFailure=false;unterminated=true;assert(!CurrentGetDeviceName());assert(!MeasuredCapturePreparation::RotateIPad(retry,[]{return CurrentGetDeviceName();}));
    unterminated=false;machineBytes=[NSData data];assert(!CurrentGetDeviceName());assert(!MeasuredCapturePreparation::RotateIPad(retry,[]{return CurrentGetDeviceName();}));
    const uint8_t invalid[]={0xff,0xfe};machineBytes=[NSData dataWithBytes:invalid length:2];assert(!CurrentGetDeviceName());assert(!MeasuredCapturePreparation::RotateIPad(retry,[]{return CurrentGetDeviceName();}));
    machineBytes=[@"iPad8,1" dataUsingEncoding:NSUTF8StringEncoding];assert(MeasuredCapturePreparation::RotateIPad(retry,[]{return CurrentGetDeviceName();}));
}
static void entryCases(){
    for(NSString *device in @[@"iPhone15,2",@"iPad7,4",@"iPad8,1",@"iPad12,9"]){
        for(unsigned n=0;n<64;++n){NSDictionary *before=nil;bool oldRotate=false;
            for(bool current:{false,true}){@autoreleasepool{reset(device);boundsWidth=n%2?844:390;boundsHeight=n%2?390:844;screenScale=1+n%3;
                assert(current?CurrentRootCapture():BeforeRootCapture());if(current)assert([lastProperties isEqual:before]&&lastRotation==oldRotate);else{before=lastProperties;oldRotate=lastRotation;}
            }}
        }
    }
    for(bool current:{false,true}){reset();for(unsigned n=0;n<10000;++n){@autoreleasepool{assert(current?CurrentRootCapture():BeforeRootCapture());}}
        assert(unames==(current?1U:10000U)&&regexes==(current?1U:10000U)&&builds==(current?1U:0U)&&legacyBuilds==(current?0U:10000U)&&captureCalls==10000);
    }
    for(bool failed:{false,true})for(bool current:{false,true}){TLinkAXFixtureResetOwners();@autoreleasepool{reset();trackCaptureOwner=true;captureFails=failed;
        CGImageRef image=current?CurrentRootCapture():BeforeRootCapture();assert(bool(image)==!failed);assert(TLinkAXFixtureLiveOwners()==(current?0U:1U));
    }assert(TLinkAXFixtureLiveOwners()==0);}
    reset();CurrentRootCapture();boundsWidth=1024;boundsHeight=768;screenScale=2;CurrentRootCapture();assert(builds==2&&unames==1&&boundsReads==2&&scaleReads==2);
    for(unsigned n=0;n<128;++n){reset();boundsWidth=1.25+n*13;boundsHeight=2.75+n*7;screenScale=1+n%3;
        int a=0,b=0,c=0,d=0;assert(BeforeDisplaySize(&a,&b)&&CurrentDisplaySize(&c,&d)&&a==c&&b==d);
        assert(screenReads==3&&scaleReads==2&&boundsReads==2);
    }
    for(unsigned n=0;n<64;++n){NSArray *before=nil;
        for(bool current:{false,true}){@autoreleasepool{reset();globalFails=n%2;privateFails=n%5==0;alignmentOverride=n%3==0?8192:0;
            FixtureSurface *surface=current?CurrentCreateSurface(1170,2532):BeforeCreateSurface(1170,2532);
            if(current)assert([attempts isEqual:before]);else before=[attempts copy];drop(surface);
        }}
    }
    reset();globalFails=true;
    for(unsigned n=0;n<10000;++n){@autoreleasepool{drop(CurrentCreateSurface(1170,2532));[attempts removeAllObjects];}}
    assert(builds==2&&resolves==10000);
    reset();alignmentOverride=SIZE_MAX;assert(!CurrentCreateSurface(1,2)&&attempts.count==0);
    reset();int w=7,h=8;boundsWidth=NAN;assert(!CurrentDisplaySize(&w,&h)&&w==7&&h==8);assert(screenReads==1);
    reset();CurrentDisplaySize(&w,&h);assert(w==1170&&h==2532&&screenReads==1);
}
struct SimpleSurface {bool locked=false;};struct SimpleImage {};
static unsigned simpleSurfaces=0,simpleImages=0,simpleUnlocks=0;
struct ExceptionAPI {
    using Surface=SimpleSurface *;using Image=SimpleImage *;unsigned stage;
    bool lock(Surface value){value->locked=true;return true;}bool unlock(Surface value){assert(value->locked);value->locked=false;++simpleUnlocks;return true;}
    void dropSurface(Surface value){assert(!value->locked);delete value;--simpleSurfaces;}void dropImage(Image value){delete value;--simpleImages;}
    void render(Surface value){assert(value->locked);if(stage==1)[NSException raise:@"CaptureOwnership" format:@"render"];}
    Image createImage(Surface value){assert(value->locked);if(stage==2)[NSException raise:@"CaptureOwnership" format:@"image"];++simpleImages;return new SimpleImage;}
    bool validImage(Image value){return value!=nullptr;}bool rotates()const{return true;}
    Image rotate(Image value){assert(value);[NSException raise:@"CaptureOwnership" format:@"rotate"];return nullptr;}
};
static void exceptionCases(){
    for(unsigned stage:{1U,2U,3U}){ExceptionAPI api{stage};++simpleSurfaces;bool caught=false;unsigned before=simpleUnlocks;
        @try{TLinkCaptureOwnership::Fresh(new SimpleSurface,api);}@catch(NSException *exception){caught=[exception.name isEqual:@"CaptureOwnership"];}
        assert(caught&&!simpleSurfaces&&!simpleImages&&simpleUnlocks==before+1);
    }
}
int main(){@autoreleasepool{
    std::puts("Capture preparation Foundation: actual/frozen root/model/TrollStore factories with real dictionaries/regex/ARC, controlled screen/kernel/render providers");
    cacheCases();deviceCases();entryCases();exceptionCases();reset();
    std::puts("Capture preparation passed: live geometry/frozen values/global-first fallback, 10k root frames with one vs10k device/regex/dictionary preparations, two cached TrollStore variants, held readers/FIFO/concurrent/reentrant/fault recovery, bounded uname and NS ownership unwind. Actual IOSurface/pixel/device performance pending.");
}return 0;}
