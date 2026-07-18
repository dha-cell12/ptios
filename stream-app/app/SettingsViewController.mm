#import "SettingsViewController.h"
#import "LicenseManager.h"
#import "LicenseLifecycleCoordinator.h"
#import "LicenseViewController.h"
#import "TLinkSocketClient.h"
#import <Photos/Photos.h>
#import <UserNotifications/UserNotifications.h>

static NSString *const kTLinkSettingsConfigPath = @"/var/mobile/Library/TLinkauto/config/tweak/config.plist";
static NSString *const kTLinkScriptPlayConfigPath = @"/var/mobile/Library/TLinkauto/config/tweak/script_play_settings.plist";
static NSString *const kTLinkAppNotificationAuthorizationPath = @"/var/mobile/Library/TLinkauto/runtime/app_notification_authorization";
static NSString *const kTLinkBackgroundSchedulerDiagnosticsPath = @"/var/mobile/Library/TLinkauto/runtime/background_service_scheduler.plist";
static NSString *const kTLinkRemoteBridgeDiagnosticsPath = @"/var/mobile/Library/TLinkauto/runtime/remote_bridge.plist";

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
    [self loadConfig];
    NSArray<NSString *> *runtimeSettings = @[@"Touch Indicator", @"Switch App Before Playing", @"Double-click Popup", @"Enable Shell Task"];
    if (_debugMode) {
        _sections = @[
            @[@"Capability Probe", @"Hello Status", @"Script Status", @"Capture Probe", @"Native Tap Center", @"Color Pick Center", @"Color Search Smoke", @"Frame Capture", @"OCR Languages", @"App Info Self", @"Frontmost App", @"List Bundles", @"Open Preferences", @"Open Settings URL", @"Toast Overlay", @"Alert Box", @"Dialog Overlay", @"Clear Dialog", @"Touch Indicator On", @"Touch Indicator Off", @"Keep Awake On", @"Keep Awake Off", @"Set Auto Launch", @"List Auto Launch", @"Set Timer Demo", @"Remove Timer Demo", @"Legacy Stop Script", @"Update Cache", @"Start Touch Recording", @"Stop Touch Recording", @"Rapid Tap Center", @"Stop Tap Macro", @"Hardware Key Home", @"Wi-Fi Status", @"Bluetooth Status", @"Airplane Status", @"Cellular Status", @"VPN Status", @"Photo Access", @"Export Diagnostics", @"Notification Access", @"Background Service Status", @"Remote Bridge Status"],
            runtimeSettings,
            @[@"Color/Image/Frame: active", @"Screenshot Album: Photos access required", @"Vision OCR: deferred; Tesseract active", @"Script Runtime: javascriptcore_mvp", @"Script Files: shared openFile handles", @"Scheduler: streamd_lite + autolaunch", @"Background Start: BGTaskScheduler best effort", @"Touch Recording: iohid raw replay", @"Tap Macro: bounded async native tap", @"Hardware Key: hid keyboard event", @"Connectivity: best effort private framework", @"VPN: query only", @"Shell: gated local sh", @"Visual Feedback: foreground overlay + background system alert", @"Toast: foreground positioned, background fixed center", @"Dialog: background CFUserNotification alert", @"Touch Indicator: foreground only", @"Keep Awake: daemon best effort", @"Service Mode: helper ensure streamd + clipboardd v12", @"App/Process: helper launch/kill/url/respring", @"Keyboard: background clipboard + HID paste/edit", @"Activator: limited_on_trollstore", @"Privhelper: open_kill_restart_ensure_respring"],
        ];
    } else {
        _sections = @[
            @[@"License", @"Remote Bridge", @"Restart streamd", @"Respring Device", @"DEBUG"],
            runtimeSettings,
        ];
    }

    _resultView = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, _debugMode ? 180.0 : 120.0)];
    _resultView.editable = NO;
    _resultView.font = [UIFont fontWithName:@"Menlo" size:11.0] ?: [UIFont systemFontOfSize:11.0];
    _resultView.text = _debugMode ? @"Diagnostics will appear here." : @"Service status will appear here.";
    self.tableView.tableFooterView = _resultView;
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
            return @"Saved; Activator fallback is limited";
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
        return section == 0 ? @"Service" : @"Runtime Settings";
    }
    if (section == 0) return @"Diagnostics";
    if (section == 1) return @"Runtime Settings";
    return @"TrollStore Compatibility";
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
    cell.imageView.image = nil;
    cell.accessoryView = nil;
    if (indexPath.section == 0) {
        if (!_debugMode) {
            if ([title isEqualToString:@"License"]) {
                NSDictionary *status = [[SCLicenseManager sharedManager] localStatus];
                cell.detailTextLabel.text = status[@"state"] ?: @"unknown";
                cell.imageView.image = [UIImage systemImageNamed:@"key.fill"];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else if ([title isEqualToString:@"Remote Bridge"]) {
                NSDictionary *remote = [_config[@"remote_bridge"] isKindOfClass:[NSDictionary class]] ? _config[@"remote_bridge"] : @{};
                BOOL enabled = [remote[@"enabled"] boolValue];
                NSString *url = [remote[@"url"] isKindOfClass:[NSString class]] ? remote[@"url"] : @"";
                cell.detailTextLabel.text = enabled ? (url.length > 0 ? url : @"Enabled, not configured") : @"Disabled";
                cell.imageView.image = [UIImage systemImageNamed:@"network"];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else if ([title isEqualToString:@"Restart streamd"]) {
                cell.detailTextLabel.text = @"Replace and restart the task service";
                cell.imageView.image = [UIImage systemImageNamed:@"arrow.clockwise"];
                cell.accessoryType = UITableViewCellAccessoryNone;
            } else if ([title isEqualToString:@"Respring Device"]) {
                cell.detailTextLabel.text = @"Restart SpringBoard";
                cell.textLabel.textColor = [UIColor systemRedColor];
                cell.imageView.image = [UIImage systemImageNamed:@"power"];
                cell.accessoryType = UITableViewCellAccessoryNone;
            } else {
                cell.detailTextLabel.text = @"Open diagnostics and compatibility tools";
                cell.imageView.image = [UIImage systemImageNamed:@"ladybug"];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            }
        } else {
            cell.detailTextLabel.text = @"Tap to run";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else if (indexPath.section == 1) {
        cell.detailTextLabel.text = [self runtimeSettingDetailAtRow:indexPath.row];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = [self runtimeSwitchForRow:indexPath.row];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else {
        cell.detailTextLabel.text = @"Planned compatibility fallback";
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        UISwitch *switchView = [cell.accessoryView isKindOfClass:[UISwitch class]] ? (UISwitch *)cell.accessoryView : nil;
        if (!switchView) return;
        [switchView setOn:!switchView.isOn animated:YES];
        [self runtimeSwitchChanged:switchView];
        return;
    }
    if (indexPath.section != 0) return;

    NSString *title = _sections[(NSUInteger)indexPath.section][(NSUInteger)indexPath.row];
    if (!_debugMode) {
        if ([title isEqualToString:@"License"]) {
            SCLicenseViewController *license = [[SCLicenseViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
            [self.navigationController pushViewController:license animated:YES];
        } else if ([title isEqualToString:@"Remote Bridge"]) {
            [self editRemoteBridge];
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
