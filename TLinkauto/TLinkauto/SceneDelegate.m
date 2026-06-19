//
//  SceneDelegate.m
//  TLinkauto
//
//  Created by Jason on 2020/12/10.
//

#import "SceneDelegate.h"

static void TLinkautoSceneLog(NSString *message) {
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

@interface SceneDelegate ()

@end

@implementation SceneDelegate


- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    TLinkautoSceneLog(@"SceneDelegate willConnectToSession");
    // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
    // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
    // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).
    if (![scene isKindOfClass:[UIWindowScene class]]) {
        return;
    }

    if (self.window && self.window.rootViewController) {
        return;
    }

    UIWindowScene *windowScene = (UIWindowScene *)scene;
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:windowScene];

    UIViewController *rootViewController = nil;
    @try {
        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
        rootViewController = [storyboard instantiateInitialViewController];
        TLinkautoSceneLog(rootViewController ? @"Main storyboard loaded" : @"Main storyboard returned nil root");
    } @catch (NSException *exception) {
        TLinkautoSceneLog([NSString stringWithFormat:@"Main storyboard exception: %@", exception]);
        NSLog(@"[TLinkauto] failed to load Main storyboard: %@", exception);
    }

    if (!rootViewController) {
        UIViewController *fallback = [[UIViewController alloc] init];
        fallback.view.backgroundColor = [UIColor whiteColor];
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.text = @"TLinkauto loaded. Main storyboard failed to load.";
        label.textColor = [UIColor blackColor];
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 0;
        [fallback.view addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:fallback.view.leadingAnchor constant:24],
            [label.trailingAnchor constraintEqualToAnchor:fallback.view.trailingAnchor constant:-24],
            [label.centerYAnchor constraintEqualToAnchor:fallback.view.centerYAnchor]
        ]];
        rootViewController = fallback;
    }

    window.rootViewController = rootViewController;
    self.window = window;
    [window makeKeyAndVisible];
    TLinkautoSceneLog(@"Window made key and visible");
}


- (void)sceneDidDisconnect:(UIScene *)scene {
    // Called as the scene is being released by the system.
    // This occurs shortly after the scene enters the background, or when its session is discarded.
    // Release any resources associated with this scene that can be re-created the next time the scene connects.
    // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
}


- (void)sceneDidBecomeActive:(UIScene *)scene {
    // Called when the scene has moved from an inactive state to an active state.
    // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
}


- (void)sceneWillResignActive:(UIScene *)scene {
    // Called when the scene will move from an active state to an inactive state.
    // This may occur due to temporary interruptions (ex. an incoming phone call).
}


- (void)sceneWillEnterForeground:(UIScene *)scene {
    // Called as the scene transitions from the background to the foreground.
    // Use this method to undo the changes made on entering the background.
}


- (void)sceneDidEnterBackground:(UIScene *)scene {
    // Called as the scene transitions from the foreground to the background.
    // Use this method to save data, release shared resources, and store enough scene-specific state information
    // to restore the scene back to its current state.
}


@end
