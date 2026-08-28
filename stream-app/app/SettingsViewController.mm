#import "SettingsViewController.h"
#import "BootScriptViewController.h"
#import "LicenseManager.h"
#import "LicenseLifecycleCoordinator.h"
#import "LicenseViewController.h"
#import "TLinkSocketClient.h"
#import "TLinkTheme.h"
#import "../../TLinkauto/TLinkauto/Settings/TLinkVPNSettingsViewController.h"
#import <Photos/Photos.h>
#import <UserNotifications/UserNotifications.h>

static NSString *const kTLinkSettingsConfigPath = @"/var/mobile/Library/TLinkauto/config/tweak/config.plist";
static NSString *const kTLinkScriptPlayConfigPath = @"/var/mobile/Library/TLinkauto/config/tweak/script_play_settings.plist";
static NSString *const kTLinkAppNotificationAuthorizationPath = @"/var/mobile/Library/TLinkauto/runtime/app_notification_authorization";
static NSString *const kTLinkBackgroundSchedulerDiagnosticsPath = @"/var/mobile/Library/TLinkauto/runtime/background_service_scheduler.plist";
static NSString *const kTLinkRemoteBridgeDiagnosticsPath = @"/var/mobile/Library/TLinkauto/runtime/remote_bridge.plist";
static NSString *const kTLinkWidgetBootDiagnosticsPath = @"/var/mobile/Library/TLinkauto/runtime/widget_boot_wake.plist";
static NSString *const kTLinkVolumeTriggerDiagnosticsPath = @"/var/mobile/Library/TLinkauto/runtime/volume_trigger.plist";
static NSString *const kTLinkUIServiceDiagnosticsPath = @"/var/mobile/Library/TLinkauto/runtime/uiservice_toast.plist";

@implementation SCSettingsViewController {
    NSArray<NSArray<NSString *> *> *_sections;
    UITextView *_resultView;
    NSMutableDictionary *_config;
    BOOL _debugMode;
}

- (instancetype)initWithStyle:(UITableViewStyle)style
{
    return [self initWithStyle:style debugMode:NO];
}

- (instancetype)initWithStyle:(UITableViewStyle)style debugMode:(BOOL)debugMode
{
    self = [super initWithStyle:style];
    if (self) {
        _debugMode = debugMode;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = _debugMode ? @"DEBUG" : @"Settings";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    if (self.navigationController) {
        self.navigationController.navigationBar.prefersLargeTitles = YES;
    }
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 58.0, 0, 0);
    [self loadConfig];
    NSArray<NSString *> *runtimeSettings = @[@"Touch Indicator", @"Switch App Before Playing", @"Double-click Popup", @"Enable Shell Task"];
    if (_debugMode) {
        _sections = @[
            @[@"Capability Probe", @"Hello Status", @"Script Status", @"Capture Probe", @"Native Tap Center", @"Color Pick Center", @"Color Search Smoke", @"Frame Capture", @"OCR Languages", @"App Info Self", @"Frontmost App", @"List Bundles", @"Open Preferences", @"Open Settings URL", @"Toast Overlay", @"Alert Box", @"Dialog Overlay", @"Clear Dialog", @"Touch Indicator On", @"Touch Indicator Off", @"Keep Awake On", @"Keep Awake Off", @"Set Auto Launch", @"List Auto Launch", @"Set Timer Demo", @"Remove Timer Demo", @"Legacy Stop Script", @"Update Cache", @"Start Touch Recording", @"Stop Touch Recording", @"Rapid Tap Center", @"Stop Tap Macro", @"Hardware Key Home", @"Wi-Fi Status", @"Bluetooth Status", @"Airplane Status", @"Cellular Status", @"VPN Status", @"Photo Access", @"Export Diagnostics", @"Notification Access", @"Background Service Status", @"Remote Bridge Status", @"Widget Boot Wake Status", @"Volume Trigger Status", @"Show Volume Menu Test", @"Toast UI Service Status", @"Show Background Toast Test"],
            runtimeSettings,
            @[@"Color/Image/Frame: active", @"Screenshot Album: Photos access required", @"Vision OCR: deferred; Tesseract active", @"Script Runtime: javascriptcore_mvp", @"Script Files: shared openFile handles", @"Scheduler: streamd_lite + autolaunch", @"Background Start: BGTaskScheduler best effort", @"Touch Recording: iohid raw replay", @"Tap Macro: bounded async native tap", @"Hardware Key: hid keyboard event", @"Connectivity: best effort private framework", @"VPN: app-side IKEv2 + on-demand", @"Shell: gated local sh", @"Visual Feedback: foreground overlay + background UI service", @"Toast: native hosted-plugin UI service with retry", @"Dialog: background CFUserNotification alert", @"Touch Indicator: foreground only", @"Keep Awake: daemon best effort", @"Service Mode: streamd-first + detached auxiliaries + clipboardd v16 + UI service v14", @"Volume Trigger: direct IOHID + system alert fallback", @"App/Process: helper launch/kill/url/respring", @"Keyboard: background clipboard + HID paste/edit", @"Activator: not required for volume trigger", @"Privhelper: open_kill_restart_ensure_respring"],
        ];
    } else {
        // Grouped like iOS Settings: Appearance · Account · Connectivity · Service · Runtime · Danger
        _sections = @[
            @[@"Appearance"],
            @[@"License"],
            @[@"Remote Bridge", @"Managed VPN"],
            @[@"Boot Script", @"Restart streamd", @"DEBUG"],
            runtimeSettings,
            @[@"Respring Device"],
        ];
    }

    CGFloat footerHeight = _debugMode ? 180.0 : 132.0;
    UIView *footerWrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, footerHeight)];
    footerWrap.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UIView *card = [TLinkTheme cardContainerView];
    card.frame = CGRectMake(16.0, 12.0, MAX(0.0, CGRectGetWidth(footerWrap.bounds) - 32.0), footerHeight - 20.0);
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [footerWrap addSubview:card];

    UILabel *statusCaption = [[UILabel alloc] initWithFrame:CGRectMake(14.0, 12.0, MAX(0.0, CGRectGetWidth(card.bounds) - 28.0), 16.0)];
    statusCaption.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    statusCaption.text = _debugMode ? @"DIAGNOSTICS" : @"SERVICE STATUS";
    statusCaption.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    statusCaption.textColor = [TLinkTheme subtleTextColor];
    [card addSubview:statusCaption];

    _resultView = [[UITextView alloc] initWithFrame:CGRectMake(10.0, 30.0, MAX(0.0, CGRectGetWidth(card.bounds) - 20.0), MAX(40.0, CGRectGetHeight(card.bounds) - 42.0))];
    _resultView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _resultView.editable = NO;
    _resultView.scrollEnabled = YES;
    _resultView.backgroundColor = [UIColor clearColor];
    _resultView.textContainerInset = UIEdgeInsetsMake(0, 0, 0, 0);
    _resultView.textContainer.lineFragmentPadding = 0;
    _resultView.font = [TLinkTheme logFont];
    _resultView.textColor = [UIColor secondaryLabelColor];
    _resultView.text = _debugMode ? @"Diagnostics will appear here." : @"Service status will appear here.";
    [card addSubview:_resultView];
    self.tableView.tableFooterView = footerWrap;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)loadConfig
{
    NSDictionary *loaded = [NSDictionary dictionaryWithContentsOfFile:kTLinkSettingsConfigPath];
    _config = loaded ? [loaded mutableCopy] : [NSMutableDictionary dictionary];

    NSMutableDictionary *touch = [_config[@"touch_indicator"] isKindOfClass:[NSDictionary class]]
        ? [_config[@"touch_indicator"] mutableCopy]
        : [NSMutableDictionary dictionary];
    if (!touch[@"show"]) touch[@"show"] = @NO;
    if (![touch[@"color"] isKindOfClass:[NSDictionary class]]) {
        touch[@"color"] = @{@"r": @255, @"g": @0, @"b": @0, @"alpha": @0.7};
    }
    _config[@"touch_indicator"] = touch;
    if (!_config[@"switch_app_before_run_script"]) _config[@"switch_app_before_run_script"] = @YES;
    if (!_config[@"double_click_volume_show_popup"]) _config[@"double_click_volume_show_popup"] = @YES;
    NSMutableDictionary *shell = [_config[@"shell"] isKindOfClass:[NSDictionary class]]
        ? [_config[@"shell"] mutableCopy]
        : [NSMutableDictionary dictionary];
    if (!shell[@"enabled"]) shell[@"enabled"] = @NO;
    _config[@"shell"] = shell;
    NSMutableDictionary *remote = [_config[@"remote_bridge"] isKindOfClass:[NSDictionary class]]
        ? [_config[@"remote_bridge"] mutableCopy]
        : [NSMutableDictionary dictionary];
    if (!remote[@"enabled"]) remote[@"enabled"] = @NO;
    if (![remote[@"url"] isKindOfClass:[NSString class]]) remote[@"url"] = @"";
    if (![remote[@"token"] isKindOfClass:[NSString class]]) remote[@"token"] = @"";
    _config[@"remote_bridge"] = remote;
}

- (void)editRemoteBridge
{
    NSDictionary *current = [_config[@"remote_bridge"] isKindOfClass:[NSDictionary class]] ? _config[@"remote_bridge"] : @{};
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Remote Bridge"
                                                                   message:@"Outbound WSS for Wi-Fi/5G. The endpoint should be the public bridge domain without an API path."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"wss://bridge.example.com";
        field.text = current[@"url"] ?: @"";
        field.keyboardType = UIKeyboardTypeURL;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Shared test token (16+ characters)";
        field.text = current[@"token"] ?: @"";
        field.secureTextEntry = YES;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Disable"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *action) {
        NSMutableDictionary *remote = [current mutableCopy];
        remote[@"enabled"] = @NO;
        self->_config[@"remote_bridge"] = remote;
        [self saveConfig];
        [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save & Enable"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        NSString *url = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *token = alert.textFields.count > 1 ? alert.textFields[1].text : @"";
        NSURL *parsed = [NSURL URLWithString:url];
        if (![[parsed.scheme lowercaseString] isEqualToString:@"wss"] || parsed.host.length == 0 || token.length < 16) {
            self->_resultView.text = @"Remote Bridge requires a wss:// URL and a token of at least 16 characters.";
            return;
        }
        self->_config[@"remote_bridge"] = @{
            @"enabled": @YES,
            @"url": url,
            @"token": token,
        };
        [self saveConfig];
        self->_resultView.text = @"Remote Bridge saved. streamd will connect within about 5 seconds.";
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)saveConfig
{
    NSString *parent = [kTLinkSettingsConfigPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:nil];
    BOOL ok = [_config writeToFile:kTLinkSettingsConfigPath atomically:YES];
    _resultView.text = ok ? [NSString stringWithFormat:@"Saved %@", kTLinkSettingsConfigPath] : @"Failed to save settings.";
}

- (BOOL)runtimeSettingEnabledAtRow:(NSInteger)row
{
    switch (row) {
        case 0:
            return [_config[@"touch_indicator"][@"show"] boolValue];
        case 1:
            return [_config[@"switch_app_before_run_script"] boolValue];
        case 2:
            return [_config[@"double_click_volume_show_popup"] boolValue];
        case 3:
            return [_config[@"shell"][@"enabled"] boolValue];
        default:
            return NO;
    }
}

- (NSString *)runtimeSettingDetailAtRow:(NSInteger)row
{
    switch (row) {
        case 0:
            return @"Show touch overlay events in foreground";
        case 1:
            return @"Saved for script compatibility";
        case 2:
            return @"Two short Volume Up clicks open Launch / Record / Cancel";
        case 3:
            return @"Run task 13/71 via local /bin/sh with timeout";
        default:
            return @"";
    }
}

- (UISwitch *)runtimeSwitchForRow:(NSInteger)row
{
    UISwitch *switchView = [[UISwitch alloc] initWithFrame:CGRectZero];
    switchView.tag = row;
    [switchView setOn:[self runtimeSettingEnabledAtRow:row] animated:NO];
    [switchView addTarget:self action:@selector(runtimeSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    return switchView;
}

- (void)runtimeSwitchChanged:(UISwitch *)switchView
{
    BOOL on = switchView.isOn;
    switch (switchView.tag) {
        case 0: {
            NSMutableDictionary *touch = [_config[@"touch_indicator"] mutableCopy] ?: [NSMutableDictionary dictionary];
            touch[@"show"] = @(on);
            _config[@"touch_indicator"] = touch;
            [self saveConfig];
            NSString *line = on ? @"261\n" : @"260\n";
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSString *response = [TLinkSocketClient sendLineAndRead:line timeout:4.0];
                dispatch_async(dispatch_get_main_queue(), ^{
                    self->_resultView.text = [NSString stringWithFormat:@"Touch Indicator %@\n%@", on ? @"On" : @"Off", response ?: @"<nil>"];
                });
            });
            break;
        }
        case 1:
            _config[@"switch_app_before_run_script"] = @(on);
            [self saveConfig];
            break;
        case 2:
            _config[@"double_click_volume_show_popup"] = @(on);
            [self saveConfig];
            break;
        case 3: {
            NSMutableDictionary *shell = [_config[@"shell"] mutableCopy] ?: [NSMutableDictionary dictionary];
            shell[@"enabled"] = @(on);
            _config[@"shell"] = shell;
            [self saveConfig];
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSString *line = [NSString stringWithFormat:@"90shell;;%d\n", on ? 1 : 0];
                NSString *response = [TLinkSocketClient sendLineAndRead:line timeout:4.0];
                dispatch_async(dispatch_get_main_queue(), ^{
                    self->_resultView.text = [NSString stringWithFormat:@"Shell Task %@\n%@", on ? @"Enabled" : @"Disabled", response ?: @"<nil>"];
                });
            });
            break;
        }
        default:
            break;
    }
}

- (void)exportDiagnostics
{
    _resultView.text = @"Exporting diagnostics...";
    NSMutableDictionary *redactedConfig = [_config mutableCopy] ?: [NSMutableDictionary dictionary];
    if ([redactedConfig[@"remote_bridge"] isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *remote = [redactedConfig[@"remote_bridge"] mutableCopy];
        if ([remote[@"token"] isKindOfClass:[NSString class]] && [remote[@"token"] length] > 0) {
            remote[@"token"] = @"<redacted>";
        }
        redactedConfig[@"remote_bridge"] = remote;
    }
    NSDictionary *configSnapshot = [redactedConfig copy];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableString *report = [NSMutableString string];
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss Z";
        [report appendFormat:@"TLinkauto TrollStore Diagnostics\n%@\n\n", [formatter stringFromDate:[NSDate date]]];
        [report appendFormat:@"config_path: %@\nconfig: %@\n\n", kTLinkSettingsConfigPath, configSnapshot];
        NSDictionary *playConfig = [NSDictionary dictionaryWithContentsOfFile:kTLinkScriptPlayConfigPath] ?: @{};
        [report appendFormat:@"play_config_path: %@\nplay_config: %@\n\n", kTLinkScriptPlayConfigPath, playConfig];
        NSDictionary *backgroundScheduler = [NSDictionary dictionaryWithContentsOfFile:kTLinkBackgroundSchedulerDiagnosticsPath] ?: @{};
        [report appendFormat:@"background_scheduler_path: %@\nbackground_scheduler: %@\n\n",
         kTLinkBackgroundSchedulerDiagnosticsPath, backgroundScheduler];
        NSDictionary *volumeTrigger = [NSDictionary dictionaryWithContentsOfFile:kTLinkVolumeTriggerDiagnosticsPath] ?: @{};
        [report appendFormat:@"volume_trigger_path: %@\nvolume_trigger: %@\n\n",
         kTLinkVolumeTriggerDiagnosticsPath, volumeTrigger];
        NSDictionary *uiService = [NSDictionary dictionaryWithContentsOfFile:kTLinkUIServiceDiagnosticsPath] ?: @{};
        [report appendFormat:@"toast_uiservice_path: %@\ntoast_uiservice: %@\n\n",
         kTLinkUIServiceDiagnosticsPath, uiService];
        NSDictionary *licenseStatus = [[SCLicenseManager sharedManager] localStatus] ?: @{};
        [report appendFormat:@"license_status: %@\n\n", licenseStatus];
        NSDictionary *licenseLifecycle = [[SCLicenseLifecycleCoordinator sharedCoordinator] diagnostics] ?: @{};
        [report appendFormat:@"license_lifecycle: %@\n\n", licenseLifecycle];

        NSArray<NSString *> *lines = @[@"97\n", @"60\n", @"75\n", @"98\n"];
        NSArray<NSString *> *labels = @[@"task97_capability", @"task60_status", @"task75_license", @"task98_capture_probe"];
        for (NSUInteger i = 0; i < lines.count; i++) {
            NSString *response = [TLinkSocketClient sendLineAndRead:lines[i] timeout:8.0];
            [report appendFormat:@"[%@]\n%@\n\n", labels[i], response ?: @"<nil>"];
        }

        NSString *dir = @"/var/mobile/Library/TLinkauto/diagnostics";
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSDateFormatter *nameFormatter = [[NSDateFormatter alloc] init];
        nameFormatter.dateFormat = @"yyyyMMdd-HHmmss";
        NSString *path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"diagnostics-%@.txt", [nameFormatter stringFromDate:[NSDate date]]]];
        NSError *err = nil;
        BOOL ok = [report writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_resultView.text = ok ? [NSString stringWithFormat:@"Diagnostics exported:\n%@", path] : (err.localizedDescription ?: @"diagnostics export failed");
        });
    });
}

- (NSString *)photoAuthorizationStatusText:(PHAuthorizationStatus)status
{
    switch (status) {
        case PHAuthorizationStatusNotDetermined: return @"not_determined";
        case PHAuthorizationStatusRestricted: return @"restricted";
        case PHAuthorizationStatusDenied: return @"denied";
        case PHAuthorizationStatusAuthorized: return @"authorized";
        case PHAuthorizationStatusLimited: return @"limited";
        default: return [NSString stringWithFormat:@"unknown_%ld", (long)status];
    }
}

- (void)confirmRespring
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Respring Device"
                                                                   message:@"SpringBoard will restart immediately. Unsaved work in foreground apps may be lost."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Respring"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *action) {
        self->_resultView.text = @"Requesting validated SpringBoard restart...";
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSString *response = [TLinkSocketClient requestTask:74 args:@[@"confirm"] timeout:6.0];
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_resultView.text = response.length > 0
                    ? [NSString stringWithFormat:@"Respring:\n%@", response]
                    : @"Respring signal sent; the connection may close while SpringBoard restarts.";
            });
        });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)restartStreamd
{
    _resultView.text = @"Restarting streamd...";
    [[NSNotificationCenter defaultCenter] postNotificationName:@"TLinkRestartStreamService"
                                                        object:self];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *response = [TLinkSocketClient requestTask:97 args:@[] timeout:4.0];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_resultView.text = response.length > 0
                ? [NSString stringWithFormat:@"Restart streamd:\n%@", response]
                : @"Restart requested, but tcp/6000 did not respond yet.";
        });
    });
}

- (void)requestPhotoAccess
{
    _resultView.text = @"Requesting Photos access...";
    void (^handler)(PHAuthorizationStatus) = ^(PHAuthorizationStatus status) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_resultView.text = [NSString stringWithFormat:@"Photos access: %@", [self photoAuthorizationStatusText:status]];
        });
    };
    if (@available(iOS 14.0, *)) {
        PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
        if (status == PHAuthorizationStatusNotDetermined) {
            [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:handler];
        } else {
            handler(status);
        }
    } else {
        PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
        if (status == PHAuthorizationStatusNotDetermined) {
            [PHPhotoLibrary requestAuthorization:handler];
        } else {
            handler(status);
        }
    }
}

- (NSString *)notificationAuthorizationStatusText:(UNAuthorizationStatus)status
{
    switch (status) {
        case UNAuthorizationStatusNotDetermined: return @"not_determined";
        case UNAuthorizationStatusDenied: return @"denied";
        case UNAuthorizationStatusAuthorized: return @"authorized";
        case UNAuthorizationStatusProvisional: return @"provisional";
        case UNAuthorizationStatusEphemeral: return @"ephemeral";
        default: return [NSString stringWithFormat:@"unknown_%ld", (long)status];
    }
}

- (void)persistNotificationAuthorizationStatus:(UNAuthorizationStatus)status
{
    NSString *directory = [kTLinkAppNotificationAuthorizationPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSString stringWithFormat:@"%ld", (long)status] writeToFile:kTLinkAppNotificationAuthorizationPath
                                                         atomically:NO
                                                           encoding:NSUTF8StringEncoding
                                                              error:nil];
}

- (void)requestNotificationAccess
{
    _resultView.text = @"Checking notification access...";
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        [self persistNotificationAuthorizationStatus:settings.authorizationStatus];
        if (settings.authorizationStatus == UNAuthorizationStatusNotDetermined) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert
                                      completionHandler:^(__unused BOOL granted, NSError *error) {
                    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *updated) {
                        [self persistNotificationAuthorizationStatus:updated.authorizationStatus];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            self->_resultView.text = [NSString stringWithFormat:@"Notification access: %@%@",
                                [self notificationAuthorizationStatusText:updated.authorizationStatus],
                                error ? [NSString stringWithFormat:@"\n%@", error.localizedDescription] : @""];
                        });
                    }];
                }];
            });
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_resultView.text = [NSString stringWithFormat:@"Notification access: %@",
                [self notificationAuthorizationStatusText:settings.authorizationStatus]];
            if (settings.authorizationStatus == UNAuthorizationStatusDenied) {
                NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
                if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            }
        });
    }];
}

- (void)applyAppearanceStyle:(TLinkAppearanceStyle)style
{
    [TLinkTheme setCurrentAppearanceStyle:style];
    UIWindow *window = self.view.window;
    if (!window) {
        for (UIWindow *candidate in [UIApplication sharedApplication].windows) {
            if (candidate.isKeyWindow) { window = candidate; break; }
        }
    }
    [TLinkTheme applyCurrentAppearanceStyleToWindow:window];
    [self.tableView reloadData];
    self->_resultView.text = [NSString stringWithFormat:@"Appearance set to %@", [TLinkTheme displayNameForAppearanceStyle:style]];
}

- (void)presentAppearancePicker
{
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Appearance"
                                                                 message:@"Choose how StreamControl looks."
                                                          preferredStyle:UIAlertControllerStyleActionSheet];
    TLinkAppearanceStyle current = [TLinkTheme currentAppearanceStyle];
    NSArray<NSNumber *> *styles = @[@(TLinkAppearanceStyleSystem), @(TLinkAppearanceStyleLight), @(TLinkAppearanceStyleDark)];
    for (NSNumber *styleNumber in styles) {
        TLinkAppearanceStyle style = (TLinkAppearanceStyle)styleNumber.integerValue;
        NSString *name = [TLinkTheme displayNameForAppearanceStyle:style];
        NSString *label = style == current ? [NSString stringWithFormat:@"%@ \u2713", name] : name;
        [sheet addAction:[UIAlertAction actionWithTitle:label
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            [self applyAppearanceStyle:style];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover) {
        popover.sourceView = self.tableView;
        popover.sourceRect = CGRectMake(CGRectGetMidX(self.tableView.bounds), CGRectGetMidY(self.tableView.bounds), 1.0, 1.0);
        popover.permittedArrowDirections = 0;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return (NSInteger)_sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)_sections[(NSUInteger)section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (!_debugMode) {
        switch (section) {
            case 0: return @"Appearance";
            case 1: return @"Account";
            case 2: return @"Connectivity";
            case 3: return @"Service";
            case 4: return @"Runtime Settings";
            case 5: return @"Danger Zone";
            default: return nil;
        }
    }
    if (section == 0) return @"Diagnostics";
    if (section == 1) return @"Runtime Settings";
    return @"TrollStore Compatibility";
}

- (UIImage *)tlink_settingsGlyphNamed:(NSString *)name background:(UIColor *)bg
{
    UIImage *symbol = [UIImage systemImageNamed:name];
    if (!symbol) return nil;
    CGFloat size = 30.0;
    CGRect rect = CGRectMake(0, 0, size, size);
    UIGraphicsBeginImageContextWithOptions(rect.size, NO, 0);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:8.0];
    [bg setFill];
    [path fill];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15.0 weight:UIImageSymbolWeightSemibold];
    UIImage *tinted = [[symbol imageByApplyingSymbolConfiguration:cfg] imageWithTintColor:[UIColor whiteColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
    CGSize s = tinted.size;
    [tinted drawInRect:CGRectMake((size - s.width) * 0.5, (size - s.height) * 0.5, s.width, s.height)];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out;
}

- (void)tlink_applySettingsChromeToCell:(UITableViewCell *)cell
{
    cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.numberOfLines = 2;
    cell.imageView.layer.cornerRadius = 8.0;
    cell.imageView.clipsToBounds = YES;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cellID = @"SettingsCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
    }
    NSString *title = _sections[(NSUInteger)indexPath.section][(NSUInteger)indexPath.row];
    cell.textLabel.text = title;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.text = nil;
    cell.imageView.image = nil;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    [self tlink_applySettingsChromeToCell:cell];

    BOOL isRuntimeSection = (!_debugMode && indexPath.section == 4) || (_debugMode && indexPath.section == 1);
    BOOL isCompatSection = _debugMode && indexPath.section == 2;

    if (isRuntimeSection) {
        cell.detailTextLabel.text = [self runtimeSettingDetailAtRow:indexPath.row];
        cell.accessoryView = [self runtimeSwitchForRow:indexPath.row];
        NSArray<NSString *> *runtimeIcons = @[ @"hand.tap.fill", @"arrow.left.arrow.right", @"speaker.wave.2.fill", @"terminal.fill" ];
        NSString *icon = indexPath.row >= 0 && indexPath.row < (NSInteger)runtimeIcons.count ? runtimeIcons[(NSUInteger)indexPath.row] : @"switch.2";
        cell.imageView.image = [self tlink_settingsGlyphNamed:icon background:[TLinkTheme accentColor]];
        return cell;
    }

    if (isCompatSection) {
        cell.detailTextLabel.text = @"Planned compatibility fallback";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    if (_debugMode) {
        cell.detailTextLabel.text = @"Tap to run";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.imageView.image = [self tlink_settingsGlyphNamed:@"hammer.fill" background:[UIColor systemGrayColor]];
        return cell;
    }

    // Non-debug action rows (any section except runtime/danger handled above/below)
    if ([title isEqualToString:@"Appearance"]) {
        cell.detailTextLabel.text = [TLinkTheme displayNameForAppearanceStyle:[TLinkTheme currentAppearanceStyle]];
        cell.imageView.image = [self tlink_settingsGlyphNamed:@"circle.lefthalf.filled" background:[TLinkTheme accentColor]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if ([title isEqualToString:@"License"]) {
        NSDictionary *status = [[SCLicenseManager sharedManager] localStatus];
        cell.detailTextLabel.text = status[@"state"] ?: @"unknown";
        cell.imageView.image = [self tlink_settingsGlyphNamed:@"key.fill" background:[UIColor systemOrangeColor]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if ([title isEqualToString:@"Remote Bridge"]) {
        NSDictionary *remote = [_config[@"remote_bridge"] isKindOfClass:[NSDictionary class]] ? _config[@"remote_bridge"] : @{};
        BOOL enabled = [remote[@"enabled"] boolValue];
        NSString *url = [remote[@"url"] isKindOfClass:[NSString class]] ? remote[@"url"] : @"";
        cell.detailTextLabel.text = enabled ? (url.length > 0 ? url : @"Enabled, not configured") : @"Disabled";
        cell.imageView.image = [self tlink_settingsGlyphNamed:@"network" background:[UIColor systemTealColor]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if ([title isEqualToString:@"Managed VPN"]) {
        cell.detailTextLabel.text = @"Experimental foreground IKEv2 control";
        cell.imageView.image = [self tlink_settingsGlyphNamed:@"lock.shield" background:[UIColor systemIndigoColor]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if ([title isEqualToString:@"Boot Script"]) {
        NSDictionary *boot = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/TLinkauto/config/tweak/boot_script.plist"];
        BOOL enabled = [boot[@"enabled"] boolValue];
        NSString *script = [boot[@"script"] isKindOfClass:[NSString class]] ? boot[@"script"] : @"";
        cell.detailTextLabel.text = enabled
            ? [NSString stringWithFormat:@"Enabled · %@", script.lastPathComponent ?: @"selected"]
            : (script.length > 0 ? [NSString stringWithFormat:@"Disabled · %@", script.lastPathComponent] : @"Choose the script to run after reboot");
        cell.imageView.image = [self tlink_settingsGlyphNamed:@"bolt.fill" background:[UIColor systemOrangeColor]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if ([title isEqualToString:@"Restart streamd"]) {
        cell.detailTextLabel.text = @"Replace and restart the task service";
        cell.imageView.image = [self tlink_settingsGlyphNamed:@"arrow.clockwise" background:[UIColor systemGreenColor]];
    } else if ([title isEqualToString:@"Respring Device"]) {
        cell.detailTextLabel.text = @"Restart SpringBoard immediately";
        cell.textLabel.textColor = [UIColor systemRedColor];
        cell.imageView.image = [self tlink_settingsGlyphNamed:@"power" background:[UIColor systemRedColor]];
    } else if ([title isEqualToString:@"DEBUG"]) {
        cell.detailTextLabel.text = @"Open diagnostics and compatibility tools";
        cell.imageView.image = [self tlink_settingsGlyphNamed:@"ladybug" background:[UIColor systemGrayColor]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    BOOL isRuntimeSection = (!_debugMode && indexPath.section == 4) || (_debugMode && indexPath.section == 1);
    if (isRuntimeSection) {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        UISwitch *switchView = [cell.accessoryView isKindOfClass:[UISwitch class]] ? (UISwitch *)cell.accessoryView : nil;
        if (!switchView) return;
        [switchView setOn:!switchView.isOn animated:YES];
        [self runtimeSwitchChanged:switchView];
        return;
    }
    if (_debugMode && indexPath.section != 0) return;

    NSString *title = _sections[(NSUInteger)indexPath.section][(NSUInteger)indexPath.row];
    if (!_debugMode) {
        if ([title isEqualToString:@"Appearance"]) {
            [self presentAppearancePicker];
        } else if ([title isEqualToString:@"License"]) {
            SCLicenseViewController *license = [[SCLicenseViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
            [self.navigationController pushViewController:license animated:YES];
        } else if ([title isEqualToString:@"Remote Bridge"]) {
            [self editRemoteBridge];
        } else if ([title isEqualToString:@"Managed VPN"]) {
            TLinkVPNSettingsViewController *vpn =
                [[TLinkVPNSettingsViewController alloc] init];
            [self.navigationController pushViewController:vpn animated:YES];
        } else if ([title isEqualToString:@"Boot Script"]) {
            SCBootScriptViewController *boot = [[SCBootScriptViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
            [self.navigationController pushViewController:boot animated:YES];
        } else if ([title isEqualToString:@"Restart streamd"]) {
            [self restartStreamd];
        } else if ([title isEqualToString:@"Respring Device"]) {
            [self confirmRespring];
        } else if ([title isEqualToString:@"DEBUG"]) {
            SCSettingsViewController *debug = [[SCSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped
                                                                                     debugMode:YES];
            [self.navigationController pushViewController:debug animated:YES];
        }
        return;
    }

    if ([title isEqualToString:@"Photo Access"]) {
        [self requestPhotoAccess];
        return;
    }

    if ([title isEqualToString:@"Notification Access"]) {
        [self requestNotificationAccess];
        return;
    }

    if ([title isEqualToString:@"Export Diagnostics"]) {
        [self exportDiagnostics];
        return;
    }

    if ([title isEqualToString:@"Background Service Status"]) {
        NSDictionary *status = [NSDictionary dictionaryWithContentsOfFile:kTLinkBackgroundSchedulerDiagnosticsPath];
        _resultView.text = status
            ? [NSString stringWithFormat:@"%@\n%@", kTLinkBackgroundSchedulerDiagnosticsPath, status]
            : @"No background scheduler diagnostics yet. Reopen StreamControl once to register and submit tasks.";
        return;
    }

    if ([title isEqualToString:@"Remote Bridge Status"]) {
        NSDictionary *status = [NSDictionary dictionaryWithContentsOfFile:kTLinkRemoteBridgeDiagnosticsPath];
        _resultView.text = status
            ? [NSString stringWithFormat:@"%@\n%@", kTLinkRemoteBridgeDiagnosticsPath, status]
            : @"No Remote Bridge diagnostics yet. Enable it in Settings and wait about 5 seconds.";
        return;
    }

    if ([title isEqualToString:@"Widget Boot Wake Status"]) {
        NSDictionary *status = [NSDictionary dictionaryWithContentsOfFile:kTLinkWidgetBootDiagnosticsPath];
        _resultView.text = status
            ? [NSString stringWithFormat:@"%@\n%@", kTLinkWidgetBootDiagnosticsPath, status]
            : @"No widget wake diagnostics yet. Enable Boot Script, add the TLinkauto Boot Wake widget, then wait for a timeline refresh.";
        return;
    }

    if ([title isEqualToString:@"Volume Trigger Status"]) {
        NSDictionary *status = [NSDictionary dictionaryWithContentsOfFile:kTLinkVolumeTriggerDiagnosticsPath];
        _resultView.text = @"Reading live clipboardd volume status...";
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSString *live = [TLinkSocketClient sendLineAndRead:@"249\n" timeout:4.0];
            NSString *decodedDaemon = @"<daemon diagnostic unavailable>";
            NSString *marker = @"daemon_diag_b64=";
            NSRange markerRange = [live rangeOfString:marker];
            if (live.length > 0 && markerRange.location != NSNotFound) {
                NSString *encoded = [[live substringFromIndex:NSMaxRange(markerRange)]
                    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
                NSString *decoded = decodedData
                    ? [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding]
                    : nil;
                if (decoded.length > 0) decodedDaemon = decoded;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_resultView.text = [NSString stringWithFormat:@"Live clipboardd:\n%@\n\nTask 249 envelope:\n%@\n\nPersisted %@\n%@",
                    decodedDaemon,
                    live ?: @"<no response>",
                    kTLinkVolumeTriggerDiagnosticsPath,
                    status ?: @"<none>"];
            });
        });
        return;
    }

    if ([title isEqualToString:@"Show Volume Menu Test"]) {
        _resultView.text = @"Requesting clipboardd system menu...";
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSString *response = [TLinkSocketClient sendLineAndRead:@"2410\n" timeout:4.0];
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_resultView.text = [NSString stringWithFormat:@"Volume menu test:\n%@", response ?: @"<no response>"];
            });
        });
        return;
    }

    if ([title isEqualToString:@"Toast UI Service Status"]) {
        NSDictionary *status = [NSDictionary dictionaryWithContentsOfFile:kTLinkUIServiceDiagnosticsPath];
        _resultView.text = @"Reading TLinkUIService live status...";
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSString *live = [TLinkSocketClient sendLineAndRead:@"2411\n" timeout:4.0];
            NSString *decodedProbe = @"<UI service probe unavailable>";
            NSString *marker = @"uiservice_probe_b64=";
            NSRange markerRange = [live rangeOfString:marker];
            if (live.length > 0 && markerRange.location != NSNotFound) {
                NSString *encoded = [[live substringFromIndex:NSMaxRange(markerRange)]
                    stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
                NSString *decoded = decodedData
                    ? [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding]
                    : nil;
                if (decoded.length > 0) decodedProbe = decoded;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_resultView.text = [NSString stringWithFormat:@"Live TLinkUIService:\n%@\n\nTask 2411 envelope:\n%@\n\nPersisted %@\n%@",
                    decodedProbe,
                    live ?: @"<no response>",
                    kTLinkUIServiceDiagnosticsPath,
                    status ?: @"<none>"];
            });
        });
        return;
    }

    if ([title isEqualToString:@"Show Background Toast Test"]) {
        _resultView.text = @"Requesting the standalone background toast service...";
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSString *response = [TLinkSocketClient sendLineAndRead:@"2412\n" timeout:4.0];
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_resultView.text = [NSString stringWithFormat:@"Background toast test:\n%@",
                    response ?: @"<no response>"];
            });
        });
        return;
    }

    if ([title isEqualToString:@"Respring Device"]) {
        [self confirmRespring];
        return;
    }

    if (indexPath.row == 32) {
        _resultView.text = @"Running hardware key home...";
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSString *down = [TLinkSocketClient sendLineAndRead:@"301;;1\n" timeout:4.0];
            [NSThread sleepForTimeInterval:0.08];
            NSString *up = [TLinkSocketClient sendLineAndRead:@"300;;1\n" timeout:4.0];
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_resultView.text = [NSString stringWithFormat:@"Home down:\n%@\nHome up:\n%@", down ?: @"<nil>", up ?: @"<nil>"];
            });
        });
        return;
    }

    NSString *line = nil;
    switch (indexPath.row) {
        case 0: line = @"97\n"; break;
        case 1: line = @"60\n"; break;
        case 2: line = @"60\n"; break;
        case 3: line = @"98\n"; break;
        case 4: {
            CGFloat scale = [UIScreen mainScreen].scale;
            CGSize size = [UIScreen mainScreen].bounds.size;
            int x = (int)(size.width * scale / 2.0);
            int y = (int)(size.height * scale / 2.0);
            line = [NSString stringWithFormat:@"62%d;;%d;;50;;0\n", x, y];
            break;
        }
        case 5: {
            CGFloat scale = [UIScreen mainScreen].scale;
            CGSize size = [UIScreen mainScreen].bounds.size;
            int x = (int)(size.width * scale / 2.0);
            int y = (int)(size.height * scale / 2.0);
            line = [NSString stringWithFormat:@"23%d;;%d\n", x, y];
            break;
        }
        case 6:
            line = @"281;;0;;0;;0;;0;;0;;255;;0;;255;;0;;255;;8\n";
            break;
        case 7:
            line = @"661;;1;;1000\n";
            break;
        case 8:
            line = @"272;;0\n";
            break;
        case 9: {
            NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
            line = [NSString stringWithFormat:@"33%@\n", bundleId];
            break;
        }
        case 10:
            line = @"34\n";
            break;
        case 11:
            line = @"530\n";
            break;
        case 12:
            line = @"11com.apple.Preferences\n";
            break;
        case 13:
            line = @"54App-Prefs:root=General\n";
            break;
        case 14:
            line = @"220;;Hello from TLinkauto overlay;;2;;2;;16\n";
            break;
        case 15:
            line = @"12TLinkauto;;Alert overlay is active;;3\n";
            break;
        case 16:
            line = @"42TLinkauto;;Dialog overlay is active;;OK;;Cancel\n";
            break;
        case 17:
            line = @"43\n";
            break;
        case 18:
            line = @"261\n";
            break;
        case 19:
            line = @"260\n";
            break;
        case 20:
            line = @"401\n";
            break;
        case 21:
            line = @"400\n";
            break;
        case 22:
            line = @"36demo;;Demo Script.tl;;1\n";
            break;
        case 23:
            line = @"37\n";
            break;
        case 24:
            line = @"38demo-timer;;5;;0;;Demo Script.tl\n";
            break;
        case 25:
            line = @"39demo-timer\n";
            break;
        case 26:
            line = @"41\n";
            break;
        case 27:
            line = @"902\n";
            break;
        case 28:
            line = @"14\n";
            break;
        case 29:
            line = @"15\n";
            break;
        case 30: {
            CGFloat scale = [UIScreen mainScreen].scale;
            CGSize size = [UIScreen mainScreen].bounds.size;
            int x = (int)(size.width * scale / 2.0);
            int y = (int)(size.height * scale / 2.0);
            line = [NSString stringWithFormat:@"17%d;;%d;;5;;100;;20;;0\n", x, y];
            break;
        }
        case 31:
            line = @"170\n";
            break;
        case 33:
            line = @"550\n";
            break;
        case 34:
            line = @"560\n";
            break;
        case 35:
            line = @"570\n";
            break;
        case 36:
            line = @"580\n";
            break;
        case 37:
            line = @"590\n";
            break;
        default: return;
    }

    _resultView.text = @"Running...";
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *response = [TLinkSocketClient sendLineAndRead:line timeout:8.0];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:@"TLinkVisualFeedbackNeedsPoll" object:nil];
            self->_resultView.text = response ?: @"<nil>";
        });
    });
}

@end
