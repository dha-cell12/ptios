#include "../shared/TLinkJSFileOpen.h"
#include <set>
#include <type_traits>
static void fileOpenOwnerCases(){
    static_assert(!std::is_copy_constructible<TLinkJSFileOpenOwner>::value,"one open owner");
    static_assert(!std::is_copy_assignable<TLinkJSFileOpenOwner>::value,"one open owner");
    for(unsigned n=0;n<100000;++n){
        const int fd=int(n%32);std::set<int> live{fd};unsigned closes=0;
        TLinkJSFileOpenOwner pending(fd);assert(pending.held());
        auto closeDescriptor=[&](int value){assert(value==fd&&live.erase(value)==1);++closes;};
        if(n%3==0){
            const int transferred=pending.release();assert(transferred==fd&&!pending.held()&&pending.release()==-1);
            pending.retire([&](int){assert(false);});closeDescriptor(transferred);
        }else if(n%3==1){
            pending.retire([&](int value){assert(!pending.held());pending.retire([&](int){assert(false);});closeDescriptor(value);});
        }else{
            bool caught=false;try{pending.retire([&](int value){closeDescriptor(value);throw std::runtime_error("after-close");});}catch(const std::runtime_error &){caught=true;}
            assert(caught&&!pending.held());
        }
        pending.retire([&](int){assert(false);});assert(!pending.held()&&closes==1&&live.empty());
    }
    TLinkJSFileOpenOwner absent(-1);absent.retire([](int){assert(false);});assert(!absent.held());
    puts("File open owner passed: 100k pending/transfer/retire lifecycles, descriptor zero/reuse, clear-before-close, reentry, after-close throw and no duplicate close or final live descriptor.");
}
