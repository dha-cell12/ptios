#include "../shared/TLinkCaptureLease.h"
#include <cassert>
#include <cstdio>
#include <map>
#include <functional>
struct File {TLinkCaptureFileID id;bool marker=false;std::vector<uint8_t> bytes;};
struct FakeIO {
    static std::map<std::string,std::shared_ptr<File>> files;
    static std::map<int,std::shared_ptr<File>> handles;
    static uint64_t inode;static int nextFD;static unsigned calls;
    static bool interrupt,failWrite,zeroWrite,failClose;
    static size_t partial;static std::function<void()> hook;
    static std::shared_ptr<File> file(bool marker){auto value=std::make_shared<File>();value->id.device=1;value->id.inode=++inode;value->marker=marker;return value;}
    static bool absent(const std::string &path){return files.count(path)==0;}
    static bool createMarker(const std::string &path,TLinkCaptureFileID &id){if(files.count(path))return false;auto value=file(true);files[path]=value;id=value->id;return true;}
    static bool marker(const std::string &path,TLinkCaptureFileID &id){auto it=files.find(path);if(it==files.end()||!it->second->marker)return false;id=it->second->id;return true;}
    static bool sameMarker(const std::string &path,TLinkCaptureFileID id){TLinkCaptureFileID current;return marker(path,current)&&TLinkCaptureSameID(id,current);}
    static void removeMarker(const std::string &path,TLinkCaptureFileID id){if(sameMarker(path,id))files.erase(path);}
    static void removePrivateOutput(const std::string &path){assert(TLinkCaptureLeasePath(path));files.erase(path);}
    static void removeOutput(const std::string &path,TLinkCaptureFileID id){auto it=files.find(path);if(it!=files.end()&&TLinkCaptureSameID(it->second->id,id))files.erase(it);}
    static int createOutput(const std::string &path,TLinkCaptureFileID &id){if(files.count(path))return -1;auto value=file(false);files[path]=value;id=value->id;int fd=++nextFD;handles[fd]=value;return fd;}
    static int64_t write(int fd,const uint8_t *data,size_t count){
        ++calls;if(hook){auto value=std::move(hook);hook={};value();}
        if(interrupt){interrupt=false;return -1;}if(failWrite)return -1;if(zeroWrite)return 0;
        auto value=handles.at(fd);const size_t size=std::min(count,partial);value->bytes.insert(value->bytes.end(),data,data+size);return int64_t(size);
    }
    static bool interrupted(){return !failWrite;}
    static bool close(int fd){assert(handles.erase(fd)==1);return !failClose;}
    static void reset(){assert(handles.empty());files.clear();interrupt=failWrite=zeroWrite=failClose=false;partial=65536;hook={};calls=0;}
};
std::map<std::string,std::shared_ptr<File>> FakeIO::files;std::map<int,std::shared_ptr<File>> FakeIO::handles;
uint64_t FakeIO::inode=0;int FakeIO::nextFD=0;unsigned FakeIO::calls=0;
bool FakeIO::interrupt=false,FakeIO::failWrite=false,FakeIO::zeroWrite=false,FakeIO::failClose=false;
size_t FakeIO::partial=65536;std::function<void()> FakeIO::hook;
using Client=TLinkCaptureClient<FakeIO>;using Receiver=TLinkCaptureReceiver<FakeIO>;
static const std::string capturePath="/tmp/tlinkautod_capture_12345678-1234-ABCD-abcd-1234567890ab.png";
static void empty(){assert(FakeIO::files.empty()&&FakeIO::handles.empty());}
int main(){
    assert(TLinkCaptureLeasePath(capturePath));
    for(const auto &bad:{capturePath+"/x",capturePath+".lease",std::string("/tmp/tlinkautod_capture_../other.png"),std::string("/var/tmp/tlinkautod_capture_12345678-1234-ABCD-abcd-1234567890ab.png")})assert(!TLinkCaptureLeasePath(bad));
    std::vector<uint8_t> data(130001,71);
    {Client client(capturePath);assert(client.valid());{Receiver receiver(capturePath,{});assert(receiver.valid());FakeIO::partial=17;FakeIO::interrupt=true;assert(receiver.write(data.data(),data.size()));receiver.finish();assert(FakeIO::files.at(capturePath)->bytes==data);assert(!receiver.write(data.data(),data.size()));}assert(FakeIO::files.count(capturePath));}empty();FakeIO::reset();
    for(unsigned fault=0;fault<5;++fault){
        {Client client(capturePath);Receiver receiver(capturePath,{});assert(receiver.valid());
            if(fault==0)client.cancel();if(fault==1)FakeIO::failWrite=true;if(fault==2)FakeIO::zeroWrite=true;if(fault==3)FakeIO::failClose=true;
            if(fault==4)FakeIO::hook=[&]{client.cancel();};
            assert(!receiver.write(data.data(),data.size()));receiver.finish();assert(FakeIO::handles.empty());
        }empty();FakeIO::reset();
    }
    {Client client(capturePath);Receiver receiver(capturePath,{});assert(!receiver.write(data.data(),32*1024*1024+1)&&FakeIO::handles.empty());}empty();
    {Client client(capturePath);Receiver receiver(capturePath,{});assert(receiver.write(data.data(),data.size()));client.cancel();FakeIO::files[capturePath]=FakeIO::file(false);receiver.finish();assert(FakeIO::files.count(capturePath));}FakeIO::reset();
    FakeIO::files[capturePath]=FakeIO::file(false);{Client client(capturePath);assert(!client.valid());}assert(FakeIO::files.count(capturePath));FakeIO::reset();
    {Client client(capturePath);Receiver receiver(capturePath,{});FakeIO::files[capturePath+".lease"]=FakeIO::file(true);assert(!receiver.valid()&&!receiver.write(data.data(),data.size()));}assert(FakeIO::files.count(capturePath+".lease"));FakeIO::reset();
    {Client client(capturePath);auto token=std::make_shared<TLinkNativeCancellation>();auto budget=std::make_shared<TLinkNativeBudget>(token,0,1024);Receiver receiver(capturePath,budget);
        FakeIO::hook=[&]{token->cancel();};assert(!receiver.write(data.data(),data.size()));assert(!FakeIO::files.count(capturePath));}empty();FakeIO::reset();
    {Client client(capturePath);auto budget=std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},TLinkNativeDeadline(.01),1024);Receiver receiver(capturePath,budget);
        FakeIO::hook=[]{std::this_thread::sleep_for(std::chrono::milliseconds(20));};assert(!receiver.write(data.data(),data.size()));}empty();FakeIO::reset();
    const uint8_t tiny[8]={1,2,3,4,5,6,7,8};
    for(unsigned n=0;n<100000;++n){
        {Client client(capturePath);Receiver receiver(capturePath,{});
            switch(n%4){case 0:client.cancel();assert(!receiver.write(tiny,sizeof(tiny)));break;
                case 1:FakeIO::hook=[&]{client.cancel();};assert(!receiver.write(tiny,sizeof(tiny)));break;
                case 2:assert(receiver.write(tiny,sizeof(tiny)));client.cancel();receiver.finish();break;
                default:assert(receiver.write(tiny,sizeof(tiny)));break;}
        }empty();
    }
    puts("Capture lease passed: 100k cancel/commit lifecycles, partial/EINTR/error/close writes, deadlines, bounded output, identity and path ownership; zero live handles/files.");
}
