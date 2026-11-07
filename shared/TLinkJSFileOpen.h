#pragma once

// The construction scope owns a newly opened descriptor until a fully
// initialized handle takes it. Retire clears first, even if a test/provider
// close callback throws; retrying close could target a reused descriptor.
class TLinkJSFileOpenOwner {
    int descriptor_;
public:
    explicit TLinkJSFileOpenOwner(int descriptor):descriptor_(descriptor){}
    TLinkJSFileOpenOwner(const TLinkJSFileOpenOwner &)=delete;
    TLinkJSFileOpenOwner &operator=(const TLinkJSFileOpenOwner &)=delete;
    int release(){const int value=descriptor_;descriptor_=-1;return value;}
    template<class Close> void retire(Close closeDescriptor){
        const int value=release();if(value>=0)closeDescriptor(value);
    }
    bool held()const{return descriptor_>=0;}
};
