#include "RuntimeUtils.h"
#include "Common.h"
#include <CoreFoundation/CoreFoundation.h>
#include "headers/CFUserNotification.h"

static NSString *lastDialogValue = @"";

static NSString *lastScriptError = @"";
static long long lastScriptErrorTs = 0;

static NSString *zx_trimErrorString(NSString *s)
{
    if (!s) return @"";
    NSString *out = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([out hasPrefix:@"-1;;"]) {
        out = [out substringFromIndex:4];
        out = [out stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    // Truncate to 200 characters.
    if ([out length] > 200) {
        out = [out substringToIndex:200];
    }
    return out;
}

void setLastScriptError(NSString *message)
{
    NSString *m = zx_trimErrorString(message);
    if (!m || [m length] == 0) {
        return;
    }
    lastScriptError = m;
    lastScriptErrorTs = (long long)[[NSDate date] timeIntervalSince1970];
}

NSString* getLastScriptError(void)
{
    return lastScriptError ?: @"";
}

long long getLastScriptErrorTs(void)
{
    return lastScriptErrorTs;
}

NSString* dialogFromRawData(UInt8 *eventData, NSError **error)
{
    NSArray *data = [[NSString stringWithUTF8String:(char*)eventData] componentsSeparatedByString:@";;"];
    NSString *title = data.count > 0 ? data[0] : @"ZXTouch";
    NSString *message = data.count > 1 ? data[1] : @"";
    NSString *ok = data.count > 2 ? data[2] : @"OK";
    NSString *cancel = data.count > 3 ? data[3] : @"Cancel";

    CFOptionFlags response = 0;
    CFUserNotificationDisplayAlert(0,
                                   kCFUserNotificationNoteAlertLevel,
                                   NULL,
                                   NULL,
                                   NULL,
                                   (__bridge CFStringRef)title,
                                   (__bridge CFStringRef)message,
                                   (__bridge CFStringRef)ok,
                                   (__bridge CFStringRef)cancel,
                                   NULL,
                                   &response);

    lastDialogValue = [NSString stringWithFormat:@"%ld", (long)response];
    return lastDialogValue;
}

NSString* clearDialogValues(NSError **error)
{
    lastDialogValue = @"";
    return @"";
}

NSString* rootDirValue(void)
{
    return getDocumentRoot();
}

NSString* currentDirValue(void)
{
    return getDocumentRoot();
}

NSString* botPathValue(void)
{
    return getScriptsFolder();
}
