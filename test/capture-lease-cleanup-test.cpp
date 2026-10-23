#include "../shared/TLinkCaptureCleanup.h"
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <sys/wait.h>
#include <signal.h>
#include <vector>
struct Fixture {
    std::string root;std::vector<std::string> names;unsigned sequence=0;
    Fixture(){char value[]="/tmp/tlink-capture-cleanup-XXXXXX";char *directory=mkdtemp(value);assert(directory);root=directory;}
    std::string path(){char name[128];snprintf(name,sizeof(name),"/tlinkautod_capture_12345678-1234-ABCD-abcd-%012u.png",++sequence);names.push_back(root+name);return names.back();}
    ~Fixture(){for(const auto &value:names){unlink((value+".lease.owner.v1").c_str());unlink((value+".lease").c_str());unlink(value.c_str());rmdir(value.c_str());}assert(rmdir(root.c_str())==0);}
};
// Functional filesystem cases use a fixed clock to avoid host scheduling pauses
// masking candidates. The portable policy test checks exact 25 ms expiry.
static TLinkCaptureSweepResult scan(const char *directory){return TLinkCaptureSweepDirectory(directory,[]()->uint64_t{return 0;});}
static bool exists(const std::string &value){struct stat st;return lstat(value.c_str(),&st)==0;}
static void gone(const std::string &value){assert(!exists(value)&&!exists(value+".lease")&&!exists(value+".lease.owner.v1"));}
static int plain(const std::string &value,mode_t mode=0600){int fd=open(value.c_str(),O_WRONLY|O_CREAT|O_EXCL|O_CLOEXEC,mode);assert(fd>=0);return fd;}
static void output(const std::string &value,TLinkCaptureFileID id){TLinkCaptureFileID created;const int fd=TLinkCapturePOSIX::createOutput(value,created,id);assert(fd>=0);const uint8_t bytes[]={1,2,3,4};assert(::write(fd,bytes,sizeof(bytes))==ssize_t(sizeof(bytes)));assert(::close(fd)==0);}
static int lease(const std::string &value,TLinkCaptureFileID &id){int fd=TLinkCapturePOSIX::createMarker(value+".lease",id);assert(fd>=0);return fd;}
static void waitChild(pid_t pid,bool killed=false){int status=0;pid_t result;do{result=waitpid(pid,&status,0);}while(result<0&&errno==EINTR);assert(result==pid);if(killed)assert(WIFSIGNALED(status)&&WTERMSIG(status)==SIGKILL);else assert(WIFEXITED(status)&&WEXITSTATUS(status)==0);}
static size_t descriptors(){size_t count=0;for(int fd=0;fd<2048;++fd)if(fcntl(fd,F_GETFD)>=0)++count;return count;}
int main(){
    const size_t before=descriptors();
    {
        Fixture fixture;TLinkCaptureFileID id;
        std::string value=fixture.path();int fd=lease(value,id);output(value,id);assert(TLinkCapturePOSIX::ownsOutput(value,id));
        auto sweep=scan(fixture.root.c_str());assert(sweep.busy==1&&exists(value)&&exists(value+".lease"));
        // Closing the only owner models process exit, with all files intact.
        assert(::close(fd)==0);sweep=scan(fixture.root.c_str());assert(sweep.removed==1);gone(value);
        value=fixture.path();pid_t child=fork();assert(child>=0);
        if(child==0){TLinkCaptureFileID owned;int held=lease(value,owned);(void)held;output(value,owned);_exit(0);}
        waitChild(child);sweep=scan(fixture.root.c_str());assert(sweep.removed==1);gone(value);
        // A separate receiver retains its own SH lock after the daemon is killed.
        value=fixture.path();int signalPipe[2];assert(pipe(signalPipe)==0);child=fork();assert(child>=0);
        if(child==0){close(signalPipe[0]);TLinkCaptureFileID owned;int held=lease(value,owned);(void)held;assert(::write(signalPipe[1],"R",1)==1);for(;;)pause();}
        close(signalPipe[1]);char ready=0;assert(read(signalPipe[0],&ready,1)==1&&ready=='R');close(signalPipe[0]);
        int receiver=TLinkCapturePOSIX::acquireMarker(value+".lease",id);assert(receiver>=0);assert(kill(child,SIGKILL)==0);waitChild(child,true);
        sweep=scan(fixture.root.c_str());assert(sweep.busy==1&&exists(value+".lease"));
        output(value,id);TLinkCapturePOSIX::releaseMarker(receiver,value,id);gone(value);
        // Legacy files have no versioned owner sidecar and are never swept.
        value=fixture.path();assert(close(plain(value+".lease"))==0&&close(plain(value))==0);
        sweep=scan(fixture.root.c_str());assert(sweep.candidates==0&&exists(value)&&exists(value+".lease"));
        receiver=TLinkCapturePOSIX::acquireMarker(value+".lease",id);assert(receiver==-2);TLinkCapturePOSIX::releaseMarker(receiver,value,id);
        // Missing/mismatched xattrs, symlinks, directories, FIFOs and hard links
        // are retained even when the matching marker belongs to a dead owner.
        value=fixture.path();fd=lease(value,id);assert(close(fd)==0&&close(plain(value))==0);
        sweep=scan(fixture.root.c_str());assert(exists(value)&&exists(value+".lease.owner.v1"));
        std::string wrong=fixture.path();fd=lease(wrong,id);assert(close(fd)==0);auto mismatched=id;++mismatched.inode;output(wrong,mismatched);
        std::string target=fixture.path();assert(close(plain(target))==0);
        std::string symbolic=fixture.path();fd=lease(symbolic,id);assert(close(fd)==0&&symlink(target.c_str(),symbolic.c_str())==0);
        std::string directory=fixture.path();fd=lease(directory,id);assert(close(fd)==0&&mkdir(directory.c_str(),0700)==0);
        std::string nested=directory+"/keep";assert(close(plain(nested))==0);
        std::string fifo=fixture.path();fd=lease(fifo,id);assert(close(fd)==0&&mkfifo(fifo.c_str(),0600)==0);
        std::string linked=fixture.path();fd=lease(linked,id);output(linked,id);assert(close(fd)==0);
        std::string alias=fixture.path();assert(link(linked.c_str(),alias.c_str())==0);
        sweep=scan(fixture.root.c_str());
        for(const auto &preserved:{wrong,symbolic,directory,fifo,linked,alias,target})assert(exists(preserved));
        assert(exists(nested));
        assert(unlink(nested.c_str())==0);
        // Guard and marker replacement cannot authorize cleanup of new objects.
        std::string guardLink=fixture.path();fd=lease(guardLink,id);assert(close(fd)==0);
        assert(unlink((guardLink+".lease.owner.v1").c_str())==0&&symlink(target.c_str(),(guardLink+".lease.owner.v1").c_str())==0);
        std::string changed=fixture.path();fd=lease(changed,id);assert(close(fd)==0);
        std::string saved=fixture.path();assert(link((changed+".lease").c_str(),saved.c_str())==0&&unlink((changed+".lease").c_str())==0);
        assert(close(plain(changed+".lease"))==0);TLinkCaptureFileID replacement;assert(TLinkCapturePOSIX::marker(changed+".lease",replacement)&&!TLinkCaptureSameID(id,replacement));
        sweep=scan(fixture.root.c_str());assert(exists(guardLink+".lease")&&exists(changed+".lease")&&exists(changed+".lease.owner.v1"));
        // Only an empty initial reservation with no marker/output is reclaimable
        // without a complete proof; partial records are quarantined.
        std::string empty=fixture.path();assert(close(plain(empty+".lease.owner.v1",0644))==0);
        std::string partial=fixture.path();fd=lease(partial,id);assert(ftruncate(fd,9)==0&&close(fd)==0);
        sweep=scan(fixture.root.c_str());assert(!exists(empty+".lease.owner.v1")&&exists(partial+".lease")&&exists(partial+".lease.owner.v1"));
        assert(scan((fixture.root+"/missing").c_str()).directoryError);
        // Concurrent cleanup processes use EX/NB and revalidate the directory
        // entry, so they cannot remove an active receiver or replay an unlink.
        std::vector<std::string> orphans;
        for(unsigned n=0;n<24;++n){std::string orphan=fixture.path();fd=lease(orphan,id);output(orphan,id);assert(close(fd)==0);orphans.push_back(orphan);}
        std::vector<pid_t> cleaners;
        for(unsigned n=0;n<2;++n){pid_t cleaner=fork();assert(cleaner>=0);if(cleaner==0){for(unsigned j=0;j<4;++j)(void)scan(fixture.root.c_str());_exit(0);}cleaners.push_back(cleaner);}
        for(pid_t cleaner:cleaners)waitChild(cleaner);
        for(unsigned n=0;n<8;++n){sweep=scan(fixture.root.c_str());assert(sweep.entries<=4096&&sweep.candidates<=64);}
        for(const auto &orphan:orphans)gone(orphan);
        // Hard-linked and unsafe owner records are untouched.
        std::string guardHard=fixture.path();fd=lease(guardHard,id);assert(close(fd)==0);
        std::string guardAlias=fixture.path();assert(link((guardHard+".lease.owner.v1").c_str(),guardAlias.c_str())==0);
        std::string unsafe=fixture.path();fd=lease(unsafe,id);assert(fchmod(fd,0666)==0&&close(fd)==0);
        sweep=scan(fixture.root.c_str());assert(exists(guardHard+".lease")&&exists(guardAlias)&&exists(unsafe+".lease.owner.v1"));
    }
    assert(descriptors()==before);
    puts("Capture cleanup POSIX passed: real flock/xattr proof, process exit/SIGKILL, held receiver after owner death, concurrent sweepers, legacy/foreign/partial evidence preserved, nonrecursive unlink and zero live fixture descriptors/files.");
}
