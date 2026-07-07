#import "PlaySettingsViewController.h"

static NSString *const kTLinkScriptPlayConfigPath = @"/var/mobile/Library/TLinkauto/config/tweak/script_play_settings.plist";

@implementation SCPlaySettingsViewController {
    NSString *_scriptPath;
    NSMutableDictionary *_currentConfig;
    NSArray<NSDictionary *> *_rows;
}

- (instancetype)initWithScriptPath:(NSString *)scriptPath
{
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _scriptPath = [[scriptPath stringByStandardizingPath] copy];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Play Settings";
    _rows = @[
        @{@"key": @"repeat_times", @"title": @"Repeat Times", @"detail": @"0 means run once"},
        @{@"key": @"interval", @"title": @"Interval", @"detail": @"Seconds between repeats"},
        @{@"key": @"speed", @"title": @"Speed", @"detail": @"Saved for compatibility"},
    ];
    [self loadSettings];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                                                           target:self
                                                                                           action:@selector(saveSettings)];
}

- (void)loadSettings
{
    NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:kTLinkScriptPlayConfigPath];
    NSDictionary *individual = [root[@"individual_configs"] isKindOfClass:[NSDictionary class]] ? root[@"individual_configs"] : nil;
    NSDictionary *stored = [individual[_scriptPath ?: @""] isKindOfClass:[NSDictionary class]] ? individual[_scriptPath ?: @""] : nil;
    _currentConfig = stored ? [stored mutableCopy] : [NSMutableDictionary dictionary];
    if (!_currentConfig[@"repeat_times"]) _currentConfig[@"repeat_times"] = @"0";
    if (!_currentConfig[@"interval"]) _currentConfig[@"interval"] = @"0";
    if (!_currentConfig[@"speed"]) _currentConfig[@"speed"] = @"1.0";
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    (void)tableView;
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    (void)tableView;
    return section == 0 ? (NSInteger)_rows.count : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    (void)tableView;
    return section == 0 ? _scriptPath.lastPathComponent : @"Compatibility";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    (void)tableView;
    if (section == 0) return @"Saved to the original TLinkauto play settings path.";
    return @"Activator trigger is limited on TrollStore and is not configured here.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cellID = @"PlaySettingCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;

    if (indexPath.section == 1) {
        cell.textLabel.text = @"Activator Trigger";
        cell.detailTextLabel.text = @"limited_on_trollstore";
        return cell;
    }

    NSDictionary *row = _rows[(NSUInteger)indexPath.row];
    NSString *key = row[@"key"];
    cell.textLabel.text = row[@"title"];
    cell.detailTextLabel.text = row[@"detail"];

    UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 96, 34)];
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.textAlignment = NSTextAlignmentRight;
    field.keyboardType = indexPath.row == 0 ? UIKeyboardTypeNumberPad : UIKeyboardTypeDecimalPad;
    field.text = [_currentConfig[key] description] ?: @"";
    field.placeholder = indexPath.row == 0 ? @"0" : @"0.0";
    field.tag = indexPath.row;
    [field addTarget:self action:@selector(textFieldChanged:) forControlEvents:UIControlEventEditingChanged];
    cell.accessoryView = field;
    return cell;
}

- (void)textFieldChanged:(UITextField *)field
{
    if (field.tag < 0 || (NSUInteger)field.tag >= _rows.count) return;
    NSString *key = _rows[(NSUInteger)field.tag][@"key"];
    _currentConfig[key] = field.text ?: @"";
}

- (BOOL)validateInteger:(NSString *)text
{
    NSScanner *scanner = [NSScanner scannerWithString:text ?: @""];
    NSInteger value = 0;
    return [scanner scanInteger:&value] && scanner.isAtEnd && value >= 0;
}

- (BOOL)validateNumber:(NSString *)text
{
    NSScanner *scanner = [NSScanner scannerWithString:text ?: @""];
    double value = 0.0;
    return [scanner scanDouble:&value] && scanner.isAtEnd && value >= 0.0;
}

- (void)showMessageWithTitle:(NSString *)title message:(NSString *)message
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)saveSettings
{
    if (![self validateInteger:[_currentConfig[@"repeat_times"] description]] ||
        ![self validateNumber:[_currentConfig[@"interval"] description]] ||
        ![self validateNumber:[_currentConfig[@"speed"] description]]) {
        [self showMessageWithTitle:@"Play Settings" message:@"Repeat must be an integer. Interval and speed must be numbers."];
        return;
    }

    NSMutableDictionary *root = [[NSDictionary dictionaryWithContentsOfFile:kTLinkScriptPlayConfigPath] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *individual = [root[@"individual_configs"] isKindOfClass:[NSDictionary class]]
        ? [root[@"individual_configs"] mutableCopy]
        : [NSMutableDictionary dictionary];
    individual[_scriptPath ?: @""] = [_currentConfig copy];
    root[@"individual_configs"] = individual;

    NSString *parent = [kTLinkScriptPlayConfigPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:nil];
    BOOL ok = [root writeToFile:kTLinkScriptPlayConfigPath atomically:YES];
    [self showMessageWithTitle:@"Play Settings" message:ok ? @"Saved" : @"Save failed"];
}

@end
