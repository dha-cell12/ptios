#include "../shared/TLinkColorPolicy.h"
#include "../shared/TLinkNativeColorRange.h"
#include "../shared/TLinkNativeColorPoints.h"
#include <cassert>
#include <cstdio>
#include <thread>
#include "fixtures/color-match-legacy-v1.inc"
static uint32_t randomValue=73;
static unsigned randomByte(){randomValue=randomValue*1664525U+1013904223U;return randomValue>>24;}
static void nativeRangePolicyCases(){
    for(unsigned i=0;i<100000;++i){
        const double values[]={double(int(i)-50000)*47.125,double(i%16385)*0.5,double(int(i%17)-8)*0.5,double(int(i%19)-9)*0.5};
        int expected[4]={};bool valid=true;
        for(unsigned j=0;j<4;++j){char text[384];std::snprintf(text,sizeof(text),"%.0f",values[j]);const bool parsed=TLinkColorInt(text,expected[j]);valid=valid&&parsed;}
        TLinkNativeColorRangeRequest r;r.setRegion(values[0],values[1],values[2],values[3]);
        assert(r.coordinatesValid==valid&&r.x==expected[0]&&r.y==expected[1]&&r.width==expected[2]&&r.height==expected[3]);
        assert(TLinkNativeColorRangeParameters(r)==(valid&&expected[0]>=0&&expected[0]<8192&&expected[1]>=0&&expected[1]<8192));
    }
    for(double v:{-1e308,double(INT_MIN)-1,double(INT_MIN),-1.5,-0.5,-0.0,0.5,1.5,2.5,8191.49,8191.5,double(INT_MAX),double(INT_MAX)+0.5,1e308}){
        int expected=0;char text[384];std::snprintf(text,sizeof(text),"%.0f",v);bool valid=TLinkColorInt(text,expected);
        TLinkNativeColorRangeRequest r;r.setRegion(0,0,v,0);assert(r.coordinatesValid==valid);if(valid)assert(r.width==expected&&TLinkNativeColorRangeParameters(r));
        r.setRegion(v,0,0,0);assert(TLinkNativeColorRangeParameters(r)==(valid&&expected>=0&&expected<8192));
        char wire[2048];int units=std::snprintf(wire,sizeof(wire),"281;;%.0f;;%.0f;;%.0f;;%.0f;;%d;;%d;;%d;;%d;;%d;;%d;;%d",v,v,v,v,INT_MIN,INT_MAX,INT_MIN,INT_MAX,INT_MIN,INT_MAX,INT_MAX);
        assert(units>0&&size_t(units)<sizeof(wire)&&units<8192);
    }
    // 4 fixed finite doubles (at most 384 bytes each), 7 signed ints, task/action and separators.
    static_assert(4*384+7*12+25<8192,"finite findColor request must fit legacy ingress");
    TLinkNativeColorRangeRequest r;r.skip=INT_MAX;r.width=INT_MIN;r.height=INT_MAX;assert(TLinkNativeColorRangeParameters(r));
    r.skip=-1;assert(!TLinkNativeColorRangeParameters(r));r.skip=0;r.redMin=-1;assert(!TLinkNativeColorRangeParameters(r));r.redMin=0;r.redMax=256;assert(!TLinkNativeColorRangeParameters(r));r.redMax=255;
    r.greenMin=20;r.greenMax=19;assert(!TLinkNativeColorRangeParameters(r));r.greenMin=0;r.greenMax=255;r.blueMin=1;r.blueMax=0;assert(!TLinkNativeColorRangeParameters(r));
    r=TLinkNativeColorRangeRequest{};r.setRegion(NAN,0,0,0);assert(!r.coordinatesValid&&!TLinkNativeColorRangeParameters(r));r.setRegion(0,0,INFINITY,0);assert(!r.coordinatesValid);
    puts("Native live range policy passed: 100k frozen decimal/strict-int ROI cases, signed extents/half ties/overflow, RGB/skip admission and finite ingress ceiling.");
}
static void nativePointsPolicyCases(){
    std::vector<uint8_t> rgba(32*24*4);for(auto &byte:rgba)byte=uint8_t(randomByte());
    for(unsigned trial=0;trial<10000;++trial){
        TLinkNativeColorPointsRequest r;r.mode=int(trial%2);char threshold[384];std::snprintf(threshold,sizeof(threshold),"%.4f",r.mode?double(trial%256)+0.00004:double(trial%10001)/10000.0);
        r.toleranceUnits=std::strlen(threshold);r.toleranceValid=TLinkColorDouble(threshold,r.tolerance);std::string table;
        std::vector<TLinkColorPoint> legacy;bool tableValid=true;
        for(unsigned j=0;j<trial%8+1;++j){
            double x=double(int((trial+j)%37)-3)*0.5,y=double(int((trial+j)%29)-2)*0.5;
            if(trial%113==0)x=1e308;if(trial%127==0)y=double(INT_MIN);
            const int red=int((trial+j)%256),green=int(j%256),blue=int(trial%256);r.append(x,y,red,green,blue);
            char xs[384],ys[384],row[820];std::snprintf(xs,sizeof(xs),"%.0f",x);std::snprintf(ys,sizeof(ys),"%.0f",y);
            std::snprintf(row,sizeof(row),"%s,,%s,,%d,,%d,,%d",xs,ys,red,green,blue);if(j)table+='|';table+=row;
            TLinkColorPoint point={0,0,red,green,blue};bool valid=TLinkColorInt(xs,point.dx)&&TLinkColorInt(ys,point.dy);tableValid=tableValid&&valid;legacy.push_back(point);
        }
        assert(r.tableValid==tableValid&&r.tableUnits==table.size()&&r.pointCount==legacy.size()&&TLinkNativeColorPointsParameters(r));
        char suffix[96];std::snprintf(suffix,sizeof(suffix),";;%d;;%s",r.mode,threshold);const size_t base=std::strlen("282;;")+table.size()+std::strlen(suffix);
        assert(TLinkNativeColorPointsInputFits(r)==(base<=8192));
        if(!tableValid){assert(std::string(TLinkNativeColorPointsTableError(r))=="color_point_table_invalid");continue;}
        assert(!TLinkNativeColorPointsTableError(r));TLinkColorRect crop;bool bounded=true,matched=true;
        for(const auto &p:legacy)if(p.dx<0||p.dy<0||p.dx>=32||p.dy>=24)bounded=false;
        assert(TLinkNativeColorPointsBounds(r.points,32,24,crop)==bounded);if(!bounded)continue;
        for(const auto &p:legacy){const uint8_t *pixel=rgba.data()+(size_t(p.dy)*32+size_t(p.dx))*4;if(!legacyColorMatch(pixel[0],pixel[1],pixel[2],p.r,p.g,p.b,r.mode,r.tolerance)){matched=false;break;}}
        std::vector<uint8_t> cropped(size_t(crop.width)*crop.height*4);
        for(int y=0;y<crop.height;++y)std::memcpy(cropped.data()+size_t(y)*crop.width*4,rgba.data()+(size_t(crop.y+y)*32+size_t(crop.x))*4,size_t(crop.width)*4);
        bool got=false;TLinkColorRequest work({});assert(TLinkNativeColorPointsCompare(cropped.data(),crop.width,crop,r.points,r.mode,r.tolerance,work,got)&&got==matched);
    }
    TLinkNativeColorPointsRequest r;for(unsigned j=0;j<512;++j)r.append(0,0,0,0,0);
    assert(r.points.size()==512&&!TLinkNativeColorPointsTableError(r)&&TLinkNativeColorPointsInputFits(r));r.append(0,0,0,0,0);
    assert(r.points.size()==512&&r.pointCount==513&&std::string(TLinkNativeColorPointsTableError(r))=="color_point_table_limit");
    r=TLinkNativeColorPointsRequest{};for(unsigned i=0;i<512;++i)r.append(1e308,-1e308,INT_MIN,INT_MAX,0);assert(r.tableUnits==131073&&!TLinkNativeColorPointsInputFits(r)&&std::string(TLinkNativeColorPointsTableError(r))=="color_point_table_limit");
    r=TLinkNativeColorPointsRequest{};r.append(0,0,0,0,0);r.tableUnits=SIZE_MAX;assert(!TLinkNativeColorPointsInputFits(r));r.tableUnits=13;r.toleranceUnits=SIZE_MAX;assert(!TLinkNativeColorPointsInputFits(r));r.toleranceUnits=6;
    r.mode=2;assert(!TLinkNativeColorPointsParameters(r));r.mode=0;r.tolerance=1.0001;assert(!TLinkNativeColorPointsParameters(r));r.mode=1;r.tolerance=255.0001;assert(!TLinkNativeColorPointsParameters(r));r.tolerance=-0.0;assert(TLinkNativeColorPointsParameters(r));r.toleranceValid=false;assert(!TLinkNativeColorPointsParameters(r));
    for(unsigned extra=0;extra<2;++extra){r=TLinkNativeColorPointsRequest{};for(unsigned i=0;i<512;++i)r.append(i<3?2e307:(i==3?(extra?2e89:2e88):0),0,0,0,0);assert(r.tableUnits+16==8192+extra&&TLinkNativeColorPointsInputFits(r)==(extra==0));}
    TLinkColorRect crop;crop.width=crop.height=1;std::vector<TLinkColorPoint> points(2,TLinkColorPoint{0,0,0,0,0});uint8_t pixel[4]={};bool matched=false;
    {TLinkColorRequest work({},TLinkNativeNowNs(),1);assert(!TLinkNativeColorPointsCompare(pixel,1,crop,points,1,0,work,matched)&&work.stopped());}
    auto token=std::make_shared<TLinkNativeCancellation>();token->cancel();auto parent=std::make_shared<TLinkNativeBudget>(token,0,4096);
    {TLinkColorRequest work(parent);TLinkNativeColorPointsCompare(pixel,1,crop,points,1,0,work,matched);assert(work.stopped());}
    {TLinkColorRequest work({},TLinkNativeNowNs()-3000000001ULL);TLinkNativeColorPointsCompare(pixel,1,crop,points,1,0,work,matched);assert(work.stopped());}
    puts("Native live points policy passed: 10k frozen encodings/bounds/crop/predicates, exact 8192/8193 ingress, 512/513 storage, saturated table, mode/tolerance and work/cancel/deadline bounds.");
}
int main(){
    nativePointsPolicyCases();
    nativeRangePolicyCases();
    int number=0;double value=0;
    assert(TLinkColorInt(" -2147483648 ",number)&&number==INT_MIN);assert(TLinkColorInt("+2147483647",number)&&number==INT_MAX);
    for(auto text:{"", "nan", "1.2", "2147483648", "-2147483649", "12junk"})assert(!TLinkColorInt(text,number));
    assert(TLinkColorDouble(" .5 ",value)&&value==.5);assert(!TLinkColorDouble("nan",value)&&!TLinkColorDouble("1x",value));
    assert(TLinkColorMode(0,1)&&TLinkColorMode(1,255.0)&&!TLinkColorMode(0,1.1)&&!TLinkColorMode(1,256)&&!TLinkColorMode(2,.5));
    TLinkColorRect region,anchors,crop;
    assert(TLinkColorRegion(32,24,2,3,INT_MAX,0,false,region)&&region.width==30&&region.height==21);
    assert(TLinkColorRegion(32,24,INT_MIN,INT_MAX,-1,-1,true,region)&&region.x==0&&region.y==23);
    assert(!TLinkColorRegion(32,24,32,0,0,0,false,region)&&!TLinkColorRegion(8193,1,0,0,1,1,false,region));
    std::vector<TLinkColorPoint> impossible={{INT_MIN,0,0,0,0},{INT_MAX,0,0,0,0}};
    assert(!TLinkColorAnchors(32,24,region,impossible,anchors,crop));
    for(unsigned n=0;n<100000;++n){TLinkColorPoint p={0,0,int(randomByte()),int(randomByte()),int(randomByte())};int r=int(randomByte()),g=int(randomByte()),b=int(randomByte()),mode=n%2;double threshold=mode?double(n%256)+.1:double(n%101)/100;
        assert(TLinkColorMatch(r,g,b,p,mode,threshold)==legacyColorMatch(r,g,b,p.r,p.g,p.b,mode,threshold));}
    std::vector<uint8_t> rgba(32*24*4);
    for(unsigned n=0;n<5000;++n){
        for(auto &byte:rgba)byte=uint8_t(randomByte());int skip=int(n%4);
        TLinkColorPoint low={0,0,int(n%220),int(n%210),int(n%200)},high={0,0,255,255,255};TLinkColorResult got;
        bool found=false;int bx=0,by=0;
        for(int y=0;y<24&&!found;y+=skip+1)for(int x=0;x<32;x+=skip+1){const auto *p=rgba.data()+(y*32+x)*4;if(p[0]>=low.r&&p[1]>=low.g&&p[2]>=low.b){found=true;bx=x;by=y;break;}}
        {TLinkColorRequest request({});auto result=TLinkColorRangeScan(rgba.data(),32,24,skip,low,high,request,got);assert(result==(found?TLinkColorScan::Match:TLinkColorScan::NoMatch));if(found){assert(got.x==bx&&got.y==by);const auto *p=rgba.data()+(by*32+bx)*4;assert(got.r==p[0]&&got.g==p[1]&&got.b==p[2]);}}
        std::vector<TLinkColorPoint> points={{-1,-1,int(n%255),100,20},{2,1,50,60,70}};
        TLinkColorRect full;assert(TLinkColorRegion(32,24,0,0,0,0,false,full));assert(TLinkColorAnchors(32,24,full,points,anchors,crop));
        std::vector<uint8_t> cropped(size_t(crop.width)*crop.height*4);
        for(int y=0;y<crop.height;++y)std::memcpy(cropped.data()+size_t(y)*crop.width*4,rgba.data()+(size_t(crop.y+y)*32+crop.x)*4,size_t(crop.width)*4);
        int mode=n%2;double threshold=mode?double(n%200):double(n%10)/10;found=false;
        for(int y=anchors.y;y<anchors.y+anchors.height&&!found;y+=skip+1)for(int x=anchors.x;x<anchors.x+anchors.width;x+=skip+1){bool ok=true;for(const auto &point:points){const auto *p=rgba.data()+((y+point.dy)*32+x+point.dx)*4;if(!legacyColorMatch(p[0],p[1],p[2],point.r,point.g,point.b,mode,threshold)){ok=false;break;}}if(ok){found=true;bx=x;by=y;break;}}
        TLinkColorRequest request({});auto result=TLinkColorMultiScan(cropped.data(),crop.width,crop,anchors,points,mode,threshold,skip,request,got);
        assert(result==(found?TLinkColorScan::Match:TLinkColorScan::NoMatch));if(found)assert(got.x==bx&&got.y==by);
    }
    {TLinkColorRequest a({},100),b({},100),c({},100);assert(a.admitted()&&b.admitted()&&!c.admitted());assert(!a.stopped(3000000099ULL)&&a.stopped(3000000100ULL));}
    {TLinkColorRequest request({},TLinkNativeNowNs(),1);TLinkColorPoint low={0,0,256,256,256},high={0,0,256,256,256};TLinkColorResult result;assert(TLinkColorRangeScan(rgba.data(),32,24,INT_MAX,low,high,request,result)==TLinkColorScan::NoMatch);}
    {TLinkColorRequest request({},TLinkNativeNowNs(),1);TLinkColorPoint low={0,0,256,256,256},high=low;TLinkColorResult result;assert(TLinkColorRangeScan(rgba.data(),32,24,0,low,high,request,result)==TLinkColorScan::Stopped);assert(std::strcmp(request.error(),"color_work_limit")==0);}
    auto token=std::make_shared<TLinkNativeCancellation>();auto parent=std::make_shared<TLinkNativeBudget>(token,0,4096);{TLinkColorRequest request(parent);token->cancel();assert(request.stopped());}
    auto &memory=TLinkColorMemory();{auto charge=memory.reserve(TLinkImageKind::Frame,32*1024*1024);assert(charge&&!memory.reserve(TLinkImageKind::Frame,1));}assert(memory.stats().total==0);
    std::vector<std::thread> clients;for(unsigned n=0;n<8;++n)clients.emplace_back([&]{for(unsigned i=0;i<10000;++i){TLinkColorRequest request({});auto charge=memory.reserve(TLinkImageKind::Frame,4194304);assert(memory.stats().total<=32*1024*1024);}});for(auto &thread:clients)thread.join();assert(memory.stats().total==0);
    puts("Color core passed: 100k legacy predicate comparisons, 5000 range/multi-point golden cases, overflow/INT_MIN offsets and INT_MAX skip, deadline/work/cancel, 80k admission/byte lifecycles and zero final reservations.");
}
