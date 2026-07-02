//
//  AdderPopOverViewController.m
//  TLinkauto
//
//  Created by Jason on 2021/1/16.
//

#import "AdderPopOverViewController.h"
#import "Util.h"

@interface AdderPopOverViewController ()

@end

@implementation AdderPopOverViewController
{
    NSString *currentFolder;
    ScriptListViewController *upperLevel;
}


- (UIModalPresentationStyle) adaptivePresentationStyleForPresentationController: (UIPresentationController * ) controller {
    return UIModalPresentationNone;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.preferredContentSize = CGSizeMake(300, 100);
    // Do any additional setup after loading the view from its nib.
}

- (void)setFolder:(NSString*)path {
    currentFolder = [path stringByStandardizingPath];
}

- (void)setUpperLevelViewController:(ScriptListViewController*)vc{
    upperLevel = vc;
}

- (IBAction)createScriptButtonClick:(id)sender {
    if (!self->currentFolder)
    {
        [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:NSLocalizedString(@"createScriptPathNotSet", nil) buttonString:@"OK"];
        return;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Script Name"
                                                                    message:@"Please enter the script name"
                                                             preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *submit = [UIAlertAction actionWithTitle:@"Submit" style:UIAlertActionStyleDefault
                                                   handler:^(UIAlertAction * action) {
                                                       if (alert.textFields.count > 0) {
                                                           UITextField *textField = [alert.textFields firstObject];
                                                           if ([textField.text length] != 0)
                                                           {
                                                               // create folder
                                                               BOOL isDir;
                                                               NSError *err = nil;
                                                               NSFileManager *fileManager= [NSFileManager defaultManager];
                                                                NSString* folderToAddPath = [self->currentFolder stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.tl", textField.text]];
                                                               if([fileManager fileExistsAtPath:folderToAddPath isDirectory:&isDir] && isDir)
                                                               {
                                                                   [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:NSLocalizedString(@"createScriptAlreadyExists", nil) buttonString:@"OK"];
                                                               }
                                                               else
                                                               {
                                                                   [fileManager createDirectoryAtPath:folderToAddPath withIntermediateDirectories:YES attributes:nil error:&err];
                                                                   if (err)
                                                                   {
                                                                       [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:[NSString stringWithFormat:@"%@%@", NSLocalizedString(@"createScriptFailed", nil), err] buttonString:@"OK"];
                                                                   }
                                                                   
                                                                    // add plist file
                                                                    NSDictionary *scriptInfo = @{@"Entry": @"main.js", @"FrontApp": @"", @"Orientation": @"1"};
                                                                    NSString *plistPath = [folderToAddPath stringByAppendingPathComponent:@"info.plist"];
                                                                    [scriptInfo writeToFile:plistPath atomically:YES];

                                                                    NSDictionary *manifest = @{
                                                                        @"runtime": @"javascriptcore",
                                                                        @"entry": @"main.js",
                                                                        @"apiVersion": @1,
                                                                        @"coordinateSpace": @"native-pixels"
                                                                    };
                                                                    NSData *manifestData = [NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:&err];
                                                                    if (manifestData) {
                                                                        NSString *manifestPath = [folderToAddPath stringByAppendingPathComponent:@"manifest.json"];
                                                                        [manifestData writeToFile:manifestPath atomically:YES];
                                                                    }

                                                                    // add JavaScript file
                                                                    NSDateFormatter *dateFormatter=[[NSDateFormatter alloc] init];
                                                                    [dateFormatter setDateFormat:@"MM/dd/yyyy hh:mm:ss"];
                                                                    NSString *currentDateTime = [dateFormatter stringFromDate:[NSDate date]];
                                                                    NSString *initContent = [NSString stringWithFormat:@"// This script is created at %@\nconsole.log(\"TLinkauto script started\");\ndevice.toast(\"Hello from TLinkauto JS\", { type: 4, duration: 2 });\n", currentDateTime];

                                                                    [initContent writeToFile:[folderToAddPath stringByAppendingPathComponent:@"main.js"] atomically:YES encoding:NSUTF8StringEncoding error:&err];
                                                                   if (err)
                                                                   {
                                                                       [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:[NSString stringWithFormat:@"%@%@", NSLocalizedString(@"createScriptFailed", nil), err] buttonString:@"OK"];
                                                                   }
                                                                   dispatch_async(dispatch_get_main_queue(), ^{
                                                                       [self->upperLevel refreshTable];
                                                                   });
                                                               }
                                                               
                                                           }
                                                           else
                                                           {
                                                               [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:NSLocalizedString(@"createScriptEmptyName", nil) buttonString:@"OK"];
                                                           }
                                                       }
                                                   }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleDefault
                                                   handler:^(UIAlertAction * action) {}];

    [alert addAction:cancel];
    [alert addAction:submit];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        //textField.placeholder = @""; // if needs
    }];

    [self presentViewController:alert animated:YES completion:nil];
    
    
}

- (IBAction)createFolderButtonClick:(id)sender {
    if (!self->currentFolder)
    {
        [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:NSLocalizedString(@"createFolderPathNotSet", nil) buttonString:@"OK"];
        return;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Folder Name"
                                                                    message:@"Please enter the folder name"
                                                             preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *submit = [UIAlertAction actionWithTitle:@"Submit" style:UIAlertActionStyleDefault
                                                   handler:^(UIAlertAction * action) {
                                                       if (alert.textFields.count > 0) {
                                                           UITextField *textField = [alert.textFields firstObject];
                                                           if ([textField.text length] != 0)
                                                           {

                                                               // create folder
                                                               BOOL isDir;
                                                               NSError *err = nil;
                                                               NSFileManager *fileManager= [NSFileManager defaultManager];
                                                               NSString* folderToAddPath = [self->currentFolder stringByAppendingPathComponent:textField.text];
                                                               if([fileManager fileExistsAtPath:folderToAddPath isDirectory:&isDir] && isDir)
                                                               {
                                                                   [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:NSLocalizedString(@"createFolderAlreadyExists", nil) buttonString:@"OK"];
                                                               }
                                                               else
                                                               {
                                                                   [fileManager createDirectoryAtPath:folderToAddPath withIntermediateDirectories:YES attributes:nil error:&err];
                                                                   if (err)
                                                                   {
                                                                       [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:[NSString stringWithFormat:@"%@%@", NSLocalizedString(@"createFolderFailed", nil), err] buttonString:@"OK"];
                                                                   }
                                                                   dispatch_async(dispatch_get_main_queue(), ^{
                                                                       [self->upperLevel refreshTable];
                                                                   });
                                                               }
                                                               
                                                           }
                                                           else
                                                           {
                                                               [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:NSLocalizedString(@"createFolderEmptyName", nil) buttonString:@"OK"];
                                                           }
                                                       }
                                                   }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleDefault
                                                   handler:^(UIAlertAction * action) {}];

    [alert addAction:cancel];
    [alert addAction:submit];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        //textField.placeholder = @""; // if needs
    }];

    [self presentViewController:alert animated:YES completion:nil];
}
@end
