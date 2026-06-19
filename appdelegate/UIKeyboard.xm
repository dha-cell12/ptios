#include "UIKeyboard.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CFMessagePort.h>
#import <Foundation/NSDistributedNotificationCenter.h>
#import <execinfo.h>
#import <mach-o/dyld.h>
#include <substrate.h>

#define INSERT_TEXT 1
#define VIRTUAL_KEYBOARD 2
#define MOVE_CURSOR 3
#define DELETE_CHARACTER 4
#define PASTE_FROM_CLIPBOARD 5

#define TEST 99

#define VIRTUAL_KEYBOARD_HIDE 1
#define VIRTUAL_KEYBOARD_SHOW 2


@interface UIKeyboardImpl : UIView
	+ (id)sharedInstance;
	+ (id)activeInstance;
	- (void)insertText:(id)arg1;
	- (void)hideKeyboard;
    - (void)showKeyboard;
	- (void)clearDelegate;
	- (void)clearInput;
	- (void)moveSelectionToEndOfWord;
	- (void)moveCursorByAmount:(long long)arg1;
	- (void)deleteFromInput;
	- (void)clearSelection;
    - (void)deleteBackward;
 	- (void)setSelectionWithPoint:(struct CGPoint)arg1;
    - (id)markedText;
    - (void)unmarkText;
    - (void)clearSelection;
    - (void)setInputPoint:(struct CGPoint)arg1;
    - (_Bool)hasMarkedText;

 	@property (readonly, assign, nonatomic) UIResponder <UITextInput> *inputDelegate;
@end


%hook UIKeyboardImpl

    - (id)initWithFrame:(CGRect)arg1 forCustomInputView:(UIView*)view
    {
		NSDistributedNotificationCenter *center = [NSDistributedNotificationCenter defaultCenter];
		[center addObserver: self
					selector: @selector(handleKeyboardNotification:)
					name: @"com.tlinkauto.tlinkauto.keyboardcontrol"
					object: nil];

		//NSLog(@"com.tlinkauto.appdelegate: UIKeyboardImpl instance allocated");
		return %orig;
    }

	- (id)initWithFrame:(CGRect)arg1 {
		NSDistributedNotificationCenter *center = [NSDistributedNotificationCenter defaultCenter];
		[center addObserver: self
					selector: @selector(handleKeyboardNotification:)
					name: @"com.tlinkauto.tlinkauto.keyboardcontrol"
					object: nil];

		//NSLog(@"com.tlinkauto.appdelegate: UIKeyboardImpl instance allocated");
		return %orig;
	}

	- (void)dealloc {
        [[NSDistributedNotificationCenter defaultCenter] removeObserver:self name:@"com.tlinkauto.tlinkauto.textinput" object:nil];
		//NSLog(@"com.tlinkauto.appdelegate: UIKeyboardImpl instance deallocated");
		return %orig;
	}

    %new
	- (void)handleKeyboardNotification:(NSNotification *)notification {
		//NSLog(@"com.tlinkauto.appdelegate: keyboard related notification received. %@", notification);
		NSDictionary *data = (NSDictionary*)notification.userInfo;

        int taskId = [data[@"task_id"] intValue];
		if (taskId == INSERT_TEXT)
		{
            dispatch_async(dispatch_get_main_queue(), ^{
                [self insertText:data[@"task_content"]];
                NSLog(@"com.tlinkauto.appdelegate: insert text: %@", data[@"task_content"]);
            });
		}
        else if (taskId == VIRTUAL_KEYBOARD)
        {
            int status = [data[@"task_content"] intValue];
            if (status == VIRTUAL_KEYBOARD_HIDE)
            {
                [self hideKeyboard];
                NSLog(@"com.tlinkauto.appdelegate: hide keyboard");
            }
            else if (status == VIRTUAL_KEYBOARD_SHOW)
            {
                [self showKeyboard];
                NSLog(@"com.tlinkauto.appdelegate: show keyboard");
            }
            else
            {
                NSLog(@"com.tlinkauto.appdelegate: task id is virtual_keyboard but unknown task content. Task content: %d", status);
            }
        }
        else if (taskId == MOVE_CURSOR)
        {
            long long moveAmount = [data[@"task_content"] longLongValue];
            [self moveCursorByAmount:moveAmount];
            NSLog(@"com.tlinkauto.appdelegate: move cursor by amount: %lld", moveAmount);
        }
        else if (taskId == DELETE_CHARACTER)
        {
            int numOfCharacterToDel = [data[@"task_content"] intValue];
            for (int i = 0; i < numOfCharacterToDel; i++)
            {
                [self deleteBackward];
            }
            NSLog(@"com.tlinkauto.appdelegate: delete characters by amount: %d", numOfCharacterToDel);
        }
        else if (taskId == PASTE_FROM_CLIPBOARD)
        {
            UIPasteboard *pb = [UIPasteboard generalPasteboard];
            [self insertText:[pb string]];
        }
	}

%end