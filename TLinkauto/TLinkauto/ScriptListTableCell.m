//
//  ScriptListTableCell.m
//  TLinkauto
//
//  Created by Jason on 2020/12/14.
//

#import "ScriptListTableCell.h"
#import "Socket.h"
#import "Util.h"
#import "TLinkAppDiagnostic.h"
#import "../../shared/TLinkLicenseVerifier.h"

@implementation ScriptListTableCell
{
    NSString* filePath;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    // Initialization code
}

- (IBAction)playButtonClick:(id)sender {
    NSString *licenseError = nil;
    if (!TLinkLicenseFeatureAllowed(@"script", &licenseError)) {
        UIViewController *parent = _parentViewController;
        if (parent) {
            [Util showAlertBoxWithOneOption:parent
                                      title:@"License Required"
                                    message:licenseError ?: @"The script feature is not enabled by this license."
                               buttonString:@"OK"];
        }
        return;
    }

    // Capture values needed by the block
    NSString *path = [filePath copy];
    __weak UIViewController *weakParent = _parentViewController;
    
    // Disable button immediately to prevent double-tap
    _playButton.enabled = NO;
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        Socket *springBoardSocket = [[Socket alloc] init];
        int connectResult = [springBoardSocket connect:@"127.0.0.1" byPort:6000];
        
        if (connectResult < 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_playButton.enabled = YES;
                UIViewController *parent = weakParent;
                if (parent) {
                    [Util showAlertBoxWithOneOption:parent title:@"Error" message:@"Cannot connect to SpringBoard socket." buttonString:@"OK"];
                }
            });
            return;
        }
        
        // Task 19 is fire-and-forget in tlinkautod. Waiting for recv here can
        // leave the Play button disabled forever because no reply is required.
        NSString *payload = [NSString stringWithFormat:@"19%@\r\n", path];
        [springBoardSocket send:payload];
        [springBoardSocket close];
        APP_DIAG("SCRIPT-PLAY", "queued path=%s", [path UTF8String]);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_playButton.enabled = YES;
        });
    });
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

- (void) setTitle:(NSString*)title{
    _scriptTitle.text = title;
}

- (void) hideButton{
    [_playButton setHidden:YES];
}

- (void) showButton{
    [_playButton setHidden:NO];
}

- (void) setPropertyWithPath:(NSString*)path{
    filePath = path;
    
    BOOL isDir = NO;
    _scriptTitle.text = [path lastPathComponent];
    [self showButton];

    if ([[path pathExtension] isEqualToString:@"tl"]) // is script. can play
    {
        // Now the image will have been loaded and decoded and is ready to rock for the main thread
        [[self imageView] setImage:[UIImage imageNamed:@"script-icon"]];
        
        return;
    }
    
    [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
    [self hideButton];

    if (!isDir)
    {
        [[self imageView] setImage:[UIImage imageNamed:@"normal-file-icon"]];
    }
    else
    {
        [[self imageView] setImage:[UIImage imageNamed:@"folder-icon"]];
    }
}

@end
