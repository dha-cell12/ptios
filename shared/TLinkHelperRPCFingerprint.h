#ifndef TLINK_HELPER_RPC_FINGERPRINT_H
#define TLINK_HELPER_RPC_FINGERPRINT_H
#include <array>
#include <cstddef>
#include <cstdint>
using TLinkHelperRPCFingerprintDigest=std::array<uint8_t,32>;
struct TLinkHelperRPCFingerprintStats {size_t bytes=0,writes=0,updates=0;bool failed=false;};
// A synchronous, non-owning feed. Never stores the input or allocates payload buffers.
class TLinkHelperRPCDigestFeed {
    TLinkHelperRPCFingerprintStats stats_;bool closed_=false;
public:
    static constexpr size_t MaxBytes=1024*1024;
    static constexpr size_t ChunkBytes=4096;
    using Update=bool (*)(void *,const uint8_t *,size_t);
    bool append(const uint8_t *bytes,size_t length,Update update,void *context){
        if(closed_||stats_.failed)return false;
        ++stats_.writes;
        if((!bytes&&length)||!update||length>MaxBytes-stats_.bytes){stats_.failed=true;return false;}
        while(length){
            const size_t chunk=length<ChunkBytes?length:ChunkBytes;
            if(!update(context,bytes,chunk)){stats_.failed=true;return false;}
            ++stats_.updates;stats_.bytes+=chunk;bytes+=chunk;length-=chunk;
        }
        return true;
    }
    bool finish(){if(closed_||stats_.failed)return false;closed_=true;return stats_.bytes!=0;}
    TLinkHelperRPCFingerprintStats stats()const{return stats_;}
};
#ifdef __OBJC__
#import <Foundation/Foundation.h>
// Stats are optional and describe this sink, not Foundation's internal allocations.
bool TLinkHelperRPCFingerprint(NSArray *arguments,TLinkHelperRPCFingerprintDigest &digest,
                              TLinkHelperRPCFingerprintStats *stats=nullptr);
#endif
#endif
