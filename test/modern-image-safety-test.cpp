#include "../shared/TLinkModernImagePolicy.h"
#include <cassert>
#include <cstdio>
#include <functional>
using BOOL=bool;
#include "modern-image-fixture.h"
#include "ModernSadUnderTest.inc"
#include "ModernScaleUnderTest.inc"
#include "fixtures/image-matcher-legacy-v1.inc"
int main(){
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
