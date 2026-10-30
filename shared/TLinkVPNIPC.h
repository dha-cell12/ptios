#ifndef TLINK_VPN_IPC_H
#define TLINK_VPN_IPC_H
#include "TLinkNativeBudget.h"
static const int TLinkVPNIPCMessage=4;
static const size_t TLinkVPNIPCHeaderBytes=12;
static const char *const TLinkVPNIPCPortName="com.tlinkauto.tlinkautod.springboard.vpn.v1";
inline bool TLinkVPNIPCRequest(const uint8_t *bytes,size_t length){
    return bytes&&length>=8&&std::memcmp(bytes,"TASK::59",8)==0;
}
inline bool TLinkVPNIPCPayload(const uint8_t *bytes,size_t length){
    return TLinkVPNIPCRequest(bytes,length)&&length<=4095&&!std::memchr(bytes,0,length);
}
inline TLinkNativeBudgetPtr TLinkVPNIPCBudget(TLinkNativeBudgetPtr parent){
    return std::make_shared<TLinkNativeBudget>(TLinkNativeDeadline(30),std::move(parent));
}
inline std::vector<uint8_t> TLinkVPNIPCEncode(const uint8_t *bytes,size_t length,uint64_t deadline){
    if(!deadline||!TLinkVPNIPCPayload(bytes,length))return {};
    std::vector<uint8_t> frame(TLinkVPNIPCHeaderBytes+length);
    std::memcpy(frame.data(),"TVP1",4);
    for(unsigned i=0;i<8;++i)frame[4+i]=uint8_t(deadline>>(56-i*8));
    std::memcpy(frame.data()+TLinkVPNIPCHeaderBytes,bytes,length);return frame;
}
enum class TLinkVPNIPCDecodeResult {Valid,Invalid,Expired};
struct TLinkVPNIPCEnvelope {const uint8_t *payload=nullptr;size_t length=0;uint64_t deadline=0;};
inline TLinkVPNIPCDecodeResult TLinkVPNIPCDecode(const uint8_t *bytes,size_t length,TLinkVPNIPCEnvelope &out,uint64_t now=TLinkNativeNowNs()){
    out={};
    if(!bytes||length<TLinkVPNIPCHeaderBytes+8||length>TLinkVPNIPCHeaderBytes+4095||std::memcmp(bytes,"TVP1",4)!=0)return TLinkVPNIPCDecodeResult::Invalid;
    uint64_t deadline=0;for(unsigned i=0;i<8;++i)deadline=(deadline<<8)|bytes[4+i];
    if(!deadline||!TLinkVPNIPCPayload(bytes+TLinkVPNIPCHeaderBytes,length-TLinkVPNIPCHeaderBytes))return TLinkVPNIPCDecodeResult::Invalid;
    if(now>=deadline)return TLinkVPNIPCDecodeResult::Expired;
    if(deadline-now>30000000000ULL)return TLinkVPNIPCDecodeResult::Invalid;
    out={bytes+TLinkVPNIPCHeaderBytes,length-TLinkVPNIPCHeaderBytes,deadline};return TLinkVPNIPCDecodeResult::Valid;
}
struct TLinkVPNIPCWaits {double send,receive;};
inline TLinkVPNIPCWaits TLinkVPNIPCTimeouts(TLinkNativeBudgetPtr budget){
    const double left=budget?budget->remainingSeconds(30):0;
    const double send=std::min(1.0,left*.1);return {send,left-send};
}
#endif
