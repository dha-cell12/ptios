#import <Foundation/Foundation.h>

FOUNDATION_EXPORT BOOL TLinkRootfullLicenseTaskIsExempt(NSInteger taskType);
FOUNDATION_EXPORT NSString *TLinkRootfullLicenseFeatureForTask(NSInteger taskType);
FOUNDATION_EXPORT BOOL TLinkRootfullLicenseTaskAllowed(NSInteger taskType,
                                                       NSString **denialResponse);
FOUNDATION_EXPORT BOOL TLinkRootfullLicenseComponentAllowed(NSString *feature,
                                                            NSString *component,
                                                            NSString **denialResponse);

