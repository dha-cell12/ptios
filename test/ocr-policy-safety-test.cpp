#include "../shared/TLinkOCRPolicy.h"
#include "../shared/TLinkNativeOCRInput.h"
#include <cassert>
#include <cstdio>
#include <thread>
#include <map>
static void typedOCRInputCases(){
    for(unsigned n=0;n<10000;++n){const int frame=n%2?1:INT_MAX,oem=int(n%7)-3,psm=int(n%29),scale=int(n%7)-1,threshold=int(n%5)-1,age=n%3?1000:INT_MIN;size_t regionUnits=0;std::string wire="91"+std::to_string(frame);
        for(unsigned i=0;i<4;++i){char part[384];std::snprintf(part,sizeof(part),"%.0f",n%73?double(int((n+i)%19)-4)*.5:1e308);regionUnits+=std::strlen(part);wire+=";;";wire+=part;}
        const size_t langUnits=n%31,whiteUnits=(n%200)*4;wire+=";;"+std::string(langUnits,'x')+";;"+std::to_string(oem)+";;"+std::to_string(psm)+";;"+std::string(whiteUnits,'x')+";;"+std::to_string(scale)+";;"+std::to_string(threshold)+";;;;"+std::to_string(age);
        const size_t limit=8192-wire.size();assert(TLinkNativeOCRInputFits(frame,oem,psm,scale,threshold,age,regionUnits,langUnits,whiteUnits,limit)&&!TLinkNativeOCRInputFits(frame,oem,psm,scale,threshold,age,regionUnits,langUnits,whiteUnits,limit+1));}
    for(unsigned field=0;field<4;++field){size_t units[]={4,3,0,5};units[field]=SIZE_MAX;assert(!TLinkNativeOCRInputFits(1,1,7,2,0,1000,units[0],units[1],units[2],units[3]));}
    puts("Typed OCR ingress passed: 10k frozen wire-length plans, signed scalar fields, huge finite ROI, exact 8192/8193 boundaries and saturated units.");
}
int main() {
    typedOCRInputCases();
    TLinkOCRImagePlan plan;
    assert(TLinkOCRPlanImage(500,500,4,false,plan) && plan.pixels == 4000000 && plan.width == 2000);
    assert(!TLinkOCRPlanImage(501,500,4,false,plan));
    for (auto width : {uint64_t(0),UINT64_MAX,uint64_t(INT_MAX)}) assert(!TLinkOCRPlanImage(width,2,4,false,plan));
    assert(TLinkOCRPlanImage(100,100,0,false,plan) && plan.scale == 1 && !plan.separateWork && plan.visibleBytes == 20000);
    assert(TLinkOCRPlanImage(100,100,1,true,plan) && plan.separateWork && plan.visibleBytes == 30000);
    assert(TLinkOCRPlanImage(500,500,99,true,plan) && plan.scale == 4);
    assert(TLinkOCRPlanImageExtent(499.5,500,4,true,plan) && plan.pixels == 4000000);
    assert(!TLinkOCRPlanImageExtent(500.1,500,4,true,plan));
    assert(!TLinkOCRPlanImageExtent(std::numeric_limits<double>::infinity(),1,1,false,plan));
    assert(!TLinkOCRPlanImageExtent(std::numeric_limits<double>::quiet_NaN(),1,1,false,plan));
    assert(!TLinkOCRPlanImageExtent(-1,1,1,false,plan));
    for (unsigned n=1;n<=100000;++n) {
        const unsigned w=n%2001+1, h=(n*17)%2001+1, scale=n%7;
        const bool valid=TLinkOCRPlanImage(w,h,static_cast<int>(scale),n%2 != 0,plan);
        const uint64_t s=std::max(1U,std::min(4U,scale));
        assert(valid == (uint64_t(w)*h*s*s<=kTLinkOCRMaxScaledPixels));
        if(valid) assert(plan.visibleBytes<=kTLinkOCRVisibleGrayBytes);
    }
    TLinkOCRLRU<std::string,std::shared_ptr<int>> cache;
    std::weak_ptr<int> evicted;
    for (unsigned n=0;n<100000;++n) {
        cache.prepareMiss(); assert(cache.size()<=1);
        auto value=std::make_shared<int>(static_cast<int>(n));
        cache.insert(std::to_string(n),value); assert(cache.size()<=2);
        if(n==0) evicted=value;
        if(n>1) assert(evicted.expired());
    }
    assert(*cache.find("99999")==99999); cache.clear(); assert(cache.size()==0);
    cache.insert("a",std::make_shared<int>(1)); cache.insert("b",std::make_shared<int>(2));
    assert(cache.find("a")); cache.prepareMiss(); assert(!cache.find("b") && cache.find("a")); cache.clear();
    std::atomic<unsigned> active{0};
    { TLinkOCRAdmission one(active),two(active),three(active); assert(one && two && !three && active==2); }
    assert(active==0); std::vector<std::thread> clients;
    for(unsigned n=0;n<8;++n) clients.emplace_back([&] { for(unsigned j=0;j<10000;++j) { TLinkOCRAdmission slot(active); assert(active<=2); } });
    for(auto &client:clients) client.join(); assert(active==0);
    const uint64_t start=TLinkNativeNowNs(); TLinkOCRRequestBudget local({},start);
    assert(!local.stopped(start+2999999999ULL) && local.stopped(start+3000000000ULL));
    assert(local.remainingSeconds(start+2000000000ULL)<=1.0);
    auto token=std::make_shared<TLinkNativeCancellation>();
    auto parent=std::make_shared<TLinkNativeBudget>(token,TLinkNativeDeadline(.5),4096);
    TLinkOCRRequestBudget child(parent); assert(child.remainingSeconds()<=.5); token->cancel(); assert(child.stopped());
    puts("OCR policy passed: 100k scale/buffer plans, 100k bounded LRU identities, eviction ownership, 80k admission cycles, full-request deadline and inherited cancellation.");
}
