#ifndef TLINK_UTF8_DATA_H
#define TLINK_UTF8_DATA_H
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

// Borrow only existing internal UTF8 storage from an immutable snapshot.
// UTF8String's temporary C buffer is deliberately not used for escaped NSData.
static inline NSData *TLinkUTF8DataFromString(NSString *text)
{
    if (![text isKindOfClass:[NSString class]]) return [text dataUsingEncoding:NSUTF8StringEncoding];
    NSString *snapshot = [text copy];
    if (!snapshot) return nil;
    const char *bytes = CFStringGetCStringPtr((__bridge CFStringRef)snapshot, kCFStringEncodingUTF8);
    if (!bytes) return [snapshot dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger length = [snapshot lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    return [[NSData alloc] initWithBytesNoCopy:(void *)bytes length:length
                                 deallocator:^(void *buffer, NSUInteger count) {
        (void)buffer;
        (void)count;
        // The immutable string owns the buffer. Keep it until the view is released.
        (void)[snapshot length];
    }];
}
#endif
