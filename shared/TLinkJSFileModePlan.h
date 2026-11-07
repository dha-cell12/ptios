#pragma once
#import <Foundation/Foundation.h>

#ifdef __cplusplus
class TLinkJSFileModePlan;
TLinkJSFileModePlan TLinkJSFilePrepareMode(NSString *mode);
// Only the preparer can create a plan. Validation, path policy and open share
// the same owned immutable mode; copying the value retains that snapshot.
class TLinkJSFileModePlan {
    __strong NSString *mode_=nil;
    bool valid_=false,writing_=false,plus_=false;
    int flags_=0;
    TLinkJSFileModePlan()=default;
    friend TLinkJSFileModePlan TLinkJSFilePrepareMode(NSString *mode);
public:
    NSString *mode() const{return mode_;}
    bool valid() const{return valid_;}
    bool writing() const{return writing_;}
    bool plus() const{return plus_;}
    int flags() const{return flags_;}
};
#endif
