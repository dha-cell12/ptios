#include "../shared/TLinkFrameVisionPolicy.h"
#include <cassert>
#include <cstdio>
int main(){
    uint32_t id=0;assert(TLinkFrameVisionUnsigned("2147483647\r\n",INT_MAX,id)&&id==INT_MAX);
    for(auto value:{"", "-1", "1x", "2147483648", "999999999999999999999999999999"})assert(!TLinkFrameVisionUnsigned(value,INT_MAX,id));
    assert(TLinkFrameVisionUnsigned("0",5000,id)&&id==0);assert(TLinkFrameVisionUnsigned("5000",5000,id));assert(!TLinkFrameVisionUnsigned("5001",5000,id));
    TLinkVisionROI roi;
    assert(TLinkFrameVisionRegion(100,80,2,true,5,10,25,20,roi)&&roi.x==10&&roi.y==20&&roi.width==50&&roi.height==40);
    assert(TLinkFrameVisionRegion(100,80,3,false,5,10,0,0,roi)&&roi.x==5&&roi.width==95&&roi.height==70);
    assert(TLinkFrameVisionRegion(100,80,2,true,5,10,10000,10000,roi)&&roi.width==90&&roi.height==60);
    assert(!TLinkFrameVisionRegion(100,80,0,true,5,10,25,20,roi));
    assert(!TLinkFrameVisionRegion(100,80,2,true,50,0,0,0,roi));
    assert(!TLinkFrameVisionRegion(100,80,2,true,-1,0,0,0,roi));
    assert(!TLinkFrameVisionRegion(100,80,2,true,0,0,-1,0,roi));
    assert(!TLinkFrameVisionRegion(100,80,2,true,0,0,std::numeric_limits<double>::infinity(),0,roi));
    assert(!TLinkFrameVisionRegion(8193,1,1,false,0,0,1,1,roi));
    assert(!TLinkFrameVisionRegion(3000,2000,1,false,0,0,0,0,roi));
    for(unsigned n=0;n<100000;++n){double x=(n%50)/2.0,y=(n%40)/2.0;assert(TLinkFrameVisionRegion(100,80,2,true,x,y,0,0,roi));assert(roi.x==x*2&&roi.y==y*2&&roi.width==100-roi.x&&roi.height==80-roi.y);}
    // Pixel ownership/admission uses the original immutable frame charge, without
    // allocating a second payload when readers survive store erasure.
    TLinkImageMemory memory(1024,0,1024);
    struct Frame {std::shared_ptr<TLinkImageCharge> charge;std::vector<uint8_t> bgra;};
    auto frame=std::make_shared<Frame>();frame->charge=memory.reserve(TLinkImageKind::Frame,1024);frame->bgra.resize(1024,42);
    std::shared_ptr<const Frame> reader=frame;const uint8_t *address=reader->bgra.data();frame.reset();
    assert(reader->bgra.data()==address&&reader->bgra[0]==42&&memory.stats().frames==1024&&!memory.reserve(TLinkImageKind::Frame,1));reader.reset();assert(memory.stats().total==0);
    puts("Frame Vision policy passed: strict id/age, 100k pixel/point/round/clip plans, pixel/ROI bounds and immutable charged readers.");
}
