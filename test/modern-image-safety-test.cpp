#include "../shared/TLinkModernImagePolicy.h"
#include "../shared/TLinkNativeFramePick.h"
#include "../shared/TLinkNativeFrameImage.h"
#include "../shared/TLinkNativeFrameSearch.h"
#include "../shared/TLinkNativeFrameColors.h"
#include "../shared/TLinkNativeFrameMulti.h"
#include <cassert>
#include <cstdio>
#include <functional>
using BOOL=bool;
#include "modern-image-fixture.h"
#include "ModernSadUnderTest.inc"
#include "ModernScaleUnderTest.inc"
#include "fixtures/image-matcher-legacy-v1.inc"
static void frameManyPolicyCases(){
    for(unsigned trial=0;trial<10000;++trial){
        TLinkNativeFramePickManyRequest request;std::string table;
        const unsigned count=trial%530+1;
        for(unsigned i=0;i<count;++i){
            const double x=(trial%17==0)?1e308:double(int(i)-16)*47.125;
            const double y=(i%7==0)?-0.0:double(i)*0.5;
            char row[780];std::snprintf(row,sizeof(row),"%.0f,%.0f",x,y);
            if(i)table+='|';table+=row;request.append(x,y);
            if(i<512){char scalar[384];std::snprintf(scalar,sizeof(scalar),"%.0f",x);assert(request.points[i].x==std::strtod(scalar,nullptr));}
        }
        assert(request.points.size()==std::min(size_t(count),size_t(512))&&request.pointCount==std::min(size_t(count),size_t(513)));
        assert(request.tableUnits==std::min(table.size(),size_t(32769)));
        char prefix[100],suffix[100];std::snprintf(prefix,sizeof(prefix),"69%d;;pick_many;;",INT_MAX);
        std::snprintf(suffix,sizeof(suffix),";;pixel;;%d",INT_MIN);
        const size_t wireBytes=std::strlen(prefix)+table.size()+std::strlen(suffix);
        assert(TLinkFramePickManyInputFits(INT_MAX,INT_MIN,request.tableUnits,5)==(wireBytes<=8192));
    }
    for(int id:{1,INT_MAX})for(int age:{INT_MIN,-1,0,1000,5000,INT_MAX}){
        char wire[100];std::snprintf(wire,sizeof(wire),"69%d;;pick_many;;0,0;;",id);
        char suffix[100];std::snprintf(suffix,sizeof(suffix),";;%d",age);
        size_t maxCoord=8192-std::strlen(wire)-std::strlen(suffix);
        assert(TLinkFramePickManyInputFits(id,age,3,maxCoord)&&!TLinkFramePickManyInputFits(id,age,3,maxCoord+1));
    }
    assert(!TLinkFramePickManyInputFits(1,1000,SIZE_MAX,0)&&!TLinkFramePickManyInputFits(1,1000,3,SIZE_MAX));
    TLinkNativeFramePickManyRequest large;for(unsigned i=0;i<100000;++i)large.append(1e308,-1e308);
    assert(large.points.size()==512&&large.pointCount==513&&large.tableUnits==32769);
    puts("Frame pick-many policy passed: 10k frozen wire-length plans, 512/513 storage/count, 100k-point saturation and exact 8192/8193 caps.");
}
#include "fixtures/frame-search-legacy-v1.inc"
static void frameSearchPolicyCases(){
    std::vector<uint8_t> bgra(40*8,0xee);for(int y=0;y<8;++y)for(int x=0;x<8;++x){size_t at=size_t(y)*40+size_t(x)*4;bgra[at]=uint8_t(x);bgra[at+1]=uint8_t(y);bgra[at+2]=uint8_t(x+y);}
    for(unsigned i=0;i<10000;++i){
        TLinkNativeFrameSearchRequest r;r.frame.frameId=1;r.frame.pointCoord=bool(i%2);
        double source[4]={double(int(i%31)-10)*0.5,double(int(i%19)-4)*0.5,double(int(i%17)-3)*0.5,double(int(i%13)-2)*0.5};
        if(i%113==0)source[0]=double(INT_MAX)-1;
        r.setRegion(source[0],source[1],source[2],source[3]);
        r.skip=int(i%5);if(i%97==0)r.skip=1023;
        if(i%3){r.redMin=r.redMax=int(i%15);r.greenMin=0;r.greenMax=7;r.blueMin=0;r.blueMax=7;}
        assert(TLinkFrameSearchParameters(r));const double scale=std::vector<double>{0.5,1,2,3.25,16}[i%5];
        TLinkNativeFrameSearchValue legacy,actual;const bool valid=legacyFrameSearch(bgra.data(),8,8,40,scale,r,legacy);
        {TLinkColorRequest work({});const auto status=TLinkFrameSearchScan(bgra.data(),8,8,40,scale,r,work,actual);
         assert((status==TLinkFrameSearchStatus::Done)==valid);
         if(valid)assert(actual.x==legacy.x&&actual.y==legacy.y&&actual.red==legacy.red&&actual.green==legacy.green&&actual.blue==legacy.blue);}
        char wire[1800];std::snprintf(wire,sizeof(wire),"69%d;;search_single;;%.0f;;%.0f;;%.0f;;%.0f;;%d;;%d;;%d;;%d;;%d;;%d;;%d;;;;%d",r.frame.frameId,source[0],source[1],source[2],source[3],r.redMin,r.redMax,r.greenMin,r.greenMax,r.blueMin,r.blueMax,r.skip,r.frame.maxAgeMs);
        size_t maxCoord=8192-std::strlen(wire);
        assert(TLinkFrameSearchInputFits(r,maxCoord)&&!TLinkFrameSearchInputFits(r,maxCoord+1));
    }
    TLinkNativeFrameSearchRequest r;r.frame.frameId=INT_MAX;r.frame.maxAgeMs=INT_MIN;r.setRegion(-1e308,1e308,-0.0,0.5);
    r.redMin=INT_MIN;r.redMax=INT_MAX;r.skip=INT_MAX;
    char wire[1800];std::snprintf(wire,sizeof(wire),"69%d;;search_single;;%.0f;;%.0f;;%.0f;;%.0f;;%d;;%d;;0;;255;;0;;255;;%d;;;;%d",INT_MAX,-1e308,1e308,-0.0,0.5,INT_MIN,INT_MAX,INT_MAX,INT_MIN);
    assert(!TLinkFrameSearchParameters(r));size_t maxCoord=8192-std::strlen(wire);
    assert(TLinkFrameSearchInputFits(r,maxCoord)&&!TLinkFrameSearchInputFits(r,maxCoord+1));
    r=TLinkNativeFrameSearchRequest{};r.frame.frameId=1;assert(TLinkFrameSearchParameters(r));
    for(int invalid:{-1,1024,INT_MAX}){r.skip=invalid;assert(!TLinkFrameSearchParameters(r));}r.skip=0;
    r.redMin=-1;assert(!TLinkFrameSearchParameters(r));r.redMin=0;r.redMax=256;assert(!TLinkFrameSearchParameters(r));r.redMax=255;
    r.greenMin=20;r.greenMax=19;assert(!TLinkFrameSearchParameters(r));r.greenMin=0;r.greenMax=255;
    r.width=double(INT_MAX);assert(!TLinkFrameSearchParameters(r));r.width=0;r.height=NAN;assert(!TLinkFrameSearchParameters(r));r.height=0;
    assert(!TLinkFrameSearchInputFits(r,SIZE_MAX));r.regionUnits=SIZE_MAX;assert(!TLinkFrameSearchInputFits(r,0));r.regionUnits=4;
    r.redMin=r.redMax=255;TLinkNativeFrameSearchValue found;
    {TLinkColorRequest work({},TLinkNativeNowNs(),17);assert(TLinkFrameSearchScan(bgra.data(),8,8,40,1,r,work,found)==TLinkFrameSearchStatus::Stopped);assert(std::string(work.error())=="color_work_limit");}
    auto token=std::make_shared<TLinkNativeCancellation>();token->cancel();auto parent=std::make_shared<TLinkNativeBudget>(token,0,4096);
    {TLinkColorRequest work(parent);assert(TLinkFrameSearchScan(bgra.data(),8,8,40,1,r,work,found)==TLinkFrameSearchStatus::Stopped);}
    auto expired=std::make_shared<TLinkNativeBudget>(nullptr,TLinkNativeNowNs()-1,4096);
    {TLinkColorRequest work(expired);assert(TLinkFrameSearchScan(bgra.data(),8,8,40,1,r,work,found)==TLinkFrameSearchStatus::Stopped);}
    puts("Frame search policy passed: 10k frozen BGRA scan/ROI/skip/scale cases, exact 8192/8193 wire accounting, parameter extremes and work/cancel/deadline bounds.");
}
#include "fixtures/frame-colors-legacy-v1.inc"
static void frameColorsPolicyCases(){
    std::vector<uint8_t> bgra(40*8,0xee);for(int y=0;y<8;++y)for(int x=0;x<8;++x){size_t at=size_t(y)*40+size_t(x)*4;bgra[at]=uint8_t(x);bgra[at+1]=uint8_t(y);bgra[at+2]=uint8_t(x+y);}
    for(unsigned i=0;i<10000;++i){
        TLinkNativeFrameColorsRequest r;r.frame.frameId=1;r.frame.pointCoord=bool(i%2);r.mode=int(i%2);
        char threshold[384];std::snprintf(threshold,sizeof(threshold),"%.4f",r.mode?double(i%256):double(i%10001)/10000.0);
        r.toleranceUnits=std::strlen(threshold);r.toleranceValid=TLinkColorDouble(threshold,r.tolerance);
        std::string table;
        for(unsigned j=0;j<i%8+1;++j){
            double x=double(int((i+j)%19)-3)*0.5,y=double((i+j)%9)*0.5;
            if(i%113==0)x=double(INT_MIN);if(i%127==0)x=double(INT_MAX);
            const int red=int((i+j)%16),green=int((i+j)%8),blue=int(j%8);
            r.append(x,y,red,green,blue);char row[800];std::snprintf(row,sizeof(row),"%.0f,,%.0f,,%d,,%d,,%d",x,y,red,green,blue);
            if(j)table+='|';table+=row;
        }
        assert(!TLinkFrameColorsTableError(r)&&r.tableUnits==table.size()&&TLinkFrameColorsParameters(r));
        const double scale=std::vector<double>{0.5,1,2,3.25,16}[i%5];bool matched=false;
        {TLinkColorRequest work({});assert(TLinkFrameColorsEvaluate(bgra.data(),8,8,40,scale,r.points,r.frame.pointCoord,r.mode,r.tolerance,work,matched));}
        assert(matched==legacyFrameColors(bgra.data(),8,8,40,scale,r.points,r.frame.pointCoord,r.mode,r.tolerance));
        char suffix[80];std::snprintf(suffix,sizeof(suffix),";;%d;;%s;;;;%d",r.mode,threshold,r.frame.maxAgeMs);
        const size_t base=std::strlen("691;;is_colors;;")+table.size()+std::strlen(suffix),maxCoord=8192-base;
        assert(TLinkFrameColorsInputFits(r,maxCoord)&&!TLinkFrameColorsInputFits(r,maxCoord+1));
    }
    for(double x:{-1e308,double(INT_MIN)-0.5,double(INT_MIN),-1.5,-0.5,-0.0,0.5,1.5,double(INT_MAX),double(INT_MAX)+0.5,1e308}){
        char text[384];std::snprintf(text,sizeof(text),"%.0f",x);int parsed=0;const bool expected=TLinkColorInt(text,parsed);
        TLinkNativeFrameColorsRequest r;r.append(x,0,1,2,3);assert(r.tableValid==expected);
        if(expected)assert(r.points[0].dx==parsed);else assert(std::string(TLinkFrameColorsTableError(r))=="invalid_point_table");
    }
    TLinkNativeFrameColorsRequest r;r.frame.frameId=1;for(unsigned i=0;i<512;++i)r.append(0,0,0,0,0);
    assert(r.points.size()==512&&!TLinkFrameColorsTableError(r)&&TLinkFrameColorsInputFits(r,5));r.append(0,0,0,0,0);
    assert(r.points.size()==512&&r.pointCount==513&&std::string(TLinkFrameColorsTableError(r))=="point_table_limit");
    r=TLinkNativeFrameColorsRequest{};r.frame.frameId=1;r.append(0,0,-1,0,0);assert(std::string(TLinkFrameColorsTableError(r))=="invalid_point_table");
    for(unsigned i=0;i<512;++i)r.append(1e308,-1e308,INT_MIN,INT_MAX,0);
    assert(r.tableUnits==32769&&!TLinkFrameColorsInputFits(r,0)&&std::string(TLinkFrameColorsTableError(r))=="point_table_limit_or_empty");
    r=TLinkNativeFrameColorsRequest{};r.frame.frameId=1;r.append(0,0,0,0,0);
    assert(!TLinkFrameColorsInputFits(r,SIZE_MAX));r.tableUnits=SIZE_MAX;assert(!TLinkFrameColorsInputFits(r,0));r.tableUnits=13;r.toleranceUnits=SIZE_MAX;assert(!TLinkFrameColorsInputFits(r,0));
    r.toleranceUnits=6;r.mode=2;assert(!TLinkFrameColorsParameters(r));r.mode=1;r.tolerance=255.0001;assert(!TLinkFrameColorsParameters(r));r.mode=0;r.tolerance=1.0001;assert(!TLinkFrameColorsParameters(r));r.tolerance=-0.0001;assert(!TLinkFrameColorsParameters(r));r.tolerance=-0.0;assert(TLinkFrameColorsParameters(r));r.toleranceValid=false;assert(!TLinkFrameColorsParameters(r));
    std::vector<TLinkColorPoint> points(2,TLinkColorPoint{0,0,0,0,0});bool matched=false;
    {TLinkColorRequest work({},TLinkNativeNowNs(),1);assert(!TLinkFrameColorsEvaluate(bgra.data(),8,8,40,1,points,false,1,0,work,matched)&&work.stopped());}
    auto token=std::make_shared<TLinkNativeCancellation>();token->cancel();auto parent=std::make_shared<TLinkNativeBudget>(token,0,4096);
    {TLinkColorRequest work(parent);TLinkFrameColorsEvaluate(bgra.data(),8,8,40,1,points,false,1,0,work,matched);assert(work.stopped());}
    puts("Frame colors policy passed: 10k frozen mode/scale/stride comparisons and exact wire limits, strict signed integers/RGB, 512/513 and saturated tables, mode/tolerance and work/cancel bounds.");
}
#include "fixtures/frame-multi-legacy-v1.inc"
static void frameMultiPolicyCases(){
    std::vector<uint8_t> bgra(40*8,0xee);for(int y=0;y<8;++y)for(int x=0;x<8;++x){const size_t i=size_t(y)*40+size_t(x)*4;bgra[i]=uint8_t(x);bgra[i+1]=uint8_t(y);bgra[i+2]=uint8_t(x+y);}
    for(unsigned i=0;i<10000;++i){
        TLinkNativeFrameMultiRequest r;r.colors.frame.frameId=1;r.colors.frame.pointCoord=i%2!=0;r.colors.frame.maxAgeMs=int(i%5001);r.colors.mode=int(i%2);r.skip=int(i%11);
        r.setRegion(double(int(i%19)-5)*0.5,double(int(i%13)-3)*0.5,double(int(i%17)-4)*0.5,double(int(i%9)-2)*0.5);
        if(i%113==0)r.setRegion(double(INT_MAX)-1,0,0,0);
        char threshold[80];std::snprintf(threshold,sizeof(threshold),"%.4f",r.colors.mode?double(i%6)+0.99995:double(i%5)*0.25);
        r.colors.toleranceUnits=std::strlen(threshold);r.colors.toleranceValid=TLinkColorDouble(threshold,r.colors.tolerance);
        std::string table;
        for(unsigned j=0;j<i%8+1;++j){
            double x=double(int((i+j)%7)-3)*0.5,y=double(int(j%5)-2)*0.5;
            if(i%97==0)x=double(INT_MIN);if(i%127==0)y=double(INT_MAX);
            const int red=int((i+j)%16),green=int((i+j)%8),blue=int(j%8);
            r.colors.append(x,y,red,green,blue);char row[800];std::snprintf(row,sizeof(row),"%.0f,,%.0f,,%d,,%d,,%d",x,y,red,green,blue);if(j)table+='|';table+=row;
        }
        assert(TLinkFrameMultiParameters(r)&&!TLinkFrameColorsTableError(r.colors));
        const double scale=std::vector<double>{0.5,1,2,3.25,16}[i%5];int oldX=-1,oldY=-1;
        const bool oldValid=legacyFrameMulti(bgra.data(),8,8,40,scale,r,oldX,oldY);
        TLinkColorRect region;auto points=r.colors.points;const bool valid=TLinkFrameMultiRegion(8,8,scale,r,region)&&TLinkFrameMultiOffsets(points,scale,r.colors.frame.pointCoord);
        assert(valid==oldValid);if(valid){TLinkNativeFrameMultiValue value;TLinkColorRequest work({});assert(TLinkFrameMultiScan(bgra.data(),8,8,40,region,points,r.colors.mode,r.colors.tolerance,r.skip,work,value));assert(value.x==oldX&&value.y==oldY);}
        char prefix[180],suffix[100];std::snprintf(prefix,sizeof(prefix),"69%d;;find_multi_point;;%.0f;;%.0f;;%.0f;;%.0f;;",r.colors.frame.frameId,r.x,r.y,r.width,r.height);
        std::snprintf(suffix,sizeof(suffix),";;%d;;%s;;%d;;;;%d",r.colors.mode,threshold,r.skip,r.colors.frame.maxAgeMs);
        const size_t base=std::strlen(prefix)+table.size()+std::strlen(suffix),maxCoord=8192-base;
        assert(TLinkFrameMultiInputFits(r,maxCoord)&&!TLinkFrameMultiInputFits(r,maxCoord+1));
    }
    TLinkNativeFrameMultiRequest r;r.colors.frame.frameId=1;r.colors.append(0,0,0,0,0);
    for(size_t huge:{SIZE_MAX,size_t(8193)}){assert(!TLinkFrameMultiInputFits(r,huge));r.regionUnits=huge;assert(!TLinkFrameMultiInputFits(r,0));r.regionUnits=4;r.colors.tableUnits=huge;assert(!TLinkFrameMultiInputFits(r,0));r.colors.tableUnits=12;r.colors.toleranceUnits=huge;assert(!TLinkFrameMultiInputFits(r,0));r.colors.toleranceUnits=6;}
    r.skip=-1;assert(!TLinkFrameMultiParameters(r));r.skip=1024;assert(!TLinkFrameMultiParameters(r));r.skip=1023;assert(TLinkFrameMultiParameters(r));r.skip=0;
    TLinkColorRect region;assert(TLinkFrameMultiRegion(8,8,2,r,region));std::vector<TLinkColorPoint> points{{0,0,255,0,0}};TLinkNativeFrameMultiValue out;
    {TLinkColorRequest work({},TLinkNativeNowNs(),1);assert(!TLinkFrameMultiScan(bgra.data(),8,8,40,region,points,1,0,0,work,out)&&work.stopped());}
    auto token=std::make_shared<TLinkNativeCancellation>();token->cancel();auto parent=std::make_shared<TLinkNativeBudget>(token,0,4096);
    {TLinkColorRequest work(parent);assert(!TLinkFrameMultiScan(bgra.data(),8,8,40,region,points,1,0,0,work,out)&&work.stopped());}
    {TLinkColorRequest work({},TLinkNativeNowNs()-3000000001ULL);assert(!TLinkFrameMultiScan(bgra.data(),8,8,40,region,points,1,0,0,work,out)&&work.stopped());}
    puts("Frame multi policy passed: 10k frozen ROI/offset/mode/scale/stride/skip scans and exact wire limits, coordinate overflow, saturated ingress and deterministic work/cancel/deadline bounds.");
}
static void frameImagePolicyCases(){
    for(unsigned n=0;n<10000;++n){
        TLinkNativeFrameImageRequest r;r.frameId=int(n%2?1:INT_MAX);r.imageId=2;r.maxAgeMs=int(n%5001);r.pixelSkip=int(n%1025);
        const double coordinates[]={n%73?double(int(n%19)-4)*.5:1e308,-0.0,double(int(n%15)-3)*.5,0};
        const double scalars[]={double(n%10001)/10000.0,n%2?1.0:.01004,n%3?1.0:16.00004,n%5?.25:.00004};
        std::string wire="68"+std::to_string(r.frameId)+";;2";int expected[4]={};bool valid=true;
        for(unsigned i=0;i<4;++i){char text[384];std::snprintf(text,sizeof(text),"%.0f",coordinates[i]);r.regionPart(i,text,std::strlen(text));wire+=";;";wire+=text;const bool parsed=TLinkColorInt(text,expected[i]);valid=valid&&parsed;}
        double decimal[4]={};for(unsigned i=0;i<4;++i){char text[384];std::snprintf(text,sizeof(text),"%.4f",scalars[i]);r.scalarPart(i,text,std::strlen(text));wire+=";;";wire+=text;assert(TLinkColorDouble(text,decimal[i]));}
        char suffix[100];std::snprintf(suffix,sizeof(suffix),";;%d;;;;%d",r.pixelSkip,r.maxAgeMs);wire+=suffix;
        const size_t limit=8192-wire.size();assert(TLinkNativeFrameImageInputFits(r,limit)&&!TLinkNativeFrameImageInputFits(r,limit+1));
        const bool policy=valid&&TLinkModernImageParameters(decimal[0],float(decimal[1]),float(decimal[2]),float(decimal[3]),r.pixelSkip)&&std::fabs(decimal[2]-decimal[1])/decimal[3]<=63;
        assert(r.coordinatesValid==valid&&TLinkNativeFrameImageParameters(r)==policy);
        if(valid)assert(r.x==expected[0]&&r.y==expected[1]&&r.width==expected[2]&&r.height==expected[3]);
    }
    TLinkNativeFrameImageRequest r;r.frameId=r.imageId=1;assert(TLinkNativeFrameImageParameters(r));r.scalarPart(0,"nan",3);assert(!TLinkNativeFrameImageParameters(r));
    r=TLinkNativeFrameImageRequest{};r.frameId=r.imageId=1;r.regionPart(0,"2147483648",10);assert(!TLinkNativeFrameImageParameters(r));
    r=TLinkNativeFrameImageRequest{};r.frameId=r.imageId=1;r.maxAgeMs=5001;assert(!TLinkNativeFrameImageParameters(r));r.maxAgeMs=0;r.validCoord=false;assert(!TLinkNativeFrameImageParameters(r));
    r.regionUnits=SIZE_MAX;assert(!TLinkNativeFrameImageInputFits(r,0));r.regionUnits=4;r.scalarUnits=SIZE_MAX;assert(!TLinkNativeFrameImageInputFits(r,0));r.scalarUnits=24;assert(!TLinkNativeFrameImageInputFits(r,SIZE_MAX));
    puts("Frame image policy passed: 10k frozen decimal/int/float/admission cases, exact ingress accounting, signed/overflow ROI, scalar traversal and saturated limits.");
}
int main(){
    frameImagePolicyCases();
    frameMultiPolicyCases();
    frameColorsPolicyCases();
    frameSearchPolicyCases();
    frameManyPolicyCases();
    for(double v:{-1e308,-2147483647.0,-1.5,-0.5,-0.0,0.5,1.5,2.5,2147483646.0,2147483647.0,1e308}){
        char legacy[384];std::snprintf(legacy,sizeof(legacy),"%.0f",v);size_t bytes=0;
        double rounded=TLinkNativeFrameJSCoordinate(v,&bytes);
        assert(rounded==std::strtod(legacy,nullptr)&&std::signbit(rounded)==std::signbit(std::strtod(legacy,nullptr))&&bytes==std::strlen(legacy));
    }
    for(unsigned i=0;i<100000;++i){
        const double v=double(i)*47.125-1234.5;char legacy[384];std::snprintf(legacy,sizeof(legacy),"%.0f",v);size_t bytes=0;
        assert(TLinkNativeFrameJSCoordinate(v,&bytes)==std::strtod(legacy,nullptr)&&bytes==std::strlen(legacy));
    }
    for(int frame:{1,INT_MAX})for(int age:{INT_MIN,-1,0,1000,5000,INT_MAX}){
        char prefix[100];std::snprintf(prefix,sizeof(prefix),"69%d;;pick;;-0;;2;;",frame);
        char suffix[100];std::snprintf(suffix,sizeof(suffix),";;%d",age);
        size_t maxCoord=8192-std::strlen(prefix)-std::strlen(suffix);
        assert(TLinkFramePickInputFits(frame,age,2,1,maxCoord)&&!TLinkFramePickInputFits(frame,age,2,1,maxCoord+1));
    }
    assert(!TLinkFramePickInputFits(1,1000,SIZE_MAX,1,5)&&!TLinkFramePickInputFits(1,1000,1,SIZE_MAX,5)&&!TLinkFramePickInputFits(1,1000,1,1,SIZE_MAX));
    TLinkNativeFramePickRequest pick;pick.frameId=1;pick.x=-10;assert(TLinkFramePickParameters(pick));
    pick.x=double(INT_MAX)-1;assert(TLinkFramePickParameters(pick));pick.x=INT_MAX;assert(!TLinkFramePickParameters(pick));
    pick.x=0;pick.maxAgeMs=5001;assert(!TLinkFramePickParameters(pick));pick.maxAgeMs=0;assert(TLinkFramePickParameters(pick));
    pick.validCoord=false;assert(!TLinkFramePickParameters(pick));
    puts("Frame pick numeric policy passed: 100k legacy scalar/byte cases, signed zero/range admission and exact/saturating input caps.");
    TLinkModernImagePlan plan;auto round=[](double v){return cvRound(v);};
    assert(TLinkModernImageMakePlan(80,60,10,10,.5f,2,.1f,round,plan)&&plan.scales.size()<=64);
    assert(!TLinkModernImageMakePlan(80,60,10,10,.5f,2,.00001f,round,plan));
    assert(!TLinkModernImageMakePlan(80,60,10,10,1,2,std::numeric_limits<float>::denorm_min(),round,plan));
    assert(!TLinkModernImageMakePlan(8192,1024,10,10,1,1,1,round,plan));
    assert(TLinkModernImageMakePlan(80,60,10,10,16,16,1,round,plan)&&plan.scales.empty());
    assert(!TLinkModernImageParameters(.8,1,1,0,0));
    assert(!TLinkModernImageParameters(.8,1,1,1,INT_MAX));
    assert(!TLinkModernImageParameters(std::numeric_limits<double>::quiet_NaN(),1,1,1,0));
    int coordinate=0;
    assert(TLinkFrameColorCoordinate(-3,2,true,coordinate)&&coordinate==-6);
    assert(!TLinkFrameColorCoordinate(std::numeric_limits<double>::infinity(),2,true,coordinate));
    assert(!TLinkFrameColorCoordinate(INT_MAX,2,true,coordinate));
    assert(TLinkFrameColorGeometry(4,4,20,80)&&!TLinkFrameColorGeometry(4,4,15,80)&&!TLinkFrameColorGeometry(4,4,20,79));
    TLinkColorRect region,anchors,crop;region.width=8;region.height=8;
    std::vector<TLinkColorPoint> offsets{{INT_MIN,0,0,0,0},{INT_MAX,0,0,0,0}};
    assert(!TLinkColorAnchors(8,8,region,offsets,anchors,crop));
    uint32_t random=19;
    // Actual modern loop vs frozen loop: both use the same controlled resizer.
    // This checks traversal/results, not OpenCV interpolation quality.
    for(unsigned n=0;n<3000;++n){
        Mat image(24,20),templ(4+int(n%5),4+int(n%3));
        for(auto &v:image.bytes){random=random*1664525U+1013904223U;v=uint8_t(random>>24);}
        for(auto &v:templ.bytes){random=random*1664525U+1013904223U;v=uint8_t(random>>24);}
        const float low=n%2?.5f:1.f,high=n%2?1.5f:1.f,step=.25f;
        int x=0,y=0,w=0,h=0,lx=0,ly=0,lw=0,lh=0;double score=0,legacyScore=0;
        const double acceptable=n%3?.99:0;
        bool current=zx_findTemplateSAD(image,templ,acceptable,low,high,step,int(n%3),&x,&y,&w,&h,&score);
        bool previous=legacyImageFind(image,templ,acceptable,low,high,step,int(n%3),&lx,&ly,&lw,&lh,&legacyScore);
        assert(current==previous&&x==lx&&y==ly&&w==lw&&h==lh&&score==legacyScore);
        assert(TLinkModernImageMemory().stats().total==0);
    }
    // Downsampled >600k source path and odd template rounding use the same oracle.
    for(int side:{800,801}){
        Mat large(side,800),pattern(7,5);int x=0,y=0,w=0,h=0,lx=0,ly=0,lw=0,lh=0;double score=0,oldScore=0;
        assert(zx_findTemplateSAD(large,pattern,1,.5f,1.5f,.25f,0,&x,&y,&w,&h,&score)==
               legacyImageFind(large,pattern,1,.5f,1.5f,.25f,0,&lx,&ly,&lw,&lh,&oldScore));
        assert(x==lx&&y==ly&&w==lw&&h==lh&&score==oldScore);
    }
    Mat image(24,20),templ(4,4);int x,y,w,h;double score;
    auto request=std::make_shared<TLinkModernImageRequest>(TLinkNativeBudgetPtr{});
    {TLinkModernImageScope scope(request);assert(request->consume(256000000));
        assert(!zx_findTemplateSAD(image,templ,.9,1,1,1,0,&x,&y,&w,&h,&score)&&request->stopped());}
    request.reset();assert(TLinkModernImageMemory().stats().total==0);
    auto full=TLinkModernImageMemory().reserve(TLinkImageKind::Frame,64*1024*1024);assert(full);
    request=std::make_shared<TLinkModernImageRequest>(TLinkNativeBudgetPtr{});
    {TLinkModernImageScope scope(request);assert(!zx_findTemplateSAD(image,templ,.9,1,1,1,0,&x,&y,&w,&h,&score));assert(std::string(request->error())=="image_scratch_budget");}
    full.reset();request.reset();
    auto cancel=std::make_shared<TLinkNativeCancellation>();auto parent=std::make_shared<TLinkNativeBudget>(cancel,0,4096);cancel->cancel();
    request=std::make_shared<TLinkModernImageRequest>(parent);unsigned before=cv::resizes;
    {TLinkModernImageScope scope(request);assert(!zx_findTemplateSAD(image,templ,.9,.5,2,.25,0,&x,&y,&w,&h,&score));}
    assert(cv::resizes==before&&TLinkModernImageMemory().stats().total==0);
    puts("Modern image passed: 3000 frozen scale/SAD cases, bounded plans/scratch/work, cancellation before resize, signed coordinates and padded BGRA bounds.");
}
