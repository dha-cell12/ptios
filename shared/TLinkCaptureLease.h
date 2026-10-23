#ifndef TLINK_CAPTURE_LEASE_H
#define TLINK_CAPTURE_LEASE_H
#include "TLinkNativeBudget.h"
#include <string>
static const int kTLinkOwnedCaptureAction=4;
inline bool TLinkCaptureLeasePath(const std::string &path) {
    const std::string prefix="/tmp/tlinkautod_capture_",suffix=".png";
    if(path.size()!=prefix.size()+36+suffix.size()||path.compare(0,prefix.size(),prefix)!=0||path.compare(path.size()-4,4,suffix)!=0)return false;
    for(size_t i=0;i<36;++i){const char c=path[prefix.size()+i];
        if(i==8||i==13||i==18||i==23){if(c!='-')return false;}
        else if(!((c>='0'&&c<='9')||(c>='a'&&c<='f')||(c>='A'&&c<='F')))return false;
    }return true;
}
struct TLinkCaptureFileID {uint64_t device=0,inode=0;};
inline bool TLinkCaptureSameID(TLinkCaptureFileID a,TLinkCaptureFileID b){return a.device==b.device&&a.inode==b.inode;}
// IO operations are nonrecursive, bounded path/descriptor operations. Production
// uses POSIX; the portable race/fault harness supplies the same ownership boundary.
template<class IO> class TLinkCaptureClient {
    std::string path_,marker_;TLinkCaptureFileID identity_;bool active_=false;
public:
    explicit TLinkCaptureClient(std::string path):path_(std::move(path)),marker_(path_+".lease") {
        active_=TLinkCaptureLeasePath(path_)&&IO::absent(path_)&&IO::createMarker(marker_,identity_);
    }
    bool valid()const{return active_;}
    void cancel(){
        if(!active_)return;active_=false;
        if(IO::sameMarker(marker_,identity_)){IO::removeMarker(marker_,identity_);IO::removePrivateOutput(path_);}
    }
    ~TLinkCaptureClient(){cancel();}
    TLinkCaptureClient(const TLinkCaptureClient &)=delete;TLinkCaptureClient &operator=(const TLinkCaptureClient &)=delete;
};
template<class IO> class TLinkCaptureReceiver {
    std::string path_,marker_;TLinkCaptureFileID markerID_,outputID_;
    TLinkNativeBudgetPtr budget_;int fd_=-1;bool valid_=false,created_=false,committed_=false,attempted_=false;
    void closeFile(){if(fd_>=0){const int fd=fd_;fd_=-1;if(!IO::close(fd))committed_=false;}}
public:
    TLinkCaptureReceiver(std::string path,TLinkNativeBudgetPtr budget):path_(std::move(path)),marker_(path_+".lease"),budget_(std::move(budget)) {
        valid_=TLinkCaptureLeasePath(path_)&&IO::marker(marker_,markerID_)&&live();
    }
    // Marker identity and budget determine liveness independently of committed output.
    bool live()const{return (!budget_||!budget_->stopped())&&IO::sameMarker(marker_,markerID_);}
    bool valid()const{return valid_&&live();}
    bool matches(const char *path)const{return path&&path_==path;}
    bool write(const void *bytes,size_t length){
        if(attempted_)return false;attempted_=true;
        if(!valid()||!bytes||!length||length>32*1024*1024)return false;
        fd_=IO::createOutput(path_,outputID_);if(fd_<0)return false;created_=true;
        const auto *data=static_cast<const uint8_t *>(bytes);size_t offset=0;
        while(offset<length){
            if(!live()){finish();return false;}
            const size_t count=std::min(size_t(65536),length-offset);
            const int64_t written=IO::write(fd_,data+offset,count);
            if(written<0&&IO::interrupted())continue;
            if(written<=0||uint64_t(written)>count){finish();return false;}
            offset+=size_t(written);
        }
        committed_=true;closeFile();committed_=committed_&&live();
        if(!committed_)finish();return committed_;
    }
    void finish(){
        if(fd_>=0){committed_=false;closeFile();}
        if(created_&&(!committed_||!live())){IO::removeOutput(path_,outputID_);created_=false;}
    }
    ~TLinkCaptureReceiver(){finish();}
    TLinkCaptureReceiver(const TLinkCaptureReceiver &)=delete;TLinkCaptureReceiver &operator=(const TLinkCaptureReceiver &)=delete;
};
#endif
