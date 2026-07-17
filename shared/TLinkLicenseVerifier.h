#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *TLinkLicenseDirectoryPath(void);
FOUNDATION_EXPORT NSString *TLinkLicenseLeasePath(void);
FOUNDATION_EXPORT NSString *TLinkLicenseDevicePublicKeyPath(void);
FOUNDATION_EXPORT NSString *TLinkLicenseDeviceKeyTag(void);
FOUNDATION_EXPORT NSString *TLinkInstalledApplicationBundlePath(void);
FOUNDATION_EXPORT NSString *TLinkBundledExecutablePath(NSString *name);
FOUNDATION_EXPORT NSDictionary *TLinkLicenseConfiguration(void);
FOUNDATION_EXPORT NSDictionary *TLinkLicenseStatusDictionary(void);
FOUNDATION_EXPORT BOOL TLinkLicenseFeatureAllowed(NSString *feature, NSString **error);
FOUNDATION_EXPORT BOOL TLinkLicenseEnforcementEnabled(void);
FOUNDATION_EXPORT void TLinkLicenseInvalidateCache(void);
