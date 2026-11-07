#define read(fd,bytes,count) TLinkUnexpectedReadMacro(fd,bytes,count)
#define write(fd,bytes,count) TLinkUnexpectedWriteMacro(fd,bytes,count)
#include "../shared/TLinkJSFileIO.h"
#undef write
#undef read
#include <random>
static void payloadCases(){
    using namespace TLinkJSFileIO;
    std::mt19937 random(42);
    for(unsigned n=0;n<10000;++n){
        Source before;before.bytes=std::string(random()%2000,'x');before.maxRead=1+random()%127;before.interrupts=random()%4;
        const size_t limit=random()%2100;Source after=before;std::vector<uint8_t> output;size_t peak=0;unsigned grows=0;
        const auto result=ReadInto(limit,[&](size_t used,size_t amount){assert(amount<=8192&&used<=limit&&amount<=limit-used);output.resize(used+amount);peak=std::max(peak,output.size());++grows;return output.data()+used;},[&](uint8_t *bytes,size_t amount){return after.read(bytes,amount);});
        size_t expected=0;bool eof=false;std::string bytes;
        while(expected<limit){uint8_t chunk[8192];const int64_t got=before.read(chunk,std::min(size_t(8192),limit-expected));if(got<0){assert(errno==EINTR);continue;}if(!got){eof=true;break;}bytes.append(reinterpret_cast<char *>(chunk),size_t(got));expected+=size_t(got);}
        output.resize(result.bytes);
        assert(!result.error&&result.eof==eof&&result.bytes==expected&&std::string(output.begin(),output.end())==bytes&&after.offset==before.offset&&after.reads==before.reads&&peak<=limit);
        assert(grows==after.reads);
    }
    for(size_t fault:{size_t(0),size_t(5),size_t(8192)}){
        Source source;source.bytes=std::string(20000,'x');source.fault=fault;source.interrupts=3;std::vector<uint8_t> output;
        const auto result=ReadInto(20000,[&](size_t used,size_t amount){output.resize(used+amount);return output.data()+used;},[&](uint8_t *bytes,size_t amount){return source.read(bytes,amount);});
        assert(result.error==EIO&&result.bytes==fault&&source.offset==fault);
    }
    for(size_t length:{size_t(512*1024-1),size_t(512*1024)}){
        Source source;source.bytes=std::string(length,'z');std::vector<uint8_t> output;
        const auto large=ReadInto(512*1024,[&](size_t used,size_t amount){output.resize(used+amount);return output.data()+used;},[&](uint8_t *bytes,size_t amount){return source.read(bytes,amount);});
        output.resize(large.bytes);assert(!large.error&&large.bytes==length&&large.eof==(length<512*1024)&&source.reads==(length<512*1024?65U:64U)&&std::string(output.begin(),output.end())==source.bytes);
    }
    unsigned reads=0;
    auto result=ReadInto(SIZE_MAX,[](size_t used,size_t amount)->uint8_t *{assert(used==0&&amount==8192);return nullptr;},[&](uint8_t *,size_t)->int64_t{++reads;return 0;});
    assert(result.error==ENOMEM&&reads==0);
    std::vector<uint8_t> buffer(8192);
    result=ReadInto(8,[&](size_t,size_t){return buffer.data();},[](uint8_t *,size_t amount)->int64_t{return int64_t(amount+1);});assert(result.error==EIO&&result.bytes==0);
    bool caught=false;
    try{ReadInto(8,[](size_t,size_t)->uint8_t *{throw std::runtime_error("grow");},[&](uint8_t *,size_t)->int64_t{++reads;return 0;});}catch(const std::runtime_error &){caught=true;}
    assert(caught&&reads==0);
    const std::string input(8192,'y');
    for(unsigned n=0;n<10000;++n){
        std::string written;unsigned interrupts=random()%4;size_t chunk=1+random()%127,fault=random()%2?SIZE_MAX:random()%input.size();
        const auto output=WriteAll(reinterpret_cast<const uint8_t *>(input.data()),input.size(),[&](const uint8_t *bytes,size_t amount)->int64_t{
            if(interrupts){--interrupts;errno=EINTR;return -1;}if(written.size()==fault){errno=EIO;return -1;}
            size_t count=std::min(std::min(amount,chunk),fault-written.size());written.append(reinterpret_cast<const char *>(bytes),count);return int64_t(count);
        });
        assert(written==input.substr(0,written.size())&&output.bytes==written.size()&&!output.zeroWrite);
        assert(output.error==(fault<input.size()?EIO:0));
    }
    result=WriteAll(reinterpret_cast<const uint8_t *>(input.data()),input.size(),[](const uint8_t *,size_t)->int64_t{return 0;});assert(result.zeroWrite&&!result.error&&!result.bytes);
    result=WriteAll(reinterpret_cast<const uint8_t *>(input.data()),input.size(),[](const uint8_t *,size_t amount)->int64_t{return int64_t(amount+1);});assert(result.error==EIO&&!result.bytes);
    result=WriteAll(nullptr,1,[](const uint8_t *,size_t)->int64_t{assert(false);return 0;});assert(result.error==EFAULT);
    result=WriteAll(nullptr,0,[](const uint8_t *,size_t)->int64_t{assert(false);return 0;});assert(!result.error&&!result.bytes);
    puts("File payload core passed: 10k frozen direct-fill reads, EOF/limit/partial/EINTR/ENOMEM/overreturn/grow faults and 10k exact partial-write/interrupt/fault cases without staging copies.");
}
