#import "TLinkHardwareIdentity.h"
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <stdint.h>

typedef CFTypeRef (*TLinkMGCopyAnswerFn)(CFStringRef key);
typedef uint32_t TLinkIOObject;
typedef TLinkIOObject (*TLinkIORegistryEntryFromPathFn)(uint32_t mainPort, const char *path);
typedef CFTypeRef (*TLinkIORegistryEntryCreateCFPropertyFn)(TLinkIOObject entry,
                                                            CFStringRef key,
                                                            CFAllocatorRef allocator,
                                                            uint32_t options);
typedef int32_t (*TLinkIOObjectReleaseFn)(TLinkIOObject object);

static NSString *TLinkStringFromHardwareValue(CFTypeRef value)
{
    if (!value) return nil;
    if (CFGetTypeID(value) == CFStringGetTypeID()) {
        return [(__bridge NSString *)value copy];
    }
    if (CFGetTypeID(value) == CFNumberGetTypeID()) {
        return [(__bridge NSNumber *)value stringValue];
    }
    if (CFGetTypeID(value) == CFDataGetTypeID()) {
        NSData *data = (__bridge NSData *)value;
        if (data.length == 0 || data.length > 128) return nil;
        const uint8_t *bytes = (const uint8_t *)data.bytes;
        NSUInteger printableLength = data.length;
        while (printableLength > 0 && bytes[printableLength - 1] == 0) printableLength--;
        BOOL printable = printableLength > 0;
        for (NSUInteger index = 0; index < printableLength; index++) {
            if (bytes[index] < 0x20 || bytes[index] > 0x7e) {
                printable = NO;
                break;
            }
        }
        if (printable) {
            return [[NSString alloc] initWithBytes:bytes length:printableLength encoding:NSUTF8StringEncoding];
        }
        NSMutableString *hex = [NSMutableString stringWithString:@"0x"];
        for (NSUInteger index = 0; index < data.length; index++) {
            [hex appendFormat:@"%02x", bytes[index]];
        }
        return hex;
    }
    return nil;
}

static NSDictionary *TLinkMobileGestaltEvidence(void)
{
    NSMutableDictionary *result = [@{
        @"source": @"mobile_gestalt",
        @"values": [NSMutableDictionary dictionary],
        @"availability": [NSMutableDictionary dictionary],
    } mutableCopy];
    void *handle = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY | RTLD_LOCAL);
    TLinkMGCopyAnswerFn copyAnswer = handle
        ? (TLinkMGCopyAnswerFn)dlsym(handle, "MGCopyAnswer")
        : NULL;
    NSMutableDictionary *values = result[@"values"];
    NSMutableDictionary *availability = result[@"availability"];
    NSDictionary *keys = @{
        @"udid": @"UniqueDeviceID",
        @"serial": @"SerialNumber",
        @"mlb": @"MLBSerialNumber",
        @"ecid": @"UniqueChipID",
    };
    for (NSString *field in keys) {
        CFTypeRef answer = copyAnswer ? copyAnswer((__bridge CFStringRef)keys[field]) : NULL;
        NSString *value = TLinkStringFromHardwareValue(answer);
        if (answer) CFRelease(answer);
        if (value.length > 0) {
            values[field] = value;
            availability[field] = @"present";
        } else {
            availability[field] = copyAnswer ? @"unavailable" : @"collector_unavailable";
        }
    }
    if (handle) dlclose(handle);
    return result;
}

static NSDictionary *TLinkIORegistryEvidence(void)
{
    NSMutableDictionary *result = [@{
        @"source": @"ioregistry",
        @"values": [NSMutableDictionary dictionary],
        @"availability": [NSMutableDictionary dictionary],
    } mutableCopy];
    void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
    TLinkIORegistryEntryFromPathFn entryFromPath = handle
        ? (TLinkIORegistryEntryFromPathFn)dlsym(handle, "IORegistryEntryFromPath")
        : NULL;
    TLinkIORegistryEntryCreateCFPropertyFn createProperty = handle
        ? (TLinkIORegistryEntryCreateCFPropertyFn)dlsym(handle, "IORegistryEntryCreateCFProperty")
        : NULL;
    TLinkIOObjectReleaseFn releaseObject = handle
        ? (TLinkIOObjectReleaseFn)dlsym(handle, "IOObjectRelease")
        : NULL;
    NSMutableDictionary *values = result[@"values"];
    NSMutableDictionary *availability = result[@"availability"];
    NSDictionary *keys = @{
        @"serial": @"serial-number",
        @"mlb": @"mlb-serial-number",
        @"ecid": @"unique-chip-id",
    };
    NSArray *paths = @[@"IODeviceTree:/chosen", @"IODeviceTree:/", @"IOService:/"];
    BOOL collectorAvailable = entryFromPath && createProperty && releaseObject;
    if (collectorAvailable) {
        for (NSString *path in paths) {
            TLinkIOObject entry = entryFromPath(0, path.UTF8String);
            if (!entry) continue;
            for (NSString *field in keys) {
                if (values[field]) continue;
                CFTypeRef property = createProperty(entry,
                                                     (__bridge CFStringRef)keys[field],
                                                     kCFAllocatorDefault,
                                                     0);
                NSString *value = TLinkStringFromHardwareValue(property);
                if (property) CFRelease(property);
                if (value.length > 0) values[field] = value;
            }
            releaseObject(entry);
        }
    }
    availability[@"udid"] = @"not_exposed_by_source";
    for (NSString *field in keys) {
        availability[field] = values[field]
            ? @"present"
            : (collectorAvailable ? @"unavailable" : @"collector_unavailable");
    }
    if (handle) dlclose(handle);
    return result;
}

NSDictionary *TLinkCopyHardwareIdentityEvidence(void)
{
    return @{
        @"version": @1,
        @"collectors": @[TLinkMobileGestaltEvidence(), TLinkIORegistryEvidence()],
    };
}
