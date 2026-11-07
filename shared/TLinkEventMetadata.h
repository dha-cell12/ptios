#pragma once
#include <cstddef>
#include <cstdint>
#include "TLinkASCIIPreparation.h"

namespace TLinkEventMetadata {
struct Stamp {
    enum class Kind { Empty, Missing, Present };
    Kind kind=Kind::Empty;
    int error=0;
    std::uint64_t device=0,inode=0;
    std::int64_t size=0,modifiedSeconds=0,modifiedNanos=0,changedSeconds=0,changedNanos=0;
    static Stamp Missing(int code){Stamp value;value.kind=Kind::Missing;value.error=code;return value;}
    static Stamp Present(std::uint64_t device,std::uint64_t inode,std::int64_t size,
                         std::int64_t modifiedSeconds,std::int64_t modifiedNanos,
                         std::int64_t changedSeconds,std::int64_t changedNanos){
        Stamp value;value.kind=Kind::Present;value.device=device;value.inode=inode;value.size=size;
        value.modifiedSeconds=modifiedSeconds;value.modifiedNanos=modifiedNanos;
        value.changedSeconds=changedSeconds;value.changedNanos=changedNanos;return value;
    }
    explicit operator bool()const{return kind!=Kind::Empty;}
    bool operator==(const Stamp &other)const{
        if(kind!=other.kind)return false;
        if(kind==Kind::Empty)return true;
        if(kind==Kind::Missing)return error==other.error;
        return device==other.device&&inode==other.inode&&size==other.size&&
            modifiedSeconds==other.modifiedSeconds&&modifiedNanos==other.modifiedNanos&&
            changedSeconds==other.changedSeconds&&changedNanos==other.changedNanos;
    }
    bool operator!=(const Stamp &other)const{return !(*this==other);}
};
struct PermissionPlan {
    bool mode,owner;
    PermissionPlan(std::uint64_t actualMode,std::uint64_t uid,std::uint64_t gid,
                   std::uint64_t wantedMode,std::uint64_t wantedUid,std::uint64_t wantedGid)
        :mode((actualMode&07777)!=wantedMode),owner(uid!=wantedUid||gid!=wantedGid){}
};
template<class Unit>
bool TopicValid(std::size_t length,Unit unit){
    if(!length||length>64)return false;
    if(length==1&&unit(0)=='*')return true;
    for(std::size_t i=0;i<length;++i)if(!TLinkASCIIPreparation::Allowed(unit(i),true))return false;
    return true;
}
}
