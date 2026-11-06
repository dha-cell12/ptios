#pragma once
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include <objc/runtime.h>
#include "TLinkAXSelectorPolicy.h"

namespace TLinkAXSelectorPlan {
inline bool Admit(NSString *text) {
    return TLinkAXSelectorPolicy::AdmitUTF16(text.length) &&
        TLinkAXSelectorPolicy::AdmitUTF8([text lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
}

// Observe concrete immutable classes from objects created by Foundation. Do
// not depend on private class names or cache mutable/custom string behavior.
inline bool StableString(NSString *text) {
    static Class classes[4];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        classes[0] = object_getClass(@"TLinkAXSelector");
        @autoreleasepool {
            @try {
                classes[1] = object_getClass([[NSString alloc] initWithUTF8String:"short"]);
                classes[2] = object_getClass([[NSString alloc] initWithUTF8String:
                    "A long immutable selector sample created by Foundation for class identity"]);
                const unichar units[] = {0x1ea3, 0x6d4b, 0x8bd5, 0x0041};
                classes[3] = object_getClass([[NSString alloc] initWithCharacters:units length:4]);
            } @catch (__unused NSException *exception) {
                // Missing classes simply keep the compatibility path.
            }
        }
    });
    Class type = object_getClass(text);
    for (Class known : classes) {
        if (known && type == known) return ![text isKindOfClass:[NSMutableString class]];
    }
    return false;
}

inline NSString *Fold(NSString *text) { return [text lowercaseString]; }

class Text {
    __strong NSString *expected_, *mode_, *folded_;
    bool caseSensitive_, checked_ = false, fast_ = false, prepared_ = false;
    enum class Mode { Contains, Exact, Prefix } modeValue_ = Mode::Contains;
public:
    Text(NSString *expected, NSString *mode, BOOL caseSensitive)
        : expected_(expected), mode_(mode), folded_(nil), caseSensitive_(caseSensitive) {}
    Text(const Text &) = delete;
    Text &operator=(const Text &) = delete;
    template<class Compatibility>
    BOOL accepts(NSString *candidate, Compatibility compatibility) {
        if (!checked_) {
            fast_ = StableString(expected_) && StableString(mode_);
            checked_ = true;
        }
        if (!fast_) return compatibility(candidate, expected_, mode_, caseSensitive_);
        if (expected_.length == 0) return YES;
        NSString *left = candidate ?: @"";
        // Keep candidate normalization and its reached faults on every call,
        // including value after a label match; only immutable selector work is reused.
        if (!caseSensitive_) left = Fold(left);
        if (!prepared_) {
            folded_ = caseSensitive_ ? expected_ : Fold(expected_);
            if ([mode_ isEqualToString:@"exact"]) modeValue_ = Mode::Exact;
            else if ([mode_ isEqualToString:@"prefix"]) modeValue_ = Mode::Prefix;
            prepared_ = true;
        }
        switch (modeValue_) {
            case Mode::Exact: return [left isEqualToString:folded_];
            case Mode::Prefix: return [left hasPrefix:folded_];
            case Mode::Contains: return [left rangeOfString:folded_].location != NSNotFound;
        }
        return NO;
    }
};
}
