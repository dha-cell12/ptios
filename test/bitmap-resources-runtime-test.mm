#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>
#include <vector>
#include <memory>
#include <unordered_set>
#include <stdexcept>
#include <cassert>
#include <cstdio>
#include <mutex>
#include "../shared/TLinkBitmapResourceCore.h"
#include "../shared/TLinkCaptureOwnership.h"
#include "../shared/TLinkCapturePlan.h"
static unsigned spaces=0,spaceDrops=0,sourceImages=0,contexts=0,locks=0,unlocks=0,allocations=0,frees=0;
static unsigned fault=0,faultKind=0,dataMode=0,seed=0;
static bool noSource=false,noSpace=false,noContext=false,noLock=false,noBytes=false;
static std::unique_ptr<TLinkBitmapCore::Memo<CGColorSpaceRef>> rgbMemo;
static std::weak_ptr<TLinkBitmapCore::Bytes> lastStorage;
static NSData *heldData;
static void fail(unsigned stage){if(fault!=stage)return;if(faultKind==1)[NSException raise:@"BitmapFixture" format:@"fault"];if(faultKind==2)throw std::runtime_error("bitmap");}
static CGColorSpaceRef fixtureRGB(){fail(1);if(noSpace)return NULL;++spaces;return CGColorSpaceCreateDeviceRGB();}
static void fixtureDropSpace(CGColorSpaceRef value){if(value){++spaceDrops;CGColorSpaceRelease(value);}}
static NSData *fixtureData(const std::shared_ptr<TLinkBitmapCore::Bytes> &owner);
#include "BitmapResourcesUnderTest.inc"
static NSData *fixtureData(const std::shared_ptr<TLinkBitmapCore::Bytes> &owner){
    if(dataMode==1)return nil;
    if(dataMode==2)[NSException raise:@"BitmapFixture" format:@"data"];
    if(dataMode==3)throw std::runtime_error("data");
    if(dataMode==4){NSData *copy=[NSData dataWithBytes:owner->data() length:owner->size()];owner->markDataRelease();return copy;}
    if(dataMode==5){heldData=MeasuredBitmapResources::CreateData(owner);return nil;}
    if(dataMode==6)return [NSData dataWithBytes:owner->data() length:owner->size()-1];
    return MeasuredBitmapResources::CreateData(owner);
}
static void *allocateBytes(size_t count,size_t size){if(noBytes)return nullptr;void *value=calloc(count,size);if(value)++allocations;return value;}
static void freeBytes(void *value){assert(value);++frees;free(value);}
static std::shared_ptr<TLinkBitmapCore::Bytes> fixtureStorage(size_t size){auto owner=TLinkBitmapCore::Bytes::Allocate(size,allocateBytes,freeBytes);lastStorage=owner;return owner;}
static void sourceRelease(void *info,const void *,size_t){delete static_cast<std::vector<uint8_t> *>(info);assert(sourceImages);--sourceImages;}
static CGImageRef fixtureScreen(){
    if(noSource)return NULL;
    const size_t width=8,height=8;auto *bytes=new std::vector<uint8_t>(width*height*4);
    for(size_t n=0;n<width*height;++n){(*bytes)[n*4]=uint8_t(seed+n*11);(*bytes)[n*4+1]=uint8_t(seed+n*7);(*bytes)[n*4+2]=uint8_t(seed+n*3);(*bytes)[n*4+3]=255;}
    ++sourceImages;CGDataProviderRef provider=CGDataProviderCreateWithData(bytes,bytes->data(),bytes->size(),sourceRelease);assert(provider);
    CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();CGImageRef image=CGImageCreate(width,height,8,32,width*4,color,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big,provider,NULL,false,kCGRenderingIntentDefault);
    CGColorSpaceRelease(color);CGDataProviderRelease(provider);assert(image);return image;
}
static std::unordered_set<CGContextRef> activeContexts;
static CGContextRef fixtureContext(void *bytes,size_t width,size_t height,size_t bits,size_t row,CGColorSpaceRef color,uint32_t info){
    fail(2);if(noContext||!color)return NULL;
    CGContextRef value=CGBitmapContextCreate(bytes,width,height,bits,row,color,info);if(value){assert(activeContexts.insert(value).second);++contexts;}return value;
}
static void fixtureDropContext(CGContextRef value){assert(value&&activeContexts.erase(value)==1&&contexts);--contexts;CGContextRelease(value);}
static void fixtureDraw(CGContextRef context,CGRect rect,CGImageRef image){fail(3);CGContextDrawImage(context,rect,image);}
static CGDataProviderRef fixtureProvider(CFDataRef data){fail(4);return CGDataProviderCreateWithCFData(data);}
static CGImageRef fixtureImage(size_t w,size_t h,size_t bits,size_t bpp,size_t row,CGColorSpaceRef color,CGBitmapInfo info,CGDataProviderRef provider,const CGFloat *decode,bool interpolate,CGColorRenderingIntent intent){
    fail(5);return CGImageCreate(w,h,bits,bpp,row,color,info,provider,decode,interpolate,intent);
}
@interface BitmapFixtureImage:NSObject{CGImageRef _image;}
+(instancetype)imageWithCGImage:(CGImageRef)image;
@end
@implementation BitmapFixtureImage
+(instancetype)imageWithCGImage:(CGImageRef)image{fail(6);BitmapFixtureImage *value=[BitmapFixtureImage new];value->_image=CGImageRetain(image);return value;}
-(void)dealloc{if(_image)CGImageRelease(_image);}
@end
enum {CaptureResultPass=0,CaptureResultBlack=1,CaptureResultFail=2};
@interface BitmapOutcome:NSObject
@property(nonatomic) NSInteger result;
@property(nonatomic,strong) BitmapFixtureImage *image;
@property(nonatomic,strong) NSData *rgbaData;
@property(nonatomic) int width;
@property(nonatomic) int height;
@property(nonatomic) int bytesPerRow;
@property(nonatomic,copy) NSString *diagnostics;
@end
@implementation BitmapOutcome
@end
#include "CurrentBitmapCapture.inc"
#include "BeforeBitmapCapture.inc"
static CVReturn fixtureLock(CVPixelBufferRef target,CVPixelBufferLockFlags flags){if(noLock)return kCVReturnError;CVReturn result=CVPixelBufferLockBaseAddress(target,flags);if(result==kCVReturnSuccess)++locks;return result;}
static CVReturn fixtureUnlock(CVPixelBufferRef target,CVPixelBufferLockFlags flags){assert(locks>unlocks);++unlocks;return CVPixelBufferUnlockBaseAddress(target,flags);}
#include "CurrentBitmapStream.inc"
#include "BeforeBitmapStream.inc"
static const size_t kMaxImagePixels=16*1024*1024;
static bool TLinkImagePixels(size_t width,size_t height,size_t maximum,size_t *pixels){if(!width||!height||width>maximum/height)return false;*pixels=width*height;return true;}
static const int CV_8UC4=4,COLOR_RGBA2GRAY=1;
namespace cv {
struct Mat {
    int rows=0,cols=0;std::vector<uint8_t> bytes;uint8_t *data=nullptr;size_t step[1]={0};
    Mat()=default;
    Mat(int h,int w,int channels):rows(h),cols(w),bytes(size_t(h)*w*channels),data(bytes.data()){step[0]=size_t(w)*channels;}
    Mat(const Mat &other):rows(other.rows),cols(other.cols),bytes(other.bytes),data(bytes.empty()?nullptr:bytes.data()){step[0]=other.step[0];}
    Mat &operator=(const Mat &other){rows=other.rows;cols=other.cols;bytes=other.bytes;data=bytes.empty()?nullptr:bytes.data();step[0]=other.step[0];return *this;}
};
static void cvtColor(const Mat &source,Mat &out,int mode){assert(mode==COLOR_RGBA2GRAY);out=Mat(source.rows,source.cols,1);for(size_t n=0;n<out.bytes.size();++n)out.bytes[n]=source.bytes[n*4];}
}
#include "CurrentBitmapGray.inc"
#include "BeforeBitmapGray.inc"
#include "CurrentBitmapRender.inc"
#include "BeforeBitmapRender.inc"
static void reset(){
    rgbMemo.reset();assert(spaces==spaceDrops&&sourceImages==0&&contexts==0&&locks==unlocks&&allocations==frees);
    spaces=spaceDrops=locks=unlocks=allocations=frees=0;fault=faultKind=dataMode=seed=0;noSource=noSpace=noContext=noLock=noBytes=false;heldData=nil;lastStorage.reset();
    rgbMemo.reset(new TLinkBitmapCore::Memo<CGColorSpaceRef>(&fixtureDropSpace));
}
static void goldenCases(){
    for(unsigned n=0;n<64;++n){NSData *before=nil;NSString *diagnostic=nil;NSInteger result=0;
        for(bool current:{false,true}){@autoreleasepool{
            reset();seed=n;BitmapOutcome *value=current?CurrentProductionCapture():BeforeProductionCapture();assert(value.rgbaData&&value.image&&contexts==0);
            if(current){assert([value.rgbaData isEqual:before]&&[value.diagnostics isEqual:diagnostic]&&value.result==result);}else{before=value.rgbaData;diagnostic=value.diagnostics;result=value.result;}
            assert(value.width==8&&value.height==8&&value.bytesPerRow==32);
        }assert(sourceImages==0);}
    }
    for(bool current:{false,true}){reset();for(unsigned n=0;n<1000;++n){@autoreleasepool{BitmapOutcome *value=current?CurrentProductionCapture():BeforeProductionCapture();assert(value.rgbaData);}}
        assert(spaces==(current?1U:1000U));
    }
    for(unsigned n=0;n<64;++n){@autoreleasepool{reset();seed=n;CGImageRef source=fixtureScreen();std::vector<uint8_t> old,newer;int a=0,b=0,c=0,x=0,y=0,z=0;
        assert(BeforeRender(source,old,&a,&b,&c)&&CurrentRender(source,newer,&x,&y,&z)&&old==newer&&a==x&&b==y&&c==z);
        NSError *oldError=nil,*newError=nil;cv::Mat grayOld=BeforeGray(source,&oldError),grayNew=CurrentGray(source,&newError);assert(grayOld.bytes==grayNew.bytes&&!oldError&&!newError);CGImageRelease(source);
    }assert(sourceImages==0);}
}
static void faultCases(){
    for(unsigned stage:{1U,2U,3U,4U,5U,6U})for(unsigned kind:{1U,2U}){
        @autoreleasepool{reset();fault=stage;faultKind=kind;bool caught=false;
            @try{try{CurrentProductionCapture();}catch(const std::runtime_error &){caught=kind==2;}}
            @catch(NSException *exception){caught=kind==1&&[exception.name isEqual:@"BitmapFixture"];}
            assert(caught&&contexts==0);
        }assert(sourceImages==0&&lastStorage.expired()&&allocations==frees);
    }
    for(unsigned mode:{1U,2U,3U,4U,5U,6U}){
        @autoreleasepool{reset();dataMode=mode;bool caught=false;BitmapOutcome *value=nil;
            @try{try{value=CurrentProductionCapture();}catch(const std::runtime_error &){caught=mode==3;}}
            @catch(NSException *exception){caught=mode==2&&[exception.name isEqual:@"BitmapFixture"];}
            if(mode==2||mode==3)assert(caught);else if(mode==4)assert(value.rgbaData&&value.result==CaptureResultPass);else assert(value.result==CaptureResultFail);
            if(mode==5){assert(!lastStorage.expired()&&heldData);heldData=nil;}
            assert(contexts==0);
        }assert(sourceImages==0&&lastStorage.expired()&&allocations==frees);
    }
    for(unsigned stage:{2U,3U})for(unsigned kind:{1U,2U}){
        @autoreleasepool{reset();CGImageRef source=fixtureScreen();fault=stage;faultKind=kind;bool caught=false;std::vector<uint8_t> out;
        @try{try{CurrentRender(source,out,NULL,NULL,NULL);}catch(const std::runtime_error &){caught=kind==2;}}
        @catch(NSException *exception){caught=kind==1&&[exception.name isEqual:@"BitmapFixture"];}
        assert(caught&&contexts==0);CGImageRelease(source);}
    }
    reset();noSpace=true;
    @autoreleasepool{BitmapOutcome *value=CurrentProductionCapture();assert(value.result==CaptureResultFail);}
    noSpace=false;
    @autoreleasepool{BitmapOutcome *value=CurrentProductionCapture();assert(value.rgbaData);}
    assert(spaces==1);
    reset();noBytes=true;
    @autoreleasepool{BitmapOutcome *value=CurrentProductionCapture();assert(value.result==CaptureResultFail);}
    assert(sourceImages==0);
}
static NSData *targetBytes(CVPixelBufferRef target){assert(CVPixelBufferLockBaseAddress(target,0)==kCVReturnSuccess);size_t row=CVPixelBufferGetBytesPerRow(target);uint8_t *bytes=(uint8_t *)CVPixelBufferGetBaseAddress(target);NSMutableData *out=[NSMutableData data];for(unsigned y=0;y<8;++y)[out appendBytes:bytes+y*row length:32];CVPixelBufferUnlockBaseAddress(target,0);return out;}
static void streamCases(){
    for(unsigned mode=0;mode<4;++mode){NSData *before=nil;
        for(bool current:{false,true}){@autoreleasepool{reset();CVPixelBufferRef target=NULL;assert(CVPixelBufferCreate(kCFAllocatorDefault,8,8,kCVPixelFormatType_32BGRA,NULL,&target)==kCVReturnSuccess);CGImageRef source=fixtureScreen();noLock=mode==1;noContext=mode==2;noSpace=mode==3;
            BOOL result=current?CurrentStreamCopy(source,target):BeforeStreamCopy(source,target);assert(result==(mode==0));
            if(result){NSData *bytes=targetBytes(target);if(current)assert([bytes isEqual:before]);else before=bytes;}
            assert(locks==unlocks&&contexts==0);CGImageRelease(source);CVPixelBufferRelease(target);
        }}
    }
    for(unsigned kind:{1U,2U}){@autoreleasepool{reset();CVPixelBufferRef target=NULL;assert(CVPixelBufferCreate(kCFAllocatorDefault,8,8,kCVPixelFormatType_32BGRA,NULL,&target)==kCVReturnSuccess);CGImageRef source=fixtureScreen();fault=3;faultKind=kind;bool caught=false;
        @try{try{CurrentStreamCopy(source,target);}catch(const std::runtime_error &){caught=kind==2;}}
        @catch(NSException *exception){caught=kind==1&&[exception.name isEqual:@"BitmapFixture"];}
        assert(caught&&contexts==0&&locks==unlocks);CGImageRelease(source);CVPixelBufferRelease(target);
    }}
}
static std::mutex sSCCaptureLock;
static unsigned pipelineUnlocks=0;
static void fixturePipelineUnlock(std::mutex *value){++pipelineUnlocks;value->unlock();}
static void pipelineGuardCases(){
    for(unsigned kind:{1U,2U})for(bool early:{false,true}){unsigned before=pipelineUnlocks;bool caught=false;fault=3;faultKind=kind;
        sSCCaptureLock.lock();
        @try{try{
#include "BitmapPipelineGuard.inc"
            if(early)captureOwner.reset(nullptr);
            fail(3);
        }catch(const std::runtime_error &){caught=kind==2;}}
        @catch(NSException *exception){caught=kind==1&&[exception.name isEqual:@"BitmapFixture"];}
        assert(caught&&pipelineUnlocks==before+1&&sSCCaptureLock.try_lock());sSCCaptureLock.unlock();
    }
}
int main(){@autoreleasepool{
    std::puts("Bitmap Foundation: complete actual/frozen renderers/materializer/stream copy, real CG/CV/data pixels and controlled capture/CV conversion/faults");
    goldenCases();faultCases();streamCases();pipelineGuardCases();reset();rgbMemo.reset();assert(spaces==spaceDrops);
    std::puts("Bitmap Foundation passed: frozen RGBA/gray/render/stream bytes, one vs1000 color factories, source/context/CV unwind, nil/copy/retained data failures and balanced byte leases. Private capture/real OpenCV/device qualification pending.");
}return 0;}
