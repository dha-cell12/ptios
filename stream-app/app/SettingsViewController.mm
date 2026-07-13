#import "SettingsViewController.h"
#import "TLinkSocketClient.h"

static NSString *const kTLinkSettingsConfigPath = @"/var/mobile/Library/TLinkauto/config/tweak/config.plist";
static NSString *const kTLinkScriptPlayConfigPath = @"/var/mobile/Library/TLinkauto/config/tweak/script_play_settings.plist";

@implementation SCSettingsViewController {
    NSArray<NSArray<NSString *> *> *_sections;
    UITextView *_resultView;
    NSMutableDictionary *_config;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Settings";
    [self loadConfig];
    _sections = @[
        @[@"Capability Probe", @"Hello Status", @"Script Status", @"Capture Probe", @"Native Tap Center", @"Color Pick Center", @"Color Search Smoke", @"Frame Capture", @"OCR Languages", @"App Info Self", @"Frontmost App", @"List Bundles", @"Open Preferences", @"Open Settings URL", @"Toast Overlay", @"Alert Box", @"Dialog Overlay", @"Clear Dialog", @"Touch Indicator On", @"Touch Indicator Off", @"Keep Awake On", @"Keep Awake Off", @"Set Auto Launch", @"List Auto Launch", @"Set Timer Demo", @"Remove Timer Demo", @"Legacy Stop Script", @"Update Cache", @"Start Touch Recording", @"Stop Touch Recording", @"Rapid Tap Center", @"Stop Tap Macro", @"Hardware Key Home", @"Wi-Fi Status", @"Bluetooth Status", @"Airplane Status", @"Cellular Status", @"Export Diagnostics"],
        @[@"Touch Indicator", @"Switch App Before Playing", @"Double-click Popup", @"Enable Shell Task"],
        @[@"Color/Image/Frame: active", @"Vision OCR: active", @"Script Runtime: javascriptcore_mvp", @"Scheduler: streamd_lite + autolaunch", @"Touch Recording: iohid raw replay", @"Tap Macro: bounded async native tap", @"Hardware Key: hid keyboard event", @"Connectivity: best effort private framework", @"Shell: gated local sh", @"Visual Feedback: foreground_overlay", @"Dialog Overlay: nonblocking", @"Keep Awake: foreground idle timer", @"Service Mode: helper ensure streamd", @"App/Process: helper launch/kill/url", @"Keyboard Clipboard: limited_on_trollstore", @"Activator: limited_on_trollstore", @"Privhelper: open_kill_restart_ensure"],
    ];

    _resultView = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 180)];
    _resultView.editable = NO;
    _resultView.font = [UIFont fontWithName:@"Menlo" size:11.0] ?: [UIFont systemFontOfSize:11.0];
    _resultView.text = @"Diagnostics will appear here.";
    self.tableView.tableFooterView = _resultView;
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
    NSDictionary *configSnapshot = [_config copy] ?: @{};
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableString *report = [NSMutableString string];
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss Z";
        [report appendFormat:@"TLinkauto TrollStore Diagnostics\n%@\n\n", [formatter stringFromDate:[NSDate date]]];
        [report appendFormat:@"config_path: %@\nconfig: %@\n\n", kTLinkSettingsConfigPath, configSnapshot];
        NSDictionary *playConfig = [NSDictionary dictionaryWithContentsOfFile:kTLinkScriptPlayConfigPath] ?: @{};
        [report appendFormat:@"play_config_path: %@\nplay_config: %@\n\n", kTLinkScriptPlayConfigPath, playConfig];

        NSArray<NSString *> *lines = @[@"97\n", @"60\n", @"98\n"];
        NSArray<NSString *> *labels = @[@"task97_capability", @"task60_status", @"task98_capture_probe"];
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
    cell.accessoryView = nil;
    if (indexPath.section == 0) {
        cell.detailTextLabel.text = @"Tap to run";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
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

    if (indexPath.row == 37) {
        [self exportDiagnostics];
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
