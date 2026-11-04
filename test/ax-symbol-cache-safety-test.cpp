#include "../shared/TLinkAXSymbolCache.h"
#include <cassert>
#include <cstdio>
#include <cstring>
#include <functional>
#include <stdexcept>
#include <thread>
#include <vector>
using TLinkAXSymbols::Cache;
using TLinkAXSymbols::Snapshot;
struct Loader {
    int handle=0,first=0,second=0;
    std::atomic<unsigned> opens{0},firstLookups{0},secondLookups{0},closes{0},references{0};
    std::atomic<bool> openReady{true},firstReady{true},secondReady{true};
    void *open(const char *path){assert(!std::strcmp(path,"fixture"));++opens;if(!openReady)return nullptr;++references;return &handle;}
    void *lookup(void *value,const char *name){
        assert(value==&handle);
        if(!std::strcmp(name,"first")){++firstLookups;return firstReady?&first:nullptr;}
        assert(!std::strcmp(name,"second"));++secondLookups;return secondReady?&second:nullptr;
    }
    void close(void *value){assert(value==&handle);++closes;assert(references.fetch_sub(1)>1);}
    Snapshot load(Cache &cache){return cache.load([this](const char *p){return open(p);},[this](void *h,const char *n){return lookup(h,n);},[this](void *h){close(h);});}
    void check(Snapshot value){assert(value.handle==&handle&&value.first==&first&&value.second==&second);}
};
static void warmAndRetryCases(){
    Loader io;Cache cache("fixture","first","second");
    io.openReady=false;
    for(unsigned n=0;n<3;++n){Snapshot value=io.load(cache);assert(!value.handle&&!value.first&&!value.second);}
    assert(io.opens==3&&io.references==0&&io.firstLookups==0&&io.secondLookups==0);
    io.openReady=true;io.secondReady=false;
    for(unsigned n=0;n<3;++n){Snapshot value=io.load(cache);assert(value.handle==&io.handle&&value.first==&io.first&&!value.second);}
    assert(io.opens==4&&io.firstLookups==1&&io.secondLookups==3&&io.references==1);
    io.secondReady=true;io.check(io.load(cache));
    // Successful symbols/handle stay pinned even if a later provider would fail.
    io.openReady=io.firstReady=io.secondReady=false;
    for(unsigned n=0;n<100000;++n)io.check(io.load(cache));
    assert(io.opens==4&&io.firstLookups==1&&io.secondLookups==4&&io.closes==0&&io.references==1);
    Loader other;Cache isolated("fixture","first","second");other.check(other.load(isolated));assert(other.opens==1);
}
static void concurrentCases(){
    for(unsigned cycle=0;cycle<64;++cycle){
        Loader io;Cache cache("fixture","first","second");std::atomic<unsigned> entered{0};std::vector<std::thread> threads;
        for(unsigned worker=0;worker<8;++worker)threads.emplace_back([&]{
            Snapshot value=cache.load([&](const char *path){
                void *handle=io.open(path);++entered;
                while(entered.load()<8)std::this_thread::yield();return handle;
            },[&](void *h,const char *n){return io.lookup(h,n);},[&](void *h){io.close(h);});
            io.check(value);
            for(unsigned n=0;n<1250;++n)io.check(io.load(cache));
        });
        for(auto &thread:threads)thread.join();
        assert(io.opens==8&&io.closes==7&&io.references==1);
        assert(io.firstLookups>=1&&io.firstLookups<=8&&io.secondLookups>=1&&io.secondLookups<=8);
    }
}
static void lateFailureCases(){
    Loader io;Cache cache("fixture","first","second");std::atomic<bool> waiting{false},release{false};Snapshot late{};
    std::thread thread([&]{late=cache.load([&](const char *p){return io.open(p);},[&](void *h,const char *n)->void *{
        if(!std::strcmp(n,"first")){waiting=true;while(!release.load())std::this_thread::yield();return nullptr;}
        return io.lookup(h,n);
    },[&](void *h){io.close(h);});});
    while(!waiting.load())std::this_thread::yield();
    io.check(io.load(cache));release=true;thread.join();io.check(late);
    assert(io.opens==1&&io.references==1&&io.closes==0);
}
static void reentryAndUnwindCases(){
    Loader io;Cache cache("fixture","first","second");bool nested=false;
    std::function<void *(const char *)> open=[&](const char *path)->void *{
        void *handle=io.open(path);
        if(!nested){nested=true;io.check(cache.load(open,[&](void *h,const char *n){return io.lookup(h,n);},[&](void *h){io.close(h);}));}
        return handle;
    };
    io.check(cache.load(open,[&](void *h,const char *n){return io.lookup(h,n);},[&](void *h){io.close(h);}));
    assert(io.opens==2&&io.closes==1&&io.references==1);
    Loader failed;Cache retry("fixture","first","second");bool caught=false;
    try{retry.load([&](const char *p){return failed.open(p);},[](void *,const char *)->void *{throw std::runtime_error("lookup");},[&](void *h){failed.close(h);});}
    catch(const std::runtime_error &){caught=true;}
    assert(caught&&failed.references==1);failed.check(failed.load(retry));assert(failed.opens==1);
}
static void borrowedSymbolCases(){
    Loader io;TLinkAXSymbols::Symbol symbol("first");
    const auto lookup=[&](void *handle,const char *name){return io.lookup(handle,name);};
    assert(!symbol.load(nullptr,lookup)&&io.firstLookups==0);
    io.firstReady=false;
    for(unsigned n=0;n<3;++n)assert(!symbol.load(&io.handle,lookup));
    io.firstReady=true;assert(symbol.load(&io.handle,lookup)==&io.first);
    io.firstReady=false;
    for(unsigned n=0;n<100000;++n)assert(symbol.load(&io.handle,lookup)==&io.first);
    assert(io.firstLookups==4&&io.opens==0&&io.closes==0&&io.references==0);
    Loader other;TLinkAXSymbols::Symbol isolated("first");
    assert(isolated.load(&other.handle,[&](void *handle,const char *name){return other.lookup(handle,name);})==&other.first);
    for(unsigned cycle=0;cycle<32;++cycle){
        Loader race;TLinkAXSymbols::Symbol shared("first");std::atomic<unsigned> entered{0};std::vector<std::thread> threads;
        for(unsigned worker=0;worker<8;++worker)threads.emplace_back([&]{
            void *value=shared.load(&race.handle,[&](void *handle,const char *name){
                ++entered;while(entered.load()<8)std::this_thread::yield();return race.lookup(handle,name);
            });
            assert(value==&race.first);
            for(unsigned n=0;n<1250;++n)assert(shared.load(&race.handle,[&](void *handle,const char *name){return race.lookup(handle,name);})==&race.first);
        });
        for(auto &thread:threads)thread.join();
        assert(race.firstLookups==8&&race.opens==0&&race.closes==0);
    }
    TLinkAXSymbols::Symbol late("first");std::atomic<bool> waiting{false},release{false};void *lateResult=nullptr;
    std::thread pending([&]{lateResult=late.load(&io.handle,[&](void *,const char *)->void *{
        waiting=true;while(!release.load())std::this_thread::yield();return nullptr;
    });});
    while(!waiting.load())std::this_thread::yield();
    io.firstReady=true;
    assert(late.load(&io.handle,lookup)==&io.first);release=true;pending.join();assert(lateResult==&io.first);
    TLinkAXSymbols::Symbol reentrant("first");bool nested=false;
    std::function<void *(void *,const char *)> recurse=[&](void *handle,const char *name)->void *{
        if(!nested){nested=true;assert(reentrant.load(handle,recurse)==&io.first);return nullptr;}
        return io.lookup(handle,name);
    };
    assert(reentrant.load(&io.handle,recurse)==&io.first);
    TLinkAXSymbols::Symbol failed("first");bool caught=false;
    try{failed.load(&io.handle,[](void *,const char *)->void *{throw std::runtime_error("lookup");});}
    catch(const std::runtime_error &){caught=true;}
    assert(caught&&failed.load(&io.handle,lookup)==&io.first);
}
static void deferredSecondCases(){
    Loader io;Cache cache("fixture","first","second");io.secondReady=false;
    const auto lookup=[&](void *h,const char *n){return io.lookup(h,n);};
    const auto firstOnly=[&]{return cache.load([&](const char *p){return io.open(p);},lookup,[&](void *h){io.close(h);},false);};
    assert(!cache.loadSecond(lookup)&&io.opens==0&&io.secondLookups==0);
    for(unsigned n=0;n<100000;++n){Snapshot value=firstOnly();assert(value.handle==&io.handle&&value.first==&io.first&&!value.second);}
    assert(io.opens==1&&io.firstLookups==1&&io.secondLookups==0&&io.references==1);
    for(unsigned n=0;n<3;++n)assert(!cache.loadSecond(lookup));
    io.secondReady=true;assert(cache.loadSecond(lookup)==&io.second);io.secondReady=false;
    for(unsigned n=0;n<100000;++n)assert(cache.loadSecond(lookup)==&io.second);
    assert(io.secondLookups==4&&io.opens==1&&io.references==1&&io.closes==0);io.check(io.load(cache));
    Loader missing;Cache partial("fixture","first","second");missing.firstReady=false;
    Snapshot value=partial.load([&](const char *p){return missing.open(p);},[&](void *h,const char *n){return missing.lookup(h,n);},[&](void *h){missing.close(h);},false);
    assert(!value.first&&!value.second&&partial.loadSecond([&](void *h,const char *n){return missing.lookup(h,n);})==&missing.second);
    for(unsigned cycle=0;cycle<32;++cycle){
        Loader race;Cache shared("fixture","first","second");
        shared.load([&](const char *p){return race.open(p);},[&](void *h,const char *n){return race.lookup(h,n);},[&](void *h){race.close(h);},false);
        std::atomic<unsigned> entered{0};std::vector<std::thread> threads;
        for(unsigned worker=0;worker<8;++worker)threads.emplace_back([&]{
            void *symbol=shared.loadSecond([&](void *h,const char *n){
                ++entered;while(entered.load()<8)std::this_thread::yield();return race.lookup(h,n);
            });
            assert(symbol==&race.second);
        });
        for(auto &thread:threads)thread.join();
        assert(race.opens==1&&race.firstLookups==1&&race.secondLookups==8&&race.closes==0&&race.references==1);
    }
    Loader lateIO;Cache late("fixture","first","second");
    late.load([&](const char *p){return lateIO.open(p);},[&](void *h,const char *n){return lateIO.lookup(h,n);},[&](void *h){lateIO.close(h);},false);
    std::atomic<bool> waiting{false},release{false};void *lateResult=nullptr;
    std::thread pending([&]{lateResult=late.loadSecond([&](void *,const char *)->void *{
        waiting=true;while(!release.load())std::this_thread::yield();return nullptr;
    });});
    while(!waiting.load())std::this_thread::yield();
    assert(late.loadSecond([&](void *h,const char *n){return lateIO.lookup(h,n);})==&lateIO.second);
    release=true;pending.join();assert(lateResult==&lateIO.second);
    Loader unwind;Cache recover("fixture","first","second");
    recover.load([&](const char *p){return unwind.open(p);},[&](void *h,const char *n){return unwind.lookup(h,n);},[&](void *h){unwind.close(h);},false);
    bool caught=false;
    try{recover.loadSecond([](void *,const char *)->void *{throw std::runtime_error("second");});}catch(const std::runtime_error &){caught=true;}
    assert(caught&&recover.loadSecond([&](void *h,const char *n){return unwind.lookup(h,n);})==&unwind.second&&unwind.opens==1);
}
int main(){warmAndRetryCases();concurrentCases();lateFailureCases();reentryAndUnwindCases();borrowedSymbolCases();deferredSecondCases();
    std::puts("AX deferred lookup passed: 100k first-only reads without secondary lookup, 100k cached secondary reads, pre-load refusal, missing/recovery, 32 x 8 deferred races, late failed publication and exception recovery with one pinned handle.");
    std::puts("AX symbol cache passed: 100k warm calls, retry/partial discovery, 64 x 8 cold races and 640k warm concurrent calls, one pinned reference/loser closes, stale failure, isolation, reentry and lookup unwind; borrowed symbols add 100k warm reads, 32 x 8 cold races/320k warm concurrent reads, no opens/closes, null/missing/retry, late failure and unwind.");}
