#import "AppDelegate.h"
#import "ScriptsViewController.h"
#import "SettingsViewController.h"
#import "ViewController.h"

// ---------------------------------------------------------------------------
// SCAppDelegate
//
// Stands up the window + navigation controller and forces light mode to match
// the Tlinkauto app's visual style. The supervisor is created/owned by the
// root view controller so its lifecycle is tied to the UI.
// ---------------------------------------------------------------------------

@implementation SCAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    (void)launchOptions;

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    SCScriptsViewController *scripts = [[SCScriptsViewController alloc] initWithScriptsPath:@"/var/mobile/Library/TLinkauto/scripts"];
    SCViewController *service = [[SCViewController alloc] init];
    SCSettingsViewController *settings = [[SCSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];

    UINavigationController *scriptsNav = [[UINavigationController alloc] initWithRootViewController:scripts];
    UINavigationController *serviceNav = [[UINavigationController alloc] initWithRootViewController:service];
    UINavigationController *settingsNav = [[UINavigationController alloc] initWithRootViewController:settings];

    scriptsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Scripts"
                                                          image:[UIImage systemImageNamed:@"list.dash"]
                                                            tag:0];
    serviceNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Service"
                                                          image:[UIImage systemImageNamed:@"dot.radiowaves.left.and.right"]
                                                            tag:1];
    settingsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Settings"
                                                           image:[UIImage systemImageNamed:@"gearshape"]
                                                             tag:2];

    UITabBarController *tabs = [[UITabBarController alloc] init];
    tabs.viewControllers = @[scriptsNav, serviceNav, settingsNav];
    tabs.selectedIndex = 1;

    if (@available(iOS 13.0, *)) {
        self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    }

    self.window.rootViewController = tabs;
    [self.window makeKeyAndVisible];

    return YES;
}

@end
