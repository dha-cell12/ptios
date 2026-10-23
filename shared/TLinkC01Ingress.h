#ifndef TLINK_C01_INGRESS_H
#define TLINK_C01_INGRESS_H
#include "TLinkNativeBudget.h"
static const int TLinkC01IPCMessage=3;
static const size_t TLinkC01IPCHeaderBytes=12;
// Socket-queue-owned admission: reserve capacity in both serial lanes. Counts
// include running, queued and completion-pending work, even after disconnect.
static const size_t TLinkC01ImagePendingLimit=2;
static const size_t TLinkC01OrdinaryPendingLimit=14;
inline bool TLinkC01LaneAvailable(bool image,size_t pending,size_t images) {
    if(images>pending||images>TLinkC01ImagePendingLimit||pending-images>TLinkC01OrdinaryPendingLimit||pending>=TLinkC01ImagePendingLimit+TLinkC01OrdinaryPendingLimit)return false;
    return image?images<TLinkC01ImagePendingLimit:pending-images<TLinkC01OrdinaryPendingLimit;
}
// Classification only; existing task parsers/license gates remain authoritative.
inline uint64_t TLinkC01DurationNs(const uint8_t *task,size_t length) {
    if(!task||length<2||task[0]<'0'||task[0]>'9'||task[1]<'0'||task[1]>'9')return 0;
    const int type=(task[0]-'0')*10+task[1]-'0';
    switch(type){
        case 23:case 28:case 69:case 91:return 3000000000ULL;
        case 21:case 49:case 68:case 70:return 8000000000ULL;
        case 27:return length>=3&&(task[2]=='1'||task[2]=='6')?8000000000ULL:0;
        default:return 0;
    }
}
inline TLinkNativeBudgetPtr TLinkC01TaskBudget(const uint8_t *task,size_t length,TLinkNativeBudgetPtr parent,uint64_t entered=TLinkNativeNowNs()) {
    const uint64_t duration=TLinkC01DurationNs(task,length);
    if(!duration)return parent;
    const uint64_t end=entered+std::min(duration,uint64_t(INT64_MAX)-std::min(entered,uint64_t(INT64_MAX)));
    return std::make_shared<TLinkNativeBudget>(end,std::move(parent));
}
inline bool TLinkC01IPCPayload(const uint8_t *bytes,size_t length) {
    if(!bytes||length<8||length>4095||std::memcmp(bytes,"TASK::",6)!=0||std::memchr(bytes,0,length))return false;
    if(TLinkC01DurationNs(bytes+6,length-6))return true;
    // Private helpers invoked by daemon task 21 inherit that same request deadline.
    return (bytes[6]=='2'&&bytes[7]=='9')||(bytes[6]=='3'&&bytes[7]=='5');
}
// Dedicated port v1 accepts read-only C01 work and task-21's owned capture /
// orientation helpers. Ordinary screenshot/album mutations stay on the legacy port.
inline bool TLinkC01IsolatedPayload(const uint8_t *bytes,size_t length) {
    if(!TLinkC01IPCPayload(bytes,length))return false;
    if(TLinkC01DurationNs(bytes+6,length-6))return true;
    return (length==8&&std::memcmp(bytes+6,"35",2)==0)||
        (length>11&&std::memcmp(bytes,"TASK::294;;",11)==0);
}
inline bool TLinkC01PrivateIPC(const uint8_t *bytes,size_t length,bool reply,TLinkNativeBudgetPtr budget) {
    return reply&&budget&&budget->deadline()&&TLinkC01IPCPayload(bytes,length);
}
// A nested framework run loop must not reenter another private image handler.
class TLinkC01IPCAdmission {
    std::atomic_bool &active_;bool admitted_;
public:
    explicit TLinkC01IPCAdmission(std::atomic_bool &active):active_(active),admitted_(false){
        bool expected=false;admitted_=active_.compare_exchange_strong(expected,true,std::memory_order_acq_rel);
    }
    bool admitted()const{return admitted_;}
    ~TLinkC01IPCAdmission(){if(admitted_)active_.store(false,std::memory_order_release);}
    TLinkC01IPCAdmission(const TLinkC01IPCAdmission &)=delete;TLinkC01IPCAdmission &operator=(const TLinkC01IPCAdmission &)=delete;
};
inline std::vector<uint8_t> TLinkC01Encode(const uint8_t *payload,size_t length,uint64_t deadline) {
    if(!deadline||!TLinkC01IPCPayload(payload,length))return {};
    std::vector<uint8_t> bytes(TLinkC01IPCHeaderBytes+length);
    std::memcpy(bytes.data(),"TC01",4);
    for(unsigned i=0;i<8;++i)bytes[4+i]=uint8_t(deadline>>(56-i*8));
    std::memcpy(bytes.data()+TLinkC01IPCHeaderBytes,payload,length);return bytes;
}
enum class TLinkC01DecodeResult {Valid,Invalid,Expired};
struct TLinkC01Envelope {const uint8_t *payload=nullptr;size_t length=0;uint64_t deadline=0;};
inline TLinkC01DecodeResult TLinkC01Decode(const uint8_t *bytes,size_t length,TLinkC01Envelope &out,uint64_t now=TLinkNativeNowNs()) {
    out=TLinkC01Envelope();
    if(!bytes||length<TLinkC01IPCHeaderBytes+8||length>TLinkC01IPCHeaderBytes+4095||std::memcmp(bytes,"TC01",4)!=0)return TLinkC01DecodeResult::Invalid;
    uint64_t deadline=0;for(unsigned i=0;i<8;++i)deadline=(deadline<<8)|bytes[4+i];
    if(!deadline||!TLinkC01IPCPayload(bytes+TLinkC01IPCHeaderBytes,length-TLinkC01IPCHeaderBytes))return TLinkC01DecodeResult::Invalid;
    if(now>=deadline)return TLinkC01DecodeResult::Expired;
    if(deadline-now>8000000000ULL)return TLinkC01DecodeResult::Invalid;
    out.payload=bytes+TLinkC01IPCHeaderBytes;out.length=length-TLinkC01IPCHeaderBytes;out.deadline=deadline;
    return TLinkC01DecodeResult::Valid;
}
// CFMessagePort takes independent send/receive limits. Their sum fits remaining
// time at call entry; opaque framework overrun is still non-preemptible.
struct TLinkC01IPCWaits { double send,receive; };
inline TLinkC01IPCWaits TLinkC01IPCTimeouts(TLinkNativeBudgetPtr budget,double maximum) {
    if(!budget)return {maximum,maximum};
    const double remaining=budget->remainingSeconds(maximum*2);
    const double send=std::min(maximum,remaining*.1);
    return {send,std::min(maximum,remaining-send)};
}
#endif
