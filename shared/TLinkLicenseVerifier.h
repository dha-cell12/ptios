#import <Foundation/Foundation.h>
#include <stdint.h>

FOUNDATION_EXPORT NSString *TLinkLicenseDirectoryPath(void);
FOUNDATION_EXPORT NSString *TLinkLicenseLeasePath(void);
FOUNDATION_EXPORT NSString *TLinkLicenseDevicePublicKeyPath(void);
FOUNDATION_EXPORT NSString *TLinkLicenseDeviceKeyTag(void);
FOUNDATION_EXPORT NSString *TLinkLicenseGenerationPath(void);
FOUNDATION_EXPORT NSString *TLinkLicenseTrustCheckpointPath(void);
FOUNDATION_EXPORT uint64_t TLinkLicenseGeneration(void);
FOUNDATION_EXPORT uint64_t TLinkLicenseAdvanceGeneration(void);
FOUNDATION_EXPORT BOOL TLinkLicenseResetTrustCheckpoint(NSString **error);
FOUNDATION_EXPORT NSString *TLinkInstalledApplicationBundlePath(void);
FOUNDATION_EXPORT NSString *TLinkBundledExecutablePath(NSString *name);
FOUNDATION_EXPORT NSDictionary *TLinkLicenseConfiguration(void);
FOUNDATION_EXPORT NSDictionary *TLinkLicenseStatusDictionary(void);
FOUNDATION_EXPORT BOOL TLinkLicenseFeatureAllowed(NSString *feature, NSString **error);
FOUNDATION_EXPORT NSData *TLinkLicenseCreateDeviceSignature(
    NSData *message,
    NSString **error);
FOUNDATION_EXPORT BOOL TLinkLicenseDevicePublicKeyAnchored(
    NSData *publicPoint,
    NSString **error);
FOUNDATION_EXPORT BOOL TLinkLicenseEnforcementEnabled(void);
FOUNDATION_EXPORT NSString *TLinkLicenseBuildMode(void);
FOUNDATION_EXPORT void TLinkLicenseInvalidateCache(void);
FOUNDATION_EXPORT NSDictionary *TLinkLicensePerformanceDictionary(void);
