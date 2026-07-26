#import "TLinkRootfullLicensePolicy.h"
#import "TLinkLicenseVerifier.h"

typedef struct {
    NSInteger task;
    const char *feature;
} TLinkRootfullLicenseTaskPolicyEntry;

static const TLinkRootfullLicenseTaskPolicyEntry kTLinkRootfullLicenseTaskPolicy[] = {
    {10, "automation"},
    {11, "automation"},
    {12, "automation"},
    {13, "shell"},
    {14, "automation"},
    {15, "automation"},
    {16, "automation"},
    {17, "automation"},
    {18, "automation"},
    {19, "script"},
    {20, "script"},
    {21, "automation"},
    {22, "automation"},
    {23, "automation"},
    {24, "automation"},
    {25, "automation"},
    {26, "automation"},
    {27, "automation"},
    {28, "automation"},
    {29, "automation"},
    {30, "automation"},
    {31, "admin"},
    {32, "automation"},
    {33, "automation"},
    {34, "automation"},
    {35, "automation"},
    {36, "script"},
    {37, "script"},
    {38, "script"},
    {39, "script"},
    {40, "automation"},
    {41, "script"},
    {42, "automation"},
    {43, "automation"},
    {44, "automation"},
    {45, "automation"},
    {46, "automation"},
    {47, "automation"},
    {48, "automation"},
    {49, "automation"},
    {50, "automation"},
    {51, "automation"},
    {52, "automation"},
    {53, "automation"},
    {54, "automation"},
    {55, "automation"},
    {56, "automation"},
    {57, "automation"},
    {58, "automation"},
    {59, "automation"},
    {61, "automation"},
    {62, "automation"},
    {63, "automation"},
    {64, "automation"},
    {65, "automation"},
    {66, "automation"},
    {67, "automation"},
    {68, "automation"},
    {69, "automation"},
    {70, "automation"},
    {71, "shell"},
    {72, "admin"},
    {90, "automation"},
    {91, "automation"},
};

BOOL TLinkRootfullLicenseTaskIsExempt(NSInteger taskType)
{
    return taskType == 60 ||
           taskType == 75 ||
           taskType == 76 ||
           taskType == 96 ||
           taskType == 97 ||
           taskType == 99;
}

NSString *TLinkRootfullLicenseFeatureForTask(NSInteger taskType)
{
    for (NSUInteger index = 0;
         index < sizeof(kTLinkRootfullLicenseTaskPolicy) / sizeof(kTLinkRootfullLicenseTaskPolicy[0]);
         index++) {
        if (kTLinkRootfullLicenseTaskPolicy[index].task == taskType) {
            return [NSString stringWithUTF8String:kTLinkRootfullLicenseTaskPolicy[index].feature];
        }
    }
    return nil;
}

static NSString *TLinkRootfullLicenseToken(id value, NSString *fallback)
{
    NSString *text = [value isKindOfClass:[NSString class]] ? value : [value description];
    if (text.length == 0) text = fallback ?: @"unknown";
    NSMutableString *token = [text mutableCopy];
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    for (NSInteger index = (NSInteger)token.length - 1; index >= 0; index--) {
        if ([whitespace characterIsMember:[token characterAtIndex:(NSUInteger)index]]) {
            [token replaceCharactersInRange:NSMakeRange((NSUInteger)index, 1) withString:@"_"];
        }
    }
    return token;
}

static NSString *TLinkRootfullLicenseDeniedResponse(NSString *subject,
                                                    NSString *feature,
                                                    NSString *licenseError)
{
    NSDictionary *status = TLinkLicenseStatusDictionary();
    NSString *state = TLinkRootfullLicenseToken(status[@"state"], @"invalid");
    NSString *error = TLinkRootfullLicenseToken(licenseError.length > 0
                                                ? licenseError
                                                : status[@"error"],
                                                @"license_required");
    return [NSString stringWithFormat:@"-1;;license_required %@ feature=%@ state=%@ error=%@\r\n",
            subject ?: @"component=unknown",
            TLinkRootfullLicenseToken(feature, @"unknown"),
            state,
            error];
}

BOOL TLinkRootfullLicenseTaskAllowed(NSInteger taskType, NSString **denialResponse)
{
    if (TLinkRootfullLicenseTaskIsExempt(taskType)) {
        return YES;
    }

    NSString *feature = TLinkRootfullLicenseFeatureForTask(taskType);
    if (feature.length == 0) {
        if (denialResponse) {
            *denialResponse = [NSString stringWithFormat:
                @"-1;;license_policy_missing task=%ld\r\n", (long)taskType];
        }
        return NO;
    }

    NSString *licenseError = nil;
    if (TLinkLicenseFeatureAllowed(feature, &licenseError)) {
        return YES;
    }
    if (denialResponse) {
        *denialResponse = TLinkRootfullLicenseDeniedResponse(
            [NSString stringWithFormat:@"task=%ld", (long)taskType],
            feature,
            licenseError);
    }
    return NO;
}

BOOL TLinkRootfullLicenseComponentAllowed(NSString *feature,
                                         NSString *component,
                                         NSString **denialResponse)
{
    NSString *licenseError = nil;
    if (feature.length > 0 && TLinkLicenseFeatureAllowed(feature, &licenseError)) {
        return YES;
    }
    if (denialResponse) {
        *denialResponse = TLinkRootfullLicenseDeniedResponse(
            [NSString stringWithFormat:@"component=%@",
             TLinkRootfullLicenseToken(component, @"unknown")],
            feature,
            licenseError);
    }
    return NO;
}

