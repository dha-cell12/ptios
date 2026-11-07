#pragma once
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include <objc/runtime.h>
#include "TLinkAXSelectorPolicy.h"
#include "TLinkAXSelectorMode.h"

namespace TLinkAXSelectorPlan {
inline bool Admit(NSString *text) {
    return TLinkAXSelectorPolicy::AdmitUTF16(text.length) &&
        TLinkAXSelectorPolicy::AdmitUTF8([text lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
}

inline bool CopyIdentity(NSString *text) {
    if(!text)return false;
    @autoreleasepool {
        @try { try {
            NSString *snapshot = [text copy];
            return snapshot==text;
        } catch(...) { return false; } }
        @catch(NSException *exception) { (void)exception;return false; }
    }
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
        if (known && type == known) {
            if(![text isKindOfClass:[NSMutableString class]])return true;
            // A known class may have mutable ancestry even for an immutable
            // instance. NSCopying identity qualifies that instance only.
            return CopyIdentity(text);
        }
    }
    return false;
}

inline NSString *Fold(NSString *text) { return [text lowercaseString]; }

class Text;
class Mode {
    friend class Text;
    __strong NSString *value_;
    TLinkAXSelectorMode::State state_;
    bool stable(){return state_.stable([&]{return StableString(value_);});}
    TLinkAXSelectorMode::Kind kind(){
        return state_.kind([&](TLinkAXSelectorMode::Kind value){
            if(value==TLinkAXSelectorMode::Kind::Exact)return [value_ isEqualToString:@"exact"];
            return [value_ isEqualToString:@"prefix"];
        });
    }
public:
    explicit Mode(NSString *value):value_(value){}
    Mode(const Mode &)=delete;Mode &operator=(const Mode &)=delete;
};

class Text {
    __strong NSString *expected_, *folded_;
    Mode ownedMode_;
    Mode *mode_;
    bool caseSensitive_, checked_ = false, fast_ = false, prepared_ = false;
public:
    Text(NSString *expected, NSString *mode, BOOL caseSensitive)
        : expected_(expected), folded_(nil), ownedMode_(mode), mode_(&ownedMode_), caseSensitive_(caseSensitive) {}
    // The borrowed mode must outlive this noncopyable plan.
    Text(NSString *expected,Mode &mode,BOOL caseSensitive)
        : expected_(expected), folded_(nil), ownedMode_(nil), mode_(&mode), caseSensitive_(caseSensitive) {}
    Text(const Text &) = delete;
    Text &operator=(const Text &) = delete;
    template<class Compatibility>
    BOOL accepts(NSString *candidate, Compatibility compatibility) {
        if (!checked_) {
            fast_ = StableString(expected_) && mode_->stable();
            checked_ = true;
        }
        if (!fast_) return compatibility(candidate, expected_, mode_->value_, caseSensitive_);
        if (expected_.length == 0) return YES;
        NSString *left = candidate ?: @"";
        // Keep candidate normalization and its reached faults on every call,
        // including value after a label match; only immutable selector work is reused.
        if (!caseSensitive_) left = Fold(left);
        if (!prepared_) {
            folded_ = caseSensitive_ ? expected_ : Fold(expected_);
            prepared_ = true;
        }
        switch (mode_->kind()) {
            case TLinkAXSelectorMode::Kind::Exact: return [left isEqualToString:folded_];
            case TLinkAXSelectorMode::Kind::Prefix: return [left hasPrefix:folded_];
            case TLinkAXSelectorMode::Kind::Contains: return [left rangeOfString:folded_].location != NSNotFound;
        }
        return NO;
    }
};
}
