#include "../shared/TLinkColorPolicy.h"
#include <cassert>
#include <cstdio>
#include <thread>
#include "fixtures/color-match-legacy-v1.inc"
static uint32_t randomValue=73;
static unsigned randomByte(){randomValue=randomValue*1664525U+1013904223U;return randomValue>>24;}
int main(){
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
