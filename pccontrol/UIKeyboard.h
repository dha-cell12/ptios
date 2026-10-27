#ifndef UIKeyboard_H
#define UIKeyboard_H

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NSString* inputTextFromRawData(UInt8 *eventData, NSError **error);
NSString *TLinkReadClipboardText(void);
void TLinkWriteClipboardText(NSString *text);

#endif