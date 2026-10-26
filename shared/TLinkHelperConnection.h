#ifndef TLINK_HELPER_CONNECTION_H
#define TLINK_HELPER_CONNECTION_H
#include "TLinkHelperClientAdmission.h"
#include "TLinkHelperRequestDeadline.h"
#include <string>
struct TLinkHelperConnectionLease {uint64_t until=0;unsigned remaining=0;};
class TLinkHelperConnectionWindow {
    uint64_t end_;unsigned completed_=0;
public:
    enum : int {Limit=4,IdleMs=1000,LifetimeMs=10000,MaxRequests=32};
    explicit TLinkHelperConnectionWindow(uint64_t now):end_(TLinkHelperIO::Deadline(now,LifetimeMs).end){}
    uint64_t end()const{return end_;}
    TLinkHelperConnectionLease complete(uint64_t now){
        if(completed_>=MaxRequests)return {};
        ++completed_;if(completed_==MaxRequests||now>=end_)return {};
        return {std::min(end_,TLinkHelperIO::Deadline(now,IdleMs).end),static_cast<unsigned>(MaxRequests)-completed_};
    }
    static bool valid(TLinkHelperConnectionLease lease,uint64_t now){
        return lease.remaining>0&&lease.remaining<MaxRequests&&lease.until<=TLinkHelperIO::MaxWireTime&&
            lease.until>now&&lease.until-now<=IdleMs;
    }
};
class TLinkHelperConnectionAdmission : public TLinkHelperClientAdmission {
public:TLinkHelperConnectionAdmission():TLinkHelperClientAdmission(TLinkHelperConnectionWindow::Limit){}
};
#if !defined(_WIN32)
// One synchronous run-owned channel. Taking transfers FD ownership to a local Socket;
// every error then closes it. Only a fully validated reply may return it to the cache.
class TLinkHelperConnectionCache {
    TLinkHelperIO::Socket socket_{-1};
    TLinkHelperConnectionLease lease_;
    std::string helper_,session_;
public:
    void close(){socket_.close();lease_={};helper_.clear();session_.clear();}
    int take(const std::string &helper,const std::string &session,uint64_t now,TLinkHelperConnectionLease &previous){
        if(helper!=helper_||session!=session_||!TLinkHelperConnectionWindow::valid(lease_,now)){close();return -1;}
        previous=lease_;const int fd=socket_.release();lease_={};helper_.clear();session_.clear();return fd;
    }
    void keep(TLinkHelperIO::Socket &socket,const std::string &helper,const std::string &session,TLinkHelperConnectionLease lease){
        close();helper_=helper;session_=session;lease_=lease;
        socket_.reset(socket.release());
    }
};
#endif
#ifdef __OBJC__
static inline bool TLinkHelperConnectionCommand(NSString *command){
    return [command isEqual:@"status"]||[command isEqual:@"nativeRPCResponse"]||[command isEqual:@"waitForChange"];
}
static inline bool TLinkHelperReadConnectionLease(NSDictionary *response,uint64_t now,TLinkHelperConnectionLease &lease){
    id value=response[@"connectionLease"];uint64_t until=0,remaining=0;
    if(![value isKindOfClass:[NSDictionary class]]||[value count]!=3||![value[@"contract"] isEqual:@"sequential_v1"]||
        !TLinkHelperWireTime(value[@"untilMs"],until)||!TLinkHelperWireTime(value[@"remaining"],remaining)||remaining>=TLinkHelperConnectionWindow::MaxRequests)return false;
    lease={until,static_cast<unsigned>(remaining)};
    // A lease can expire in transit without invalidating the correlated reply.
    return remaining>0&&until<=TLinkHelperIO::MaxWireTime&&(until<=now||until-now<=TLinkHelperConnectionWindow::IdleMs);
}
static inline NSDictionary *TLinkHelperConnectionLeaseValue(TLinkHelperConnectionLease lease){
    return @{@"contract":@"sequential_v1",@"untilMs":@(lease.until),@"remaining":@(lease.remaining)};
}
#endif
#endif
