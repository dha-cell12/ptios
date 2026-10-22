#include "ColorPicker.h"
#include "Screen.h"
#include "../shared/TLinkColorPolicy.h"
#include <memory>
#include <exception>

static void zx_colorError(NSError **error,const char *code){
    if(error)*error=[NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999
        userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;%s\r\n",code]}];
}
struct ZXColorImage {
    CGImageRef value;
    explicit ZXColorImage(CGImageRef image):value(image){}
    ~ZXColorImage(){if(value)CGImageRelease(value);}
    ZXColorImage(const ZXColorImage &)=delete;ZXColorImage &operator=(const ZXColorImage &)=delete;
};
struct ZXColorSpace {CGColorSpaceRef value=CGColorSpaceCreateDeviceRGB();~ZXColorSpace(){if(value)CGColorSpaceRelease(value);}};
struct ZXColorContext {CGContextRef value=nullptr;~ZXColorContext(){if(value)CGContextRelease(value);}};
struct ZXColorFree {void operator()(uint8_t *p)const{free(p);}};
struct ZXColorBuffer {
    // Release bytes before their reservation, including error/exception paths.
    std::shared_ptr<TLinkImageCharge> charge;
    std::unique_ptr<uint8_t,ZXColorFree> bytes;
    int width=0,height=0;
};
static bool zx_colorDimensions(CGImageRef image,int &width,int &height,NSError **error){
    size_t pixels=0;
    if(!image){zx_colorError(error,"color_capture_failed");return false;}
    if(!TLinkImagePixels(CGImageGetWidth(image),CGImageGetHeight(image),8388608,&pixels)){zx_colorError(error,"color_source_pixel_limit");return false;}
    width=int(CGImageGetWidth(image));height=int(CGImageGetHeight(image));return true;
}
static bool zx_colorRender(CGImageRef image,const TLinkColorRect &region,TLinkColorRequest &request,ZXColorBuffer &out,NSError **error){
    size_t pixels=0;int sw=0,sh=0;
    if(!zx_colorDimensions(image,sw,sh,error))return false;
    if(region.x<0||region.y<0||region.x>=sw||region.y>=sh||region.width>sw-region.x||region.height>sh-region.y||
        !TLinkImagePixels(region.width>0?size_t(region.width):0,region.height>0?size_t(region.height):0,4194304,&pixels)){
        zx_colorError(error,"color_roi_invalid_or_too_large");return false;
    }
    if(request.stopped()){zx_colorError(error,request.error());return false;}
    out.charge=TLinkColorMemory().reserve(TLinkImageKind::Frame,pixels*4);
    if(!out.charge){zx_colorError(error,"color_memory_budget");return false;}
    out.bytes.reset(static_cast<uint8_t *>(calloc(pixels,4)));
    if(!out.bytes){zx_colorError(error,"color_allocation_failed");return false;}
    ZXColorImage crop(CGImageCreateWithImageInRect(image,CGRectMake(region.x,region.y,region.width,region.height)));
    if(!crop.value){zx_colorError(error,"color_crop_failed");return false;}
    if(CGImageGetWidth(crop.value)!=size_t(region.width)||CGImageGetHeight(crop.value)!=size_t(region.height)){zx_colorError(error,"color_crop_geometry_changed");return false;}
    ZXColorSpace color;
    if(!color.value){zx_colorError(error,"color_space_failed");return false;}
    ZXColorContext context;
    context.value=CGBitmapContextCreate(out.bytes.get(),region.width,region.height,8,size_t(region.width)*4,color.value,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    if(!context.value){zx_colorError(error,"color_context_failed");return false;}
    CGContextDrawImage(context.value,CGRectMake(0,0,region.width,region.height),crop.value);
    if(request.stopped()){zx_colorError(error,request.error());return false;}
    out.width=region.width;out.height=region.height;return true;
}
static NSArray<NSString *> *zx_colorPayload(UInt8 *data,NSError **error){
    if(!data){zx_colorError(error,"color_payload_invalid");return nil;}
    size_t length=strnlen(reinterpret_cast<const char *>(data),262145);
    if(length>262144){zx_colorError(error,"color_payload_limit");return nil;}
    NSString *text=[[NSString alloc] initWithBytes:data length:length encoding:NSUTF8StringEncoding];
    if(!text){zx_colorError(error,"color_payload_invalid");return nil;}
    return [text componentsSeparatedByString:@";;"];
}
static bool zx_colorInt(NSArray<NSString *> *parts,NSUInteger index,int &out){return index<parts.count&&TLinkColorInt(parts[index].UTF8String,out);}
static bool zx_colorTable(NSString *table,std::vector<TLinkColorPoint> &points,NSError **error){
    if(!table.length||[table lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>131072){zx_colorError(error,"color_point_table_limit");return false;}
    NSArray<NSString *> *items=[table componentsSeparatedByString:@"|"];
    if(items.count>512){zx_colorError(error,"color_point_table_limit");return false;}
    for(NSString *item in items){
        if(!item.length)continue;
        NSArray<NSString *> *parts=[item componentsSeparatedByString:@",,"];TLinkColorPoint point;
        if(parts.count!=5||!zx_colorInt(parts,0,point.dx)||!zx_colorInt(parts,1,point.dy)||!zx_colorInt(parts,2,point.r)||!zx_colorInt(parts,3,point.g)||!zx_colorInt(parts,4,point.b)||
            !TLinkColorRGB(point.r)||!TLinkColorRGB(point.g)||!TLinkColorRGB(point.b)){zx_colorError(error,"color_point_table_invalid");return false;}
        points.push_back(point);
    }
    if(points.empty()){zx_colorError(error,"color_point_table_empty");return false;}return true;
}
template<class Operation> static id zx_colorRun(Operation operation,NSError **error){
    try {
        TLinkColorRequest request(TLinkCurrentNativeBudget());
        if(!request.admitted()){zx_colorError(error,"color_compute_busy");return nil;}
        if(request.stopped()){zx_colorError(error,request.error());return nil;}
        @try {
            id result=operation(request);
            if(request.stopped()){zx_colorError(error,request.error());return nil;}
            return result;
        } @catch(NSException *exception){(void)exception;zx_colorError(error,"color_operation_failed");return nil;}
    } catch(const std::exception &exception){(void)exception;zx_colorError(error,"color_operation_failed");return nil;}
}
static NSDictionary *zx_colorPick(CGImageRef image,int x,int y,TLinkColorRequest &request,NSError **error){
    TLinkColorRect crop;crop.x=x;crop.y=y;crop.width=crop.height=1;ZXColorBuffer buffer;
    if(!zx_colorRender(image,crop,request,buffer,error))return nil;
    const uint8_t *p=buffer.bytes.get();return @{@"red":@(p[0]),@"green":@(p[1]),@"blue":@(p[2])};
}
static NSString *zx_colorRange(CGImageRef image,const TLinkColorRect &region,const TLinkColorPoint &low,const TLinkColorPoint &high,int skip,TLinkColorRequest &request,NSError **error){
    ZXColorBuffer buffer;if(!zx_colorRender(image,region,request,buffer,error))return nil;
    TLinkColorResult result;auto scan=TLinkColorRangeScan(buffer.bytes.get(),buffer.width,buffer.height,skip,low,high,request,result);
    if(scan==TLinkColorScan::Stopped){zx_colorError(error,request.error());return nil;}
    if(scan==TLinkColorScan::NoMatch)return @"-1;;-1;;-1;;-1;;-1";
    return [NSString stringWithFormat:@"%d;;%d;;%d;;%d;;%d",region.x+result.x,region.y+result.y,result.r,result.g,result.b];
}
static CGImageRef zx_colorCapture(TLinkColorRequest &request,NSError **error){
    if(request.stopped()){zx_colorError(error,request.error());return NULL;}
    return [Screen createScreenShotCGImageRef];
}
NSDictionary* getRGBFromRawData(UInt8 *eventData,NSError **error){
    return zx_colorRun([&](TLinkColorRequest &request)->id{
        NSArray<NSString *> *parts=zx_colorPayload(eventData,error);if(!parts)return nil;int x=0,y=0;
        if(!zx_colorInt(parts,0,x)||!zx_colorInt(parts,1,y)||x<0||y<0||x>=8192||y>=8192){zx_colorError(error,"color_parameters_invalid");return nil;}
        ZXColorImage screen(zx_colorCapture(request,error));return zx_colorPick(screen.value,x,y,request,error);
    },error);
}
NSString* searchRGBFromRawData(UInt8 *eventData,NSError **error){
    return zx_colorRun([&](TLinkColorRequest &request)->id{
        NSArray<NSString *> *parts=zx_colorPayload(eventData,error);if(!parts)return nil;
        int action=0;if(!zx_colorInt(parts,0,action)||action<1||action>3){zx_colorError(error,"color_parameters_invalid");return nil;}
        if(action==1){
            int values[11];for(NSUInteger i=0;i<11;++i)if(!zx_colorInt(parts,i+1,values[i])){zx_colorError(error,"color_parameters_invalid");return nil;}
            int x=values[0],y=values[1],width=values[2],height=values[3],skip=values[10];
            if(x<0||y<0||x>=8192||y>=8192||skip<0||!TLinkColorRGB(values[4])||!TLinkColorRGB(values[5])||values[4]>values[5]||
                !TLinkColorRGB(values[6])||!TLinkColorRGB(values[7])||values[6]>values[7]||!TLinkColorRGB(values[8])||!TLinkColorRGB(values[9])||values[8]>values[9]){zx_colorError(error,"color_parameters_invalid");return nil;}
            ZXColorImage screen(zx_colorCapture(request,error));int sw=0,sh=0;
            if(!zx_colorDimensions(screen.value,sw,sh,error))return nil;
            TLinkColorRect region;if(!TLinkColorRegion(sw,sh,x,y,width,height,false,region)){zx_colorError(error,"color_region_invalid");return nil;}
            TLinkColorPoint low={0,0,values[4],values[6],values[8]},high={0,0,values[5],values[7],values[9]};
            return zx_colorRange(screen.value,region,low,high,skip,request,error);
        }
        int x=0,y=0,width=0,height=0,mode=0,skip=0;double value=0;
        if(parts.count<(action==2?4:9)){zx_colorError(error,"color_parameters_invalid");return nil;}
        if(action==3&&(!zx_colorInt(parts,1,x)||!zx_colorInt(parts,2,y)||!zx_colorInt(parts,3,width)||!zx_colorInt(parts,4,height)||!zx_colorInt(parts,8,skip))){zx_colorError(error,"color_parameters_invalid");return nil;}
        if(!zx_colorInt(parts,action==2?2:6,mode)||!TLinkColorDouble(parts[action==2?3:7].UTF8String,value)||skip<0||!TLinkColorMode(mode,value)){zx_colorError(error,"color_parameters_invalid");return nil;}
        std::vector<TLinkColorPoint> points;if(!zx_colorTable(parts[action==2?1:5],points,error))return nil;
        if(action==2)for(const auto &p:points)if(p.dx<0||p.dy<0||p.dx>=8192||p.dy>=8192){zx_colorError(error,"color_point_out_of_bounds");return nil;}
        ZXColorImage screen(zx_colorCapture(request,error));int sw=0,sh=0;if(!zx_colorDimensions(screen.value,sw,sh,error))return nil;
        TLinkColorRect crop,anchors;
        if(action==2){
            int minX=sw,minY=sh,maxX=0,maxY=0;
            for(const auto &p:points){if(p.dx<0||p.dy<0||p.dx>=sw||p.dy>=sh){zx_colorError(error,"color_point_out_of_bounds");return nil;}minX=std::min(minX,p.dx);minY=std::min(minY,p.dy);maxX=std::max(maxX,p.dx);maxY=std::max(maxY,p.dy);}
            crop.x=minX;crop.y=minY;crop.width=maxX-minX+1;crop.height=maxY-minY+1;
        }else{
            TLinkColorRect region;if(!TLinkColorRegion(sw,sh,x,y,width,height,true,region)){zx_colorError(error,"color_region_invalid");return nil;}
            if(!TLinkColorAnchors(sw,sh,region,points,anchors,crop))return @"-1;;-1";
        }
        ZXColorBuffer buffer;if(!zx_colorRender(screen.value,crop,request,buffer,error))return nil;
        if(action==2){
            for(const auto &p:points){if(!request.consume()){zx_colorError(error,request.error());return nil;}
                const uint8_t *pixel=buffer.bytes.get()+(size_t(p.dy-crop.y)*buffer.width+size_t(p.dx-crop.x))*4;
                if(!TLinkColorMatch(pixel[0],pixel[1],pixel[2],p,mode,value))return @"0";
            }return @"1";
        }
        TLinkColorResult result;auto scan=TLinkColorMultiScan(buffer.bytes.get(),buffer.width,crop,anchors,points,mode,value,skip,request,result);
        if(scan==TLinkColorScan::Stopped){zx_colorError(error,request.error());return nil;}
        if(scan==TLinkColorScan::NoMatch)return @"-1;;-1";
        return [NSString stringWithFormat:@"%d;;%d",result.x,result.y];
    },error);
}
@implementation ColorPicker
+ (NSDictionary *)colorAtPositionFromCGImage:(CGImageRef)image x:(int)x andY:(int)y {
    NSDictionary *result=zx_colorRun([&](TLinkColorRequest &request)->id{return zx_colorPick(image,x,y,request,NULL);},NULL);
    return result?:@{@"red":@(-1),@"green":@(-1),@"blue":@(-1)};
}
+ (NSString*)searchRGBFromCGImageRef:(CGImageRef)image region:(CGRect)rect redMin:(int)r0 redMax:(int)r1 greenMin:(int)g0 greenMax:(int)g1 blueMin:(int)b0 blueMax:(int)b1 skip:(int)skip {
    NSString *result=zx_colorRun([&](TLinkColorRequest &request)->id{
        if(!std::isfinite(rect.origin.x)||!std::isfinite(rect.origin.y)||!std::isfinite(rect.size.width)||!std::isfinite(rect.size.height)||
            rect.origin.x<0||rect.origin.y<0||rect.origin.x>8192||rect.origin.y>8192||rect.size.width<0||rect.size.height<0||rect.size.width>8192||rect.size.height>8192||
            rect.origin.x!=std::floor(rect.origin.x)||rect.origin.y!=std::floor(rect.origin.y)||rect.size.width!=std::floor(rect.size.width)||rect.size.height!=std::floor(rect.size.height)||
            skip<0||!TLinkColorRGB(r0)||!TLinkColorRGB(r1)||r0>r1||!TLinkColorRGB(g0)||!TLinkColorRGB(g1)||g0>g1||!TLinkColorRGB(b0)||!TLinkColorRGB(b1)||b0>b1)return nil;
        int sw=0,sh=0;if(!zx_colorDimensions(image,sw,sh,NULL))return nil;TLinkColorRect region;
        if(!TLinkColorRegion(sw,sh,int(rect.origin.x),int(rect.origin.y),int(rect.size.width),int(rect.size.height),false,region))return nil;
        TLinkColorPoint low={0,0,r0,g0,b0},high={0,0,r1,g1,b1};return zx_colorRange(image,region,low,high,skip,request,NULL);
    },NULL);
    return result?:@"-1;;-1;;-1;;-1;;-1";
}
@end
