#include "../shared/TLinkConsoleLogRetention.h"
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <stdexcept>
#include <sys/wait.h>
using namespace TLinkConsoleLogRetention;
static std::string nameFor(unsigned n,bool helper=false){
    char value[64];std::snprintf(value,sizeof(value),"%08x-0000-4000-8000-%012x%s",n,n,helper?"-helper.log":".log");return value;
}
static void create(const std::string &path,const char *bytes="log\n"){
    Detail::FD fd(::open(path.c_str(),O_WRONLY|O_CREAT|O_EXCL,0600));assert(fd.get()>=0);
    const size_t length=std::strlen(bytes);assert(::write(fd.get(),bytes,length)==(ssize_t)length);
}
static bool exists(const std::string &path){struct stat s;return ::lstat(path.c_str(),&s)==0;}
static void mark(const std::string &path){
    Detail::FD fd(::open(path.c_str(),O_RDONLY|O_NOFOLLOW));assert(fd.get()>=0);
    struct stat info;assert(::fstat(fd.get(),&info)==0);const auto proof=Proof(Detail::Identify(info));
    assert(::fsetxattr(fd.get(),Detail::MarkerName,proof.data(),proof.size(),0,0)==0);
}
static Candidate candidate(int dir,const std::string &name){
    Candidate result;result.name=name;struct stat s;assert(::fstatat(dir,name.c_str(),&s,AT_SYMLINK_NOFOLLOW)==0);result.identity=Detail::Identify(s);return result;
}
static unsigned fdCount(){unsigned count=0;for(int n=0;n<1024;++n)if(::fcntl(n,F_GETFD)>=0)++count;return count;}
static void completedCases(const std::string &directory){
    const std::string active=directory+"/"+nameFor(1000),legacy=directory+"/"+nameFor(1001,true);
    create(active);create(legacy);create(directory+"/latest.log");create(directory+"/latest-helper.log");create(directory+"/notes.log");
    for(unsigned n=0;n<100;++n){
        const std::string path=directory+"/"+nameFor(n,n%2);create(path);
        struct timespec times[2]={{1000+(time_t)n,0},{1000+(time_t)n,0}};assert(::utimensat(AT_FDCWD,path.c_str(),times,0)==0);
        if(n%2){Completion completed(path.c_str());}else assert(Complete(path.c_str()).marked);
    }
    Detail::FD dir(::open(directory.c_str(),O_RDONLY|O_DIRECTORY));assert(dir.get()>=0);
    const auto state=Sweep(dir.get());assert(state.eligible==50&&state.removed==0&&!state.incomplete);
    for(unsigned n=0;n<100;++n)assert(exists(directory+"/"+nameFor(n,n%2))==(n>=50));
    assert(exists(active)&&exists(legacy)&&exists(directory+"/latest.log")&&exists(directory+"/latest-helper.log")&&exists(directory+"/notes.log"));
    const auto partial=Sweep(dir.get(),0,2);assert(partial.incomplete&&partial.removed==0);
    assert(!Complete((directory+"/latest.log").c_str()).marked);
    assert(!Complete((directory+"/missing.log").c_str()).marked);
}
static void refusalCases(const std::string &directory){
    Detail::FD dir(::open(directory.c_str(),O_RDONLY|O_DIRECTORY));assert(dir.get()>=0);
    const auto busyName=nameFor(2000);const auto busy=directory+"/"+busyName;create(busy);mark(busy);
    auto held=candidate(dir.get(),busyName);
    {
        Detail::FD owner(::open(busy.c_str(),O_RDONLY));assert(owner.get()>=0&&::flock(owner.get(),LOCK_SH|LOCK_NB)==0);
        Result result;Detail::Retire(dir.get(),held,result);assert(result.busy==1&&exists(busy));
    }
    Result released;Detail::Retire(dir.get(),held,released);assert(released.removed==1&&!exists(busy));
    const auto changedName=nameFor(2001);const auto changed=directory+"/"+changedName;create(changed);mark(changed);
    auto prior=candidate(dir.get(),changedName);assert(::rename(changed.c_str(),(changed+".saved").c_str())==0);create(changed);mark(changed);
    Result replacement;Detail::Retire(dir.get(),prior,replacement);assert(replacement.refused==1&&exists(changed));
    auto beforeAppend=candidate(dir.get(),changedName);
    {Detail::FD writer(::open(changed.c_str(),O_WRONLY|O_APPEND));assert(writer.get()>=0&&::write(writer.get(),"x",1)==1);}
    Result append;Detail::Retire(dir.get(),beforeAppend,append);assert(append.refused==1&&exists(changed));
    auto beforeMarker=candidate(dir.get(),changedName);
    {Detail::FD writer(::open(changed.c_str(),O_RDONLY));assert(writer.get()>=0&&::fremovexattr(writer.get(),Detail::MarkerName,0)==0);}
    Result removedMarker;Detail::Retire(dir.get(),beforeMarker,removedMarker);assert(removedMarker.refused==1&&exists(changed));
    const auto linked=directory+"/"+nameFor(2002);create(linked);mark(linked);assert(::link(linked.c_str(),(linked+".alias").c_str())==0);
    const auto symbolic=directory+"/"+nameFor(2003);assert(::symlink(linked.c_str(),symbolic.c_str())==0);
    const auto fifo=directory+"/"+nameFor(2004);assert(::mkfifo(fifo.c_str(),0600)==0);
    const auto folder=directory+"/"+nameFor(2005);assert(::mkdir(folder.c_str(),0700)==0);create(folder+"/"+nameFor(1));mark(folder+"/"+nameFor(1));
    const auto foreign=directory+"/"+nameFor(2006);create(foreign);
    {Detail::FD fd(::open(foreign.c_str(),O_RDONLY));assert(fd.get()>=0&&::fsetxattr(fd.get(),Detail::MarkerName,"foreign",7,0,0)==0);}
    const auto writable=directory+"/"+nameFor(2007);create(writable);mark(writable);assert(::chmod(writable.c_str(),0666)==0);
    const auto copied=directory+"/"+nameFor(2008);create(copied);
    {Detail::FD source(::open(writable.c_str(),O_RDONLY)),target(::open(copied.c_str(),O_RDONLY));uint8_t proof[24];
        assert(source.get()>=0&&target.get()>=0&&::fgetxattr(source.get(),Detail::MarkerName,proof,sizeof(proof),0,0)==24);
        assert(::fsetxattr(target.get(),Detail::MarkerName,proof,sizeof(proof),0,0)==0);}
    Sweep(dir.get(),0);
    for(const auto &path:{linked,symbolic,fifo,folder,foreign,changed,writable,copied})assert(exists(path));
    assert(exists(folder+"/"+nameFor(1)));
    assert(!Complete(linked.c_str()).marked&&!Complete(symbolic.c_str()).marked&&!Complete(fifo.c_str()).marked&&!Complete(folder.c_str()).marked&&!Complete(writable.c_str()).marked);
}
static void concurrencyCases(const std::string &directory){
    assert(::mkdir(directory.c_str(),0700)==0);Detail::FD dir(::open(directory.c_str(),O_RDONLY|O_DIRECTORY));assert(dir.get()>=0);
    for(unsigned n=0;n<128;++n){const auto path=directory+"/"+nameFor(n);create(path);mark(path);}
    std::vector<pid_t> children;
    for(unsigned n=0;n<8;++n){
        const pid_t child=::fork();assert(child>=0);
        if(child==0){const auto result=Sweep(dir.get(),3);::_exit(result.incomplete||result.errors?2:0);}
        children.push_back(child);
    }
    for(pid_t child:children){int status=0;pid_t waited;do{waited=::waitpid(child,&status,0);}while(waited<0&&errno==EINTR);assert(waited==child&&WIFEXITED(status)&&WEXITSTATUS(status)==0);}
    const auto final=Sweep(dir.get(),3);assert(final.eligible==3&&final.removed==0);
}
static void lifetimeCases(const std::string &directory){
    for(unsigned n=0;n<128;++n){
        const auto path=directory+"/"+nameFor(3000+n,n%2);create(path);
        struct timespec times[2]={{200000+(time_t)n,0},{200000+(time_t)n,0}};assert(::utimensat(AT_FDCWD,path.c_str(),times,0)==0);
        try {Completion completed(path.c_str());if(n%2)throw std::runtime_error("unwind");}catch(const std::runtime_error &){}
        Detail::FD fd(::open(path.c_str(),O_RDONLY));struct stat info;assert(fd.get()>=0&&::fstat(fd.get(),&info)==0&&Detail::Marked(fd.get(),info));
    }
}
static void byteBudgetCases(const std::string &directory){
    assert(::mkdir(directory.c_str(),0700)==0);Detail::FD dir(::open(directory.c_str(),O_RDONLY|O_DIRECTORY));assert(dir.get()>=0);
    const uint64_t mib=1024*1024;
    for(unsigned n=0;n<4;++n){
        const auto path=directory+"/"+nameFor(n);create(path);
        {Detail::FD file(::open(path.c_str(),O_WRONLY));assert(file.get()>=0&&::ftruncate(file.get(),8*mib)==0);}
        struct timespec times[2]={{100+(time_t)n,0},{100+(time_t)n,0}};assert(::utimensat(AT_FDCWD,path.c_str(),times,0)==0);mark(path);
    }
    auto result=Sweep(dir.get());assert(result.removed==1&&result.plannedKeep==3&&result.plannedBytes==24*mib&&!exists(directory+"/"+nameFor(0)));
    const auto huge=directory+"/"+nameFor(100),small=directory+"/"+nameFor(101);
    create(huge);{Detail::FD file(::open(huge.c_str(),O_WRONLY));assert(file.get()>=0&&::ftruncate(file.get(),26*mib)==0);}mark(huge);
    create(small);{Detail::FD file(::open(small.c_str(),O_WRONLY));assert(file.get()>=0&&::ftruncate(file.get(),mib/2)==0);}
    struct timespec old[2]={{1,0},{1,0}};assert(::utimensat(AT_FDCWD,small.c_str(),old,0)==0);mark(small);
    result=Sweep(dir.get());assert(result.removed==1&&!exists(huge)&&exists(small)&&result.plannedKeep==4&&result.plannedBytes==24*mib+mib/2);
    result=Sweep(dir.get(),KeepCompleted,ScanLimit,mib/2);assert(result.removed==3&&result.plannedKeep==1&&result.plannedBytes==mib/2&&exists(small));
    const auto empty=directory+"/"+nameFor(102);create(empty,"");mark(empty);
    result=Sweep(dir.get(),KeepCompleted,ScanLimit,0);assert(result.removed==1&&result.plannedKeep==1&&result.plannedBytes==0&&exists(empty));
}
int main(int argc,char **argv){
    assert(argc==2);const unsigned descriptors=fdCount();const std::string base=argv[1],directory=base+"/_logs";
    assert(::mkdir(directory.c_str(),0700)==0);
    completedCases(directory);refusalCases(directory);lifetimeCases(directory);concurrencyCases(base+"/parallel");byteBudgetCases(base+"/quota");
    const auto alias=base+"/alias";assert(::mkdir(alias.c_str(),0700)==0);assert(::symlink(directory.c_str(),(alias+"/_logs").c_str())==0);
    assert(!Complete((alias+"/_logs/"+nameFor(1)).c_str()).marked);
    const auto outside=alias+"/"+nameFor(99);create(outside);assert(!Complete(outside.c_str()).marked&&exists(outside));
    const auto cancelled=directory+"/"+nameFor(9999);create(cancelled);
    {Completion incomplete(cancelled.c_str());incomplete.cancel();}
    {Detail::FD fd(::open(cancelled.c_str(),O_RDONLY));struct stat info;assert(fd.get()>=0&&::fstat(fd.get(),&info)==0&&!Detail::Marked(fd.get(),info));}
    assert(!Complete(nullptr).marked&&!Complete("/tmp/not-a-log").marked);
    assert(fdCount()==descriptors);
    puts("Console retention POSIX passed: real xattr terminal ownership, 50 newest completed files, active/legacy/latest preservation, incomplete-scan refusal, symlink/FIFO/directory/hardlink/foreign-marker refusal, locks/replacements/appends, eight process cleaners and 128 normal/throwing scope lifecycles; zero final fixture FDs. Installed logs are untouched.");
}
