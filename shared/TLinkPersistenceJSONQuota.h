#pragma once
#include <cstddef>

class TLinkPersistenceJSONQuota {
    std::size_t limit_=0,bytes_=0;
    bool failed_=false;
public:
    explicit TLinkPersistenceJSONQuota(std::size_t limit=0):limit_(limit){}
    bool append(std::size_t bytes){
        if(failed_)return false;
        if(bytes>limit_-bytes_){failed_=true;return false;}
        bytes_+=bytes;return true;
    }
    void fail(){failed_=true;}
    std::size_t size()const{return bytes_;}
    bool failed()const{return failed_;}
};
