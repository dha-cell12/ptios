#include "../shared/TLinkTemplatePolicy.h"
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <thread>
struct Mat {
    int cols,rows;std::vector<unsigned char> bytes;
    Mat(int w,int h):cols(w),rows(h),bytes(size_t(w)*h){}
    template<class T>const T *ptr(int row)const{return reinterpret_cast<const T *>(bytes.data()+size_t(row)*cols);}
};
#include "TemplateSadUnderTest.inc"
#include "../test/fixtures/template-sad-legacy-v1.inc"
#include "TemplateKeyUnderTest.inc"
int main(){
    assert(TLinkTemplateParametersValid(8,.1,0)&&TLinkTemplateParametersValid(0,1.9,1));
    assert(!TLinkTemplateParametersValid(9,.8,.8)&&!TLinkTemplateParametersValid(-1,.8,.8));
    assert(!TLinkTemplateParametersValid(2,std::numeric_limits<double>::quiet_NaN(),.8));
    assert(!TLinkTemplateParametersValid(2,.8,std::numeric_limits<double>::infinity()));
    auto round=[](double x){return static_cast<int>(std::nearbyint(x));};TLinkTemplatePlan plan;
    assert(TLinkTemplateMakePlan(100,100,8,8,1,2,.8f,round,plan)&&plan.scales.size()==5);
    assert(TLinkTemplateMakePlan(100,100,8,8,1,8,1,round,plan)&&plan.scales.size()==1);
    assert(!TLinkTemplateMakePlan(100,100,8,8,1,100000,.8f,round,plan));
    assert(!TLinkTemplateMakePlan(INT_MAX,100,8,8,1,2,.8f,round,plan));
    assert(TLinkTemplateMakePlan(100,100,100,100,1,8,.1f,round,plan));
    for(const auto &s:plan.scales)assert(s.width>0&&s.height>0&&s.width<=100&&s.height<=100);
    assert(!TLinkTemplateMakePlan(2800,2800,2000,2000,1,8,.99f,round,plan));
    bool limited=false;
    for(int side=1200;side<2800;side+=50) if(!TLinkTemplateMakePlan(2800,2800,side,side,1,8,.9f,round,plan))limited=true;
    assert(limited);
    assert(TLinkTemplateMakePlan(80,60,9,7,1,2,.8f,round,plan));
    auto key=zx_tmScaledKey("file",plan,.8f,2);
    assert(key!=zx_tmScaledKey("file",plan,std::nextafter(.8f,1.0f),2));
    auto different=plan;++different.screenWidth;assert(key!=zx_tmScaledKey("file",different,.8f,2));
    // Frozen production oracle: preserve both SAD result and first-minimum coordinates.
    uint32_t random=17;
    for(unsigned n=0;n<3000;++n){
        Mat image(30,24),templ(2+int(n%9),2+int(n%7));
        for(auto &v:image.bytes){random=random*1664525U+1013904223U;v=static_cast<unsigned char>(random>>24);}
        for(auto &v:templ.bytes){random=random*1664525U+1013904223U;v=static_cast<unsigned char>(random>>24);}
        int x=0,y=0,lx=0,ly=0;int step=n%2?1:4;
        auto current=zx_sad_match_region(image,templ,-3,-2,30,24,step,&x,&y);
        auto previous=legacyTemplateSad(image,templ,-3,-2,30,24,step,&lx,&ly);
        assert(current==previous&&x==lx&&y==ly);
    }
    auto request=std::make_shared<TLinkTemplateRequest>(TLinkNativeBudgetPtr{});assert(request->consume(256000000));
    {TLinkTemplateRequestScope scope(request);Mat image(4,4),templ(2,2);int x=0,y=0;assert(zx_sad_match_region(image,templ,0,0,2,2,1,&x,&y)==LLONG_MAX);}
    assert(std::string(request->error())=="template_work_limit");
    auto cancelled=std::make_shared<TLinkNativeCancellation>();auto parent=std::make_shared<TLinkNativeBudget>(cancelled,0,4096);
    request=std::make_shared<TLinkTemplateRequest>(parent);cancelled->cancel();assert(request->stopped());
    uint64_t start=TLinkNativeNowNs();TLinkTemplateRequest deadline({},start);
    assert(!deadline.stopped(start+7999999999ULL)&&deadline.stopped(start+8000000000ULL));
    TLinkImageMemory memory(64,32,96);
    struct Payload {std::shared_ptr<TLinkImageCharge> charge;};
    TLinkTemplateLRU<std::shared_ptr<Payload>> cache;
    auto held=std::make_shared<Payload>();held->charge=memory.reserve(TLinkImageKind::Image,32);cache.put("a",held,16);cache.clear();
    assert(memory.stats().images==32&&!memory.reserve(TLinkImageKind::Image,1));held.reset();assert(memory.stats().total==0);
    std::vector<std::thread> clients;
    for(unsigned n=0;n<8;++n)clients.emplace_back([&]{for(unsigned i=0;i<10000;++i){auto charge=memory.reserve(TLinkImageKind::Image,8);auto stats=memory.stats();assert(stats.images<=32&&stats.total<=96);}});
    for(auto &client:clients)client.join();assert(memory.stats().total==0);
    for(unsigned n=0;n<100000;++n){auto value=std::make_shared<Payload>();value->charge=memory.reserve(TLinkImageKind::Image,1);assert(value->charge);cache.put(std::to_string(n),value,16);assert(cache.size()<=16);}
    cache.clear();assert(memory.stats().total==0);
    puts("Template core passed: checked scale/pyramid plans, exact float keys, 3000 production SAD golden cases, cooperative deadline/work/cancel, held-reader accounting, 80k reservations and 100k LRU lifecycles.");
}
