#include "UIKeyboard.h"
#import <Foundation/NSDistributedNotificationCenter.h>

#define TASK_GET_TEXT_FROM_CLIPBOARD 6
#define TASK_SAVE_TEXT_TO_CLIPBOARD 7
#define TASK_SAVE_IMAGE_TO_CLIPBOARD 8

static const unsigned long long kTLinkautoMaxClipboardImageBytes = 16ULL * 1024ULL * 1024ULL;

static NSError *TLinkautoKeyboardError(NSString *message)
{
    return [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;%@\r\n", message]}];
}

static NSString *TLinkautoPasteboardImageType(NSData *imageData)
{
    if ([imageData length] < 4) return nil;

    const unsigned char *bytes = (const unsigned char *)[imageData bytes];
    if ([imageData length] >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 && bytes[4] == 0x0D && bytes[5] == 0x0A && bytes[6] == 0x1A && bytes[7] == 0x0A) {
        return @"public.png";
    }
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
        return @"public.jpeg";
    }
    if ([imageData length] >= 6 && bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38) {
        return @"com.compuserve.gif";
    }
    if ([imageData length] >= 12 && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 && bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
        return @"org.webmproject.webp";
    }

    return nil;
}

NSString* inputTextFromRawData(UInt8 *eventData, NSError **error)
{
    NSArray *data = [[NSString stringWithUTF8String:(char*)eventData] componentsSeparatedByString:@";;"];

    NSString *taskContent = @"";
    if ([data count] < 1)
    {
        *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Keyboard related event length error. You have to specify the task id.\r\n"}];
        return nil;
    }
    int taskType = [data[0] intValue];
    if (taskType == TASK_GET_TEXT_FROM_CLIPBOARD)
    {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];

        if (!pasteboard.string)
            return @"";

        return pasteboard.string;
    }
    else if (taskType == TASK_SAVE_TEXT_TO_CLIPBOARD)
    {  
        if ([data count] < 2)
        {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Keyboard related event error. You have to specify the content you want to paste to clipboard.\r\n"}];
            return nil;
        }
        
        UIPasteboard *pb = [UIPasteboard generalPasteboard];
        pb.string = data[1];
        return @"";
    }
    else if (taskType == TASK_SAVE_IMAGE_TO_CLIPBOARD)
    {
        if ([data count] < 3)
        {
            *error = TLinkautoKeyboardError(@"Keyboard related event error. You have to specify image source type and file path.");
            return nil;
        }

        NSString *sourceType = data[1];
        if (![sourceType isEqualToString:@"file"])
        {
            *error = TLinkautoKeyboardError(@"Unsupported clipboard image source type. Only file is supported.");
            return nil;
        }

        NSString *imagePath = [[data subarrayWithRange:NSMakeRange(2, [data count] - 2)] componentsJoinedByString:@";;"];
        if ([imagePath length] == 0)
        {
            *error = TLinkautoKeyboardError(@"Clipboard image path cannot be empty.");
            return nil;
        }

        NSFileManager *fileManager = [NSFileManager defaultManager];
        BOOL isDirectory = NO;
        if (![fileManager fileExistsAtPath:imagePath isDirectory:&isDirectory] || isDirectory)
        {
            *error = TLinkautoKeyboardError(@"Clipboard image file does not exist.");
            return nil;
        }

        NSError *fileError = nil;
        NSDictionary *attributes = [fileManager attributesOfItemAtPath:imagePath error:&fileError];
        unsigned long long fileSize = [[attributes objectForKey:NSFileSize] unsignedLongLongValue];
        if (fileError || fileSize == 0)
        {
            *error = TLinkautoKeyboardError(@"Clipboard image file cannot be read or is empty.");
            return nil;
        }
        if (fileSize > kTLinkautoMaxClipboardImageBytes)
        {
            *error = TLinkautoKeyboardError(@"Clipboard image file is too large. Maximum size is 16MB.");
            return nil;
        }

        NSData *imageData = [NSData dataWithContentsOfFile:imagePath options:0 error:&fileError];
        if (fileError || !imageData)
        {
            *error = TLinkautoKeyboardError(@"Failed to read clipboard image file.");
            return nil;
        }

        NSString *pasteboardType = TLinkautoPasteboardImageType(imageData);
        if (!pasteboardType)
        {
            *error = TLinkautoKeyboardError(@"Unsupported clipboard image format. Use PNG, JPEG, GIF, or WebP.");
            return nil;
        }

        UIPasteboard *pb = [UIPasteboard generalPasteboard];
        pb.items = @[@{pasteboardType: imageData}];
        return @"";
    }

    // otherwise, send it to appdelegate
    if ([data count] == 2)
    {
        taskContent = data[1];
    }
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"com.tlinkauto.tlinkauto.keyboardcontrol" object:NULL userInfo:@{@"task_id": data[0], @"task_content": taskContent} deliverImmediately: true];
    return @"Successfully notify the appdelegate tweak. But not sure whether it works...";

}
