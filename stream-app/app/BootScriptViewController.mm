#import "BootScriptViewController.h"
#import "TLinkTheme.h"

static NSString *const kTLinkScriptsRootPath = @"/var/mobile/Library/TLinkauto/scripts";
static NSString *const kTLinkBootScriptConfigPath = @"/var/mobile/Library/TLinkauto/config/tweak/boot_script.plist";
static NSString *const kTLinkAutoLaunchConfigPath = @"/var/mobile/Library/TLinkauto/autolaunch.plist";
static NSString *const kTLinkBootEnabledMarkerPath = @"/var/mobile/Library/TLinkauto/runtime/widget_boot_enabled";
static NSString *const kTLinkBootAutoLaunchName = @"00-boot-script";

@implementation SCBootScriptViewController {
    NSMutableDictionary *_config;
    NSArray<NSString *> *_scriptPaths;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Boot Script";
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    [self loadConfiguration];
    [self reloadScriptPaths];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self reloadScriptPaths];
    [self.tableView reloadData];
}

- (void)loadConfiguration
{
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:kTLinkBootScriptConfigPath];
    _config = [saved isKindOfClass:[NSDictionary class]] ? [saved mutableCopy] : [NSMutableDictionary dictionary];
    if (![_config[@"enabled"] isKindOfClass:[NSNumber class]]) _config[@"enabled"] = @NO;
    if (![_config[@"script"] isKindOfClass:[NSString class]]) _config[@"script"] = @"";
}

- (BOOL)isScriptBundleAtPath:(NSString *)path
{
    NSString *extension = path.pathExtension.lowercaseString;
    if ([extension isEqualToString:@"tl"] || [extension isEqualToString:@"xxt"]) return YES;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    return [fileManager fileExistsAtPath:[path stringByAppendingPathComponent:@"manifest.json"]] ||
           [fileManager fileExistsAtPath:[path stringByAppendingPathComponent:@"info.plist"]];
}

- (void)reloadScriptPaths
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager createDirectoryAtPath:kTLinkScriptsRootPath withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *rootURL = [NSURL fileURLWithPath:kTLinkScriptsRootPath isDirectory:YES];
    NSArray *keys = @[NSURLIsDirectoryKey, NSURLIsRegularFileKey, NSURLNameKey];
    NSDirectoryEnumerator<NSURL *> *enumerator = [fileManager enumeratorAtURL:rootURL
                                                   includingPropertiesForKeys:keys
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                 errorHandler:^BOOL(NSURL *url, NSError *error) {
        (void)url;
        (void)error;
        return YES;
    }];
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSURL *url in enumerator) {
        NSNumber *isDirectory = nil;
        NSNumber *isRegularFile = nil;
        [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
        [url getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:nil];
        NSString *path = url.path ?: @"";
        if (isDirectory.boolValue) {
            if ([self isScriptBundleAtPath:path]) {
                [paths addObject:path];
                [enumerator skipDescendants];
            }
            continue;
        }
        if (isRegularFile.boolValue && [path.pathExtension.lowercaseString isEqualToString:@"js"]) {
            [paths addObject:path];
        }
    }
    _scriptPaths = [paths sortedArrayUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
        return [[self displayPathForScript:left] localizedCaseInsensitiveCompare:[self displayPathForScript:right]];
    }];
}

- (NSString *)displayPathForScript:(NSString *)path
{
    NSString *prefix = [kTLinkScriptsRootPath stringByAppendingString:@"/"];
    return [path hasPrefix:prefix] ? [path substringFromIndex:prefix.length] : path.lastPathComponent;
}

- (BOOL)writeEnabledMarker:(BOOL)enabled
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (!enabled) {
        if (![fileManager fileExistsAtPath:kTLinkBootEnabledMarkerPath]) return YES;
        return [fileManager removeItemAtPath:kTLinkBootEnabledMarkerPath error:nil];
    }

    NSString *directory = [kTLinkBootEnabledMarkerPath stringByDeletingLastPathComponent];
    if (![fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil]) return NO;
    [fileManager setAttributes:@{NSFileProtectionKey: NSFileProtectionNone}
                 ofItemAtPath:directory
                        error:nil];
    NSData *marker = [@"enabled\n" dataUsingEncoding:NSUTF8StringEncoding];
    if (![marker writeToFile:kTLinkBootEnabledMarkerPath atomically:YES]) return NO;
    return [fileManager setAttributes:@{NSFileProtectionKey: NSFileProtectionNone}
                         ofItemAtPath:kTLinkBootEnabledMarkerPath
                                error:nil];
}

- (BOOL)saveConfigurationWithError:(NSString **)errorMessage
{
    BOOL enabled = [_config[@"enabled"] boolValue];
    NSString *script = [_config[@"script"] isKindOfClass:[NSString class]] ? _config[@"script"] : @"";
    if (enabled && script.length == 0) {
        if (errorMessage) *errorMessage = @"Choose a script before enabling Boot Script.";
        return NO;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *autoLaunchDirectory = [kTLinkAutoLaunchConfigPath stringByDeletingLastPathComponent];
    NSString *bootConfigDirectory = [kTLinkBootScriptConfigPath stringByDeletingLastPathComponent];
    if (![fileManager createDirectoryAtPath:autoLaunchDirectory withIntermediateDirectories:YES attributes:nil error:nil] ||
        ![fileManager createDirectoryAtPath:bootConfigDirectory withIntermediateDirectories:YES attributes:nil error:nil]) {
        if (errorMessage) *errorMessage = @"Could not create the TLinkauto configuration directory.";
        return NO;
    }

    NSMutableDictionary *autoLaunch = [[NSDictionary dictionaryWithContentsOfFile:kTLinkAutoLaunchConfigPath] mutableCopy];
    if (!autoLaunch) autoLaunch = [NSMutableDictionary dictionary];
    autoLaunch[kTLinkBootAutoLaunchName] = @{
        @"script": script ?: @"",
        @"enabled": @(enabled),
        @"source": @"widget_boot_script_v1",
    };
    if (![autoLaunch writeToFile:kTLinkAutoLaunchConfigPath atomically:YES]) {
        if (errorMessage) *errorMessage = @"Could not update autolaunch.plist.";
        return NO;
    }

    _config[@"updated_at"] = @([[NSDate date] timeIntervalSince1970]);
    _config[@"autolaunch_name"] = kTLinkBootAutoLaunchName;
    _config[@"mode"] = @"widget_wake_then_streamd_autolaunch";
    if (![_config writeToFile:kTLinkBootScriptConfigPath atomically:YES]) {
        if (errorMessage) *errorMessage = @"Could not save boot_script.plist.";
        return NO;
    }
    if (![self writeEnabledMarker:enabled]) {
        if (errorMessage) *errorMessage = @"Could not update the boot-enabled marker.";
        return NO;
    }
    return YES;
}

- (void)showError:(NSString *)message
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Boot Script"
                                                                   message:message ?: @"Configuration could not be saved."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)enabledSwitchChanged:(UISwitch *)sender
{
    BOOL previous = [_config[@"enabled"] boolValue];
    _config[@"enabled"] = @(sender.isOn);
    NSString *error = nil;
    if (![self saveConfigurationWithError:&error]) {
        _config[@"enabled"] = @(previous);
        [sender setOn:previous animated:YES];
        [self showError:error];
        return;
    }
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    (void)tableView;
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    (void)tableView;
    return section == 0 ? 1 : MAX((NSInteger)_scriptPaths.count, 1);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    (void)tableView;
    return section == 0 ? @"Startup" : @"Script";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    (void)tableView;
    if (section == 0) {
        return @"Add the TLinkauto Boot Wake widget to the Home Screen. After reboot, WidgetKit can wake StreamControl, which starts streamd and runs the selected script.";
    }
    return @"Boot wake is best effort and depends on iOS scheduling the installed widget. The selected script still obeys the normal script license and runtime checks.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *identifier = indexPath.section == 0 ? @"BootEnabled" : @"BootScript";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    if (indexPath.section == 0) {
        cell.textLabel.text = @"Enable Boot Script";
        NSString *selected = [_config[@"script"] isKindOfClass:[NSString class]] ? _config[@"script"] : @"";
        cell.detailTextLabel.text = selected.length > 0 ? [self displayPathForScript:selected] : @"No script selected";
        UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectZero];
        [toggle setOn:[_config[@"enabled"] boolValue] animated:NO];
        [toggle addTarget:self action:@selector(enabledSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    if (_scriptPaths.count == 0) {
        cell.textLabel.text = @"No JavaScript scripts found";
        cell.detailTextLabel.text = kTLinkScriptsRootPath;
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    NSString *path = _scriptPaths[(NSUInteger)indexPath.row];
    cell.textLabel.text = path.lastPathComponent;
    cell.detailTextLabel.text = [self displayPathForScript:path];
    cell.accessoryType = [path isEqualToString:_config[@"script"]]
        ? UITableViewCellAccessoryCheckmark
        : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1 || _scriptPaths.count == 0) return;
    _config[@"script"] = _scriptPaths[(NSUInteger)indexPath.row];
    NSString *error = nil;
    if (![self saveConfigurationWithError:&error]) {
        [self showError:error];
    }
    [self.tableView reloadData];
}

@end
