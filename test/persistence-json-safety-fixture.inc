#include "../shared/TLinkPersistenceJSONQuota.h"
#include <limits>
static void persistenceJSONQuotaCases(){
    const size_t maximum=std::numeric_limits<size_t>::max();
    const size_t caps[]={0,1,4U*1024U*1024U,32U*1024U*1024U,maximum};
    for(size_t cap:caps){
        TLinkPersistenceJSONQuota quota(cap);assert(quota.append(0));
        assert(quota.append(cap)&&quota.size()==cap);
        assert(!quota.append(1)&&quota.failed()&&quota.size()==cap);
        assert(!quota.append(0)&&!quota.append(maximum)&&quota.size()==cap);
    }
    uint64_t state=12345;
    for(unsigned n=0;n<100000;++n){
        state=state*6364136223846793005ULL+1;const size_t cap=(size_t)(state%65537);
        TLinkPersistenceJSONQuota quota(cap);size_t used=0;bool failed=false;
        for(unsigned chunk=0;chunk<16;++chunk){
            state=state*6364136223846793005ULL+1;const size_t bytes=(size_t)(state%8193);
            const bool accepted=!failed&&bytes<=cap-used;
            if(accepted)used+=bytes;else failed=true;
            assert(quota.append(bytes)==accepted&&quota.size()==used&&quota.failed()==failed&&used<=cap);
        }
        quota.fail();assert(!quota.append(0)&&quota.size()==used);
    }
    puts("Persistence JSON quota passed: 100k chunk/oracle lifecycles, exact zero/4-MiB/32-MiB/SIZE_MAX limits, sticky refusal and unchanged accepted bytes.");
}
