#import "LicenseViewController.h"
#import "LicenseManager.h"

@implementation SCLicenseViewController {
    NSDictionary *_status;
    UITextField *_licenseField;
    BOOL _requestInFlight;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"License";
    _licenseField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 220, 38)];
    _licenseField.placeholder = @"License key";
    _licenseField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    _licenseField.autocorrectionType = UITextAutocorrectionTypeNo;
    _licenseField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _licenseField.textAlignment = NSTextAlignmentRight;
    [self reloadStatus];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self reloadStatus];
}

- (void)reloadStatus
{
    _status = [[SCLicenseManager sharedManager] localStatus];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) return 7;
    if (section == 1) return 1;
    return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (section == 0) return @"Status";
    if (section == 1) return @"Activation";
    return @"Actions";
}

- (NSString *)dateTextForValue:(id)value
{
    NSTimeInterval seconds = [value doubleValue];
    if (seconds <= 0) return @"-";
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:seconds]];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *identifier = indexPath.section == 1 ? @"LicenseInputCell" : @"LicenseCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:identifier];
    }
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if (indexPath.section == 0) {
        NSArray *labels = @[@"State", @"License", @"Expires", @"Offline Until", @"Enforcement", @"Device Key", @"Device Proof"];
        cell.textLabel.text = labels[(NSUInteger)indexPath.row];
        switch (indexPath.row) {
            case 0: cell.detailTextLabel.text = _status[@"state"] ?: @"unknown"; break;
            case 1: cell.detailTextLabel.text = _status[@"license_id"] ?: @"-"; break;
            case 2: cell.detailTextLabel.text = [self dateTextForValue:_status[@"expires_at"]]; break;
            case 3: cell.detailTextLabel.text = [self dateTextForValue:_status[@"offline_until"]]; break;
            case 4: cell.detailTextLabel.text = [_status[@"enforcement_enabled"] boolValue] ? @"On" : @"Observe"; break;
            case 5: cell.detailTextLabel.text = _status[@"device_key_mode"] ?: @"none"; break;
            case 6: cell.detailTextLabel.text = [_status[@"device_key_proof"] boolValue] ? @"Verified" : @"Unavailable"; break;
            default: break;
        }
        return cell;
    }
    if (indexPath.section == 1) {
        cell.textLabel.text = @"Key";
        cell.accessoryView = _licenseField;
        return cell;
    }

    NSArray *actions = @[@"Activate", @"Refresh Lease", @"Remove Local Lease"];
    cell.textLabel.text = actions[(NSUInteger)indexPath.row];
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.selectionStyle = _requestInFlight ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
    if (indexPath.row == 2) cell.textLabel.textColor = [UIColor systemRedColor];
    return cell;
}

- (void)showResult:(NSString *)message success:(BOOL)success
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:success ? @"License" : @"License Error"
                                                                   message:message ?: @""
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)setRequestInFlight:(BOOL)inFlight
{
    _requestInFlight = inFlight;
    self.navigationItem.hidesBackButton = inFlight;
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:2] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 2 || _requestInFlight) return;
    if (indexPath.row == 0) {
        [self setRequestInFlight:YES];
        [[SCLicenseManager sharedManager] activateLicenseKey:_licenseField.text
                                                  completion:^(BOOL success, NSString *message) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setRequestInFlight:NO];
                [self reloadStatus];
                [self showResult:message success:success];
            });
        }];
    } else if (indexPath.row == 1) {
        [self setRequestInFlight:YES];
        [[SCLicenseManager sharedManager] refreshLeaseWithCompletion:^(BOOL success, NSString *message) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setRequestInFlight:NO];
                [self reloadStatus];
                [self showResult:message success:success];
            });
        }];
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Remove Local Lease"
                                                                       message:nil
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Remove"
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(__unused UIAlertAction *action) {
            NSError *error = nil;
            BOOL ok = [[SCLicenseManager sharedManager] removeLocalLease:&error];
            [self reloadStatus];
            [self showResult:ok ? @"local_lease_removed" : error.localizedDescription success:ok];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

@end
