#ifndef RUNTIME_UTILS_H
#define RUNTIME_UTILS_H

#import <Foundation/Foundation.h>

NSString* dialogFromRawData(UInt8 *eventData, NSError **error);
NSString* clearDialogValues(NSError **error);
NSString* rootDirValue(void);
NSString* currentDirValue(void);
NSString* botPathValue(void);

// Script status (last error)
void setLastScriptError(NSString *message);
NSString* getLastScriptError(void);
long long getLastScriptErrorTs(void);

#endif

static inline BOOL TLinkautoJSIsFiniteNumber(double value) {
    return isfinite(value);
}

static inline int TLinkautoJSIntOption(NSDictionary *options, NSString *key, int defaultValue) {
    if (!options || ![options isKindOfClass:[NSDictionary class]]) return defaultValue;
    id val = options[key];
    if ([val respondsToSelector:@selector(intValue)]) return [val intValue];
    return defaultValue;
}

static inline double TLinkautoJSDoubleOption(NSDictionary *options, NSString *key, double defaultValue) {
    if (!options || ![options isKindOfClass:[NSDictionary class]]) return defaultValue;
    id val = options[key];
    if ([val respondsToSelector:@selector(doubleValue)]) return [val doubleValue];
    return defaultValue;
}

static inline NSString *TLinkautoJSStringOption(NSDictionary *options, NSString *key, NSString *defaultValue) {
    if (!options || ![options isKindOfClass:[NSDictionary class]]) return defaultValue;
    id val = options[key];
    if ([val isKindOfClass:[NSString class]]) return val;
    if ([val respondsToSelector:@selector(stringValue)]) return [val stringValue];
    return defaultValue;
}

static inline NSString *TLinkautoJSSafeStringPart(NSArray *parts, NSUInteger index) {
    if (!parts || index >= parts.count) return @"0";
    id val = parts[index];
    if ([val isKindOfClass:[NSString class]]) return val;
    if ([val respondsToSelector:@selector(stringValue)]) return [val stringValue];
    return @"0";
}

static inline NSString *TLinkautoJSSanitizeProtocolText(NSString *text, NSUInteger maxLength) {
    NSString *safe = [text isKindOfClass:[NSString class]] ? text : [text description];
    safe = safe ?: @"";
    safe = [safe stringByReplacingOccurrencesOfString:@";;" withString:@"; "];
    safe = [safe stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
    safe = [safe stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    if (safe.length > maxLength) safe = [safe substringToIndex:maxLength];
    return safe;
}

static inline bool TLinkautoJSStringContainsAny(NSString *string, NSArray<NSString *> *substrings) {
    if (!string || !substrings) return false;
    for (NSString *sub in substrings) {
        if ([string rangeOfString:sub].location != NSNotFound) return true;
    }
    return false;
}
