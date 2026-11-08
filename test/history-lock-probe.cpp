// Disposable POSIX peer. No Foundation state or after-fork runtime is reused.
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#include <cerrno>
#include <cstdio>
#include <cstring>

static int failure(const char *stage,int error,int code,const char *path){
    std::fprintf(stderr,"History lock probe: stage=%s errno=%d (%s) path=%s\n",stage,error,std::strerror(error),path);
    return code;
}
int main(int argc,char **argv){
    if(argc!=3)return failure("arguments",EINVAL,64,"<missing>");
    const int operation=std::strcmp(argv[2],"shared")==0?LOCK_SH:
        (std::strcmp(argv[2],"exclusive")==0?LOCK_EX:0);
    if(!operation)return failure("operation",EINVAL,64,argv[1]);
    int fd;
    do{fd=::open(argv[1],O_RDWR|O_NONBLOCK|O_NOFOLLOW);}while(fd<0&&errno==EINTR);
    if(fd<0)return failure("open",errno,2,argv[1]);
    int result;
    do{result=::flock(fd,operation|LOCK_NB);}while(result<0&&errno==EINTR);
    const int error=result<0?errno:0;
    int outcome=0;
    if(result<0){
        if(error==EWOULDBLOCK||error==EAGAIN)outcome=1;
        else outcome=failure("flock",error,3,argv[1]);
    }else{
        int unlocked;
        do{unlocked=::flock(fd,LOCK_UN);}while(unlocked<0&&errno==EINTR);
        if(unlocked<0)outcome=failure("unlock",errno,4,argv[1]);
    }
    if(::close(fd)!=0)return failure("close",errno,5,argv[1]);
    return outcome;
}
