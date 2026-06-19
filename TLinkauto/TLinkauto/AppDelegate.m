//
//  AppDelegate.m
//  TLinkauto
//
//  Created by Jason on 2020/12/10.
//

#import "AppDelegate.h"

static void TLinkautoAppLog(NSString *message) {
    NSString *dir = @"/var/mobile/Library/TLinkauto";
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [dir stringByAppendingPathComponent:@"app.log"];
    NSString *line = [NSString stringWithFormat:@"%@\n", message];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
        [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    [handle seekToEndOfFile];
    [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

@interface AppDelegate ()
{

}

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    TLinkautoAppLog(@"AppDelegate didFinishLaunching");
    // Override point for customization after application launch.

    if (@available(iOS 13.0, *)) {
        _window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    }
    
    if (@available(iOS 13.0, *)) {
        if ([_window respondsToSelector:NSSelectorFromString(@"overrideUserInterfaceStyle")]) {
            [_window setValue:@(UIUserInterfaceStyleLight) forKey:@"overrideUserInterfaceStyle"];
        }
    }
    
    return YES;
}


#pragma mark - UISceneSession lifecycle


- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    // Called when a new scene session is being created.
    // Use this method to select a configuration to create the new scene with.
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}


- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
    // Called when the user discards a scene session.
    // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
    // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
}


@end
