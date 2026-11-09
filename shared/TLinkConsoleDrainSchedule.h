#pragma once
#include <cstdint>
// Caller holds its publication lock. Tokens identify jobs, independently of runs.
class TLinkConsoleDrainSchedule {
    uint64_t token_=0;
    bool scheduled_=false;
public:
    struct Lease {uint64_t token;bool starts;explicit operator bool()const{return token!=0;}};
    explicit TLinkConsoleDrainSchedule(uint64_t token=0):token_(token){}
    Lease prepare(){
        if(scheduled_)return {token_,false};
        if(token_==UINT64_MAX)return {0,false};
        ++token_;scheduled_=true;return {token_,true};
    }
    bool matches(uint64_t token)const{return scheduled_&&token==token_;}
    void rollback(Lease lease){if(lease.starts&&matches(lease.token))scheduled_=false;}
    bool retire(uint64_t token){if(!matches(token))return false;scheduled_=false;return true;}
    uint64_t current()const{return scheduled_?token_:0;}
};
