#ifndef TLINK_HELPER_RPC_REPLAY_H
#define TLINK_HELPER_RPC_REPLAY_H
#include <array>
#include <cstdint>
#include <cstddef>
#include <string>
#include <unordered_map>
#include <deque>
#include <utility>

// Session-owner only. Retired IDs stay in the bounded ledger until clear().
class TLinkHelperRPCReplay {
public:
    using Digest=std::array<uint8_t,32>;
    enum class Decision { Execute, Replay, Collision, Unavailable, Capacity, Invalid, InFlight };
    struct Limits {
        size_t replies=256,bytes=4*1024*1024,replyBytes=1024*1024;
        size_t identities=8192,identityBytes=1024*1024;
    };
    struct Lookup {Decision decision;const std::string *reply;};
private:
    struct Entry {std::string method;Digest digest;std::string reply;bool pending=true;};
    Limits limits_;std::unordered_map<std::string,Entry> entries_;std::deque<std::string> order_;
    size_t bytes_=0,identityBytes_=0;
public:
    TLinkHelperRPCReplay()=default;
    explicit TLinkHelperRPCReplay(Limits limits):limits_(limits){}
    Lookup begin(const std::string &id,const std::string &method,const Digest &digest){
        if(id.empty()||id.size()>64||method.empty()||method.size()>128)return {Decision::Invalid,nullptr};
        const auto found=entries_.find(id);
        if(found!=entries_.end()){
            const Entry &entry=found->second;
            if(entry.method!=method||entry.digest!=digest)return {Decision::Collision,nullptr};
            if(entry.pending)return {Decision::InFlight,nullptr};
            return entry.reply.empty()?Lookup{Decision::Unavailable,nullptr}:Lookup{Decision::Replay,&entry.reply};
        }
        const size_t charge=id.size()+method.size()+digest.size();
        if(entries_.size()>=limits_.identities||charge>limits_.identityBytes-identityBytes_)return {Decision::Capacity,nullptr};
        entries_.emplace(id,Entry{method,digest,{},true});identityBytes_+=charge;
        return {Decision::Execute,nullptr};
    }
    bool finish(const std::string &id,std::string reply){
        auto found=entries_.find(id);
        if(found==entries_.end()||!found->second.pending)return false;
        Entry &entry=found->second;entry.pending=false;
        if(reply.empty()||reply.size()>limits_.replyBytes||reply.size()>limits_.bytes||!limits_.replies)return false;
        while(!order_.empty()&&(order_.size()>=limits_.replies||reply.size()>limits_.bytes-bytes_)){
            Entry &old=entries_.at(order_.front());bytes_-=old.reply.size();std::string().swap(old.reply);order_.pop_front();
        }
        order_.push_back(id);bytes_+=reply.size();entry.reply=std::move(reply);return true;
    }
    void clear(){entries_.clear();order_.clear();bytes_=0;identityBytes_=0;}
    size_t bytes()const{return bytes_;}
    size_t replies()const{return order_.size();}
    size_t identities()const{return entries_.size();}
    size_t identityBytes()const{return identityBytes_;}
};

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
static inline NSDictionary *TLinkHelperRPCError(NSString *message){return @{@"ok":@(false),@"error":message};}
// Keep JSON number/string semantics, sort object keys, and retain only a 32-byte digest.
// The bounded transport still supplies the argument object and this temporary JSON buffer.
static inline bool TLinkHelperRPCFingerprint(NSArray *arguments,TLinkHelperRPCReplay::Digest &digest){
    NSData *json=[NSJSONSerialization dataWithJSONObject:arguments options:NSJSONWritingSortedKeys error:nil];
    if(!json||json.length>1024*1024)return false;
    return CC_SHA256(json.bytes,(CC_LONG)json.length,digest.data())!=nullptr;
}
static inline NSDictionary *TLinkHelperRPCDispatch(TLinkHelperRPCReplay &cache,NSString *requestId,NSString *method,
                                                   NSArray *arguments,NSDictionary *(^execute)(void),
                                                   TLinkHelperRPCReplay::Decision &decision){
    @autoreleasepool {
        decision=TLinkHelperRPCReplay::Decision::Invalid;
        if(![requestId isKindOfClass:[NSString class]]||requestId.length==0||requestId.length>64||
           ![method isKindOfClass:[NSString class]]||method.length==0||method.length>128||
           ![arguments isKindOfClass:[NSArray class]])return TLinkHelperRPCError(@"invalid native RPC identity or arguments");
        TLinkHelperRPCReplay::Digest digest;
        @try {
            if(!TLinkHelperRPCFingerprint(arguments,digest))return TLinkHelperRPCError(@"invalid native RPC arguments");
        } @catch(NSException *exception) {(void)exception;return TLinkHelperRPCError(@"invalid native RPC arguments");}
        const char *idBytes=requestId.UTF8String,*methodBytes=method.UTF8String;
        // Explicit lengths preserve embedded NUL instead of aliasing another identity.
        NSData *idData=[requestId dataUsingEncoding:NSUTF8StringEncoding],*methodData=[method dataUsingEncoding:NSUTF8StringEncoding];
        if(!idBytes||!methodBytes||!idData||!methodData)return TLinkHelperRPCError(@"invalid native RPC identity or arguments");
        std::string idKey(idBytes,idData.length),methodKey(methodBytes,methodData.length);
        const auto lookup=cache.begin(idKey,methodKey,digest);decision=lookup.decision;
        using D=TLinkHelperRPCReplay::Decision;
        switch(decision){
            case D::Collision:return @{@"ok":@(false),@"error":@"duplicate native RPC requestId collision",@"requestId":requestId};
            case D::Unavailable:return TLinkHelperRPCError(@"native RPC replay unavailable; request already handled");
            case D::InFlight:return TLinkHelperRPCError(@"native RPC request already in flight");
            case D::Capacity:return TLinkHelperRPCError(@"native RPC session identity limit reached");
            case D::Invalid:return TLinkHelperRPCError(@"invalid native RPC identity or arguments");
            case D::Replay:{
                NSData *data=[NSData dataWithBytes:lookup.reply->data() length:lookup.reply->size()];
                return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            }
            case D::Execute:break;
        }
        // Reserve identity before policy/native execution; faults never permit a second effect.
        NSDictionary *result=nil;NSData *json=nil;
        try {
            @try {
                result=execute();
                if(![result isKindOfClass:[NSDictionary class]])result=TLinkHelperRPCError(@"invalid native RPC result");
                json=[NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
                if(!json||json.length>1024*1024){result=TLinkHelperRPCError(@"native RPC result exceeds replay limit or is invalid");json=nil;}
            } @catch(NSException *exception) {(void)exception;result=TLinkHelperRPCError(@"native RPC execution exception");json=nil;}
        } catch(...) {result=TLinkHelperRPCError(@"native RPC execution exception");json=nil;}
        if(!json)json=[NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
        cache.finish(idKey,std::string(static_cast<const char *>(json.bytes),json.length));
        return result;
    }
}
#endif
#endif
