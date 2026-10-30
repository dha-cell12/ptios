#include "../shared/TLinkVPNIPC.h"
#include "../shared/TLinkC01Ingress.h"
#include "../shared/TLinkVPNTaskAdmission.h"
#include <cassert>
#include <cstdio>
#include <string>
int main(){
    assert(TLinkVPNIPCMessage!=TLinkC01IPCMessage&&std::strlen(TLinkVPNIPCPortName)>0);
    for(unsigned n=0;n<100000;++n){
        const uint64_t now=100000000000ULL,span=n%4==0?0:n%4==1?1:n%4==2?30000000000ULL:30000000001ULL;
        const std::string payload="TASK::59"+std::string(n%4088,'x');
        const auto bytes=TLinkVPNIPCEncode(reinterpret_cast<const uint8_t *>(payload.data()),payload.size(),now+span);
        assert(bytes.size()==12+payload.size());TLinkVPNIPCEnvelope envelope;
        const auto result=TLinkVPNIPCDecode(bytes.data(),bytes.size(),envelope,now);
        const auto expected=span==0?TLinkVPNIPCDecodeResult::Expired:span>30000000000ULL?TLinkVPNIPCDecodeResult::Invalid:TLinkVPNIPCDecodeResult::Valid;
        assert(result==expected);
        if(result==TLinkVPNIPCDecodeResult::Valid)assert(envelope.deadline==now+span&&envelope.length==payload.size()&&std::memcmp(envelope.payload,payload.data(),payload.size())==0);
        else assert(!envelope.payload&&!envelope.length&&!envelope.deadline);
    }
    for(const std::string &payload:{std::string(""),std::string("TASK::58"),std::string("TASK::60"),std::string("TASK::590\0bad",12),std::string("CMD_PING"),"TASK::59"+std::string(4088,'x')}){
        assert(!TLinkVPNIPCPayload(reinterpret_cast<const uint8_t *>(payload.data()),payload.size()));
        assert(TLinkVPNIPCEncode(reinterpret_cast<const uint8_t *>(payload.data()),payload.size(),100).empty());
    }
    assert(!TLinkVPNIPCPayload(nullptr,8));
    const std::string oversized="TASK::59"+std::string(4088,'x');
    assert(TLinkVPNIPCRequest(reinterpret_cast<const uint8_t *>(oversized.data()),oversized.size())&&!TLinkVPNIPCPayload(reinterpret_cast<const uint8_t *>(oversized.data()),oversized.size()));
    const std::string payload="TASK::591;;1";
    auto good=TLinkVPNIPCEncode(reinterpret_cast<const uint8_t *>(payload.data()),payload.size(),1000);TLinkVPNIPCEnvelope out;
    for(size_t length=0;length<20;++length)assert(TLinkVPNIPCDecode(good.data(),length,out,100)==TLinkVPNIPCDecodeResult::Invalid);
    for(size_t index:std::initializer_list<size_t>{0,1,2,3,12,18,19}){auto bad=good;bad[index]=0;assert(TLinkVPNIPCDecode(bad.data(),bad.size(),out,100)==TLinkVPNIPCDecodeResult::Invalid);}
    assert(TLinkVPNIPCDecode(nullptr,good.size(),out,100)==TLinkVPNIPCDecodeResult::Invalid);
    auto parent=std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},TLinkNativeDeadline(2),1024);
    const uint64_t original=parent->deadline();auto child=TLinkVPNIPCBudget(parent);assert(child->deadline()==original&&parent->deadline()==original);
    const auto waits=TLinkVPNIPCTimeouts(child);assert(waits.send>0&&waits.send<=1&&waits.receive>0&&waits.send+waits.receive<=2);
    auto token=std::make_shared<TLinkNativeCancellation>();parent=std::make_shared<TLinkNativeBudget>(token,0,1024);child=TLinkVPNIPCBudget(parent);token->cancel();
    assert(child->stopped()&&TLinkVPNIPCTimeouts(child).send==0&&TLinkVPNIPCTimeouts(child).receive==0);
    assert(TLinkVPNIPCTimeouts({}).send==0);
    const uint64_t started=TLinkNativeNowNs();child=TLinkVPNIPCBudget({});assert(child->deadline()>=started+30000000000ULL&&child->deadline()<=TLinkNativeNowNs()+30000000000ULL);
    std::atomic_bool active{false};{TLinkC01IPCAdmission first(active);assert(first.admitted());{TLinkC01IPCAdmission nested(active);assert(!nested.admitted());}assert(active.load());}assert(!active.load());
    for(size_t pending=0;pending<=18;++pending)for(size_t images=0;images<=18;++images)for(size_t vpns=0;vpns<=18;++vpns)for(unsigned lane=0;lane<3;++lane){
        const bool vpn=lane==2,image=lane==1;
        const bool valid=images<=pending&&vpns<=pending-images&&vpns<=2&&TLinkC01LaneAvailable(image,pending,images)&&(!vpn||vpns<2);
        assert(TLinkVPNTaskLaneAvailable(vpn,image,pending,images,vpns)==valid);
    }
    assert(!TLinkVPNTaskLaneAvailable(true,true,0,0,0));
    for(unsigned n=0;n<100000;++n){
        size_t pending=0,images=0,vpns=0;
        assert(TLinkVPNTaskLaneAvailable(true,false,pending,images,vpns));++pending;++vpns;
        assert(TLinkVPNTaskLaneAvailable(true,false,pending,images,vpns));++pending;++vpns;
        assert(!TLinkVPNTaskLaneAvailable(true,false,pending,images,vpns));
        for(unsigned ordinary=0;ordinary<12;++ordinary){assert(TLinkVPNTaskLaneAvailable(false,false,pending,images,vpns));++pending;}
        assert(!TLinkVPNTaskLaneAvailable(false,false,pending,images,vpns));
        for(unsigned image=0;image<2;++image){assert(TLinkVPNTaskLaneAvailable(false,true,pending,images,vpns));++pending;++images;}
        assert(pending==16&&!TLinkVPNTaskLaneAvailable(false,true,pending,images,vpns));
        // Disconnect does not change pending ownership; only completion ACK retires.
        assert(vpns==2&&!TLinkVPNTaskLaneAvailable(true,false,pending,images,vpns));
        --pending;--vpns;assert(TLinkVPNTaskLaneAvailable(true,false,pending,images,vpns));
        pending-=vpns;vpns=0;pending-=images;images=0;pending-=12;assert(!pending&&!images&&!vpns);
    }
    assert(TLinkVPNTaskPayload(reinterpret_cast<const uint8_t *>("590"),3)&&TLinkVPNTaskPayload(reinterpret_cast<const uint8_t *>("59"),2));
    assert(!TLinkVPNTaskPayload(nullptr,2)&&!TLinkVPNTaskPayload(reinterpret_cast<const uint8_t *>("5"),1)&&!TLinkVPNTaskPayload(reinterpret_cast<const uint8_t *>("60"),2));
    puts("VPN IPC core passed: 100k task/deadline envelope cases, strict 4095/NUL/type/header boundaries, parent deadline/cancel, bounded send+receive allocation and reentry ownership.");
    puts("VPN task admission passed: exhaustive invalid counters, two VPN within fourteen ordinary plus two image slots, no early disconnect release, 100k admission/ACK lifecycles and unchanged task classification.");
}
