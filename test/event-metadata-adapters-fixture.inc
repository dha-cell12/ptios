static NSString *TLinkEventLockPath(void);
struct FixtureEventPermissionState {mode_t mode;uid_t uid;gid_t gid;};
static bool fixturePermissionsActive=false;
static unsigned fixturePermissionFailures=0;
static FixtureEventPermissionState fixturePermissionState[2]{};
static std::vector<std::string> fixturePermissionCalls;
static unsigned FixturePermissionIndex(const char *path){
    NSString *value=[NSString stringWithUTF8String:path];
    if([value isEqual:TLinkEventChannelRootPath()])return 0;
    if([value isEqual:TLinkEventLockPath()])return 1;
    assert(false);return 2;
}
static int FixtureEventPathStat(const char *path,struct stat *info){
    const int result=::lstat(path,info);
    if(!result&&fixturePermissionsActive){
        const auto state=fixturePermissionState[FixturePermissionIndex(path)];
        info->st_mode=(info->st_mode&S_IFMT)|state.mode;info->st_uid=state.uid;info->st_gid=state.gid;
    }
    return result;
}
static int FixtureRepairPermission(unsigned index,bool owner){
    assert(fixturePermissionsActive&&index<2);
    fixturePermissionCalls.push_back(std::string(index?"lock:":"root:")+(owner?"owner":"mode"));
    const unsigned bit=index*2+(owner?1:0);
    if(fixturePermissionFailures&(1U<<bit)){errno=EACCES;return -1;}
    if(owner){fixturePermissionState[index].uid=501;fixturePermissionState[index].gid=501;}
    else fixturePermissionState[index].mode=index?0640:0750;
    return 0;
}
static int FixtureRootChmod(const char *path,mode_t mode){
    assert(mode==0750);if(fixturePermissionsActive){assert(FixturePermissionIndex(path)==0);return FixtureRepairPermission(0,false);}return ::chmod(path,mode);
}
static int FixtureRootChown(const char *path,uid_t uid,gid_t gid){
    assert(uid==501&&gid==501);if(fixturePermissionsActive){assert(FixturePermissionIndex(path)==0);return FixtureRepairPermission(0,true);}return ::lchown(path,uid,gid);
}
static bool fixtureFingerprintSynthetic=false;
static int fixtureFingerprintFailure=0;
static struct stat fixtureFingerprintInfo{};
static int FixtureFingerprintStat(const char *path,struct stat *info){
    if(!fixtureFingerprintSynthetic)return ::stat(path,info);
    if(fixtureFingerprintFailure){errno=fixtureFingerprintFailure;return -1;}
    *info=fixtureFingerprintInfo;return 0;
}
