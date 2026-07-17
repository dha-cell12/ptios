#import "LicenseViewController.h"
#import "LicenseLifecycleCoordinator.h"
#import "LicenseManager.h"
#include <math.h>

@implementation SCLicenseViewController {
    NSDictionary *_status;
    NSDictionary *_lifecycle;
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
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(lifecycleDidChange:)
                                                 name:SCLicenseLifecycleDidChangeNotification
                                               object:nil];
    [self reloadStatus];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self reloadStatus];
}

- (void)reloadStatus
{
    _status = [[SCLicenseManager sharedManager] localStatus];
    SCLicenseLifecycleCoordinator *coordinator = [SCLicenseLifecycleCoordinator sharedCoordinator];
    _lifecycle = [coordinator diagnostics];
    _requestInFlight = [coordinator isRequestInFlight];
    [self.tableView reloadData];
}

- (void)lifecycleDidChange:(NSNotification *)notification
{
    (void)notification;
    [self reloadStatus];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) return 11;
    if (section == 1) return 1;
    return 4;
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

- (NSString *)dateWithRemainingTextForValue:(id)value
{
    NSTimeInterval seconds = [value doubleValue];
    if (seconds <= 0) return @"-";
    NSTimeInterval remaining = seconds - [[NSDate date] timeIntervalSince1970];
    NSString *date = [self dateTextForValue:value];
    NSTimeInterval absolute = fabs(remaining);
    NSInteger hours = (NSInteger)(absolute / 3600.0);
    NSInteger minutes = (NSInteger)((absolute - hours * 3600.0) / 60.0);
    NSString *relative = hours > 0
        ? [NSString stringWithFormat:@"%ldh %ldm", (long)hours, (long)minutes]
        : [NSString stringWithFormat:@"%ldm", (long)minutes];
    return [NSString stringWithFormat:@"%@ | %@ %@",
            date,
            relative,
            remaining >= 0 ? @"remaining" : @"ago"];
}

- (NSString *)dateTextForMilliseconds:(id)value
{
    NSTimeInterval milliseconds = [value doubleValue];
    return milliseconds > 0 ? [self dateTextForValue:@(milliseconds / 1000.0)] : @"-";
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
    cell.detailTextLabel.adjustsFontSizeToFitWidth = YES;
    cell.detailTextLabel.minimumScaleFactor = 0.7;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if (indexPath.section == 0) {
        NSArray *labels = @[@"State", @"License", @"Features", @"Expires", @"Offline Until",
                            @"Last Attempt", @"Last Success", @"Next Attempt", @"Enforcement",
                            @"Device Key", @"Device Proof"];
        cell.textLabel.text = labels[(NSUInteger)indexPath.row];
        switch (indexPath.row) {
            case 0: cell.detailTextLabel.text = _status[@"state"] ?: @"unknown"; break;
            case 1: cell.detailTextLabel.text = _status[@"license_id"] ?: @"-"; break;
            case 2: {
                NSArray *features = [_status[@"features"] isKindOfClass:[NSArray class]] ? _status[@"features"] : @[];
                cell.detailTextLabel.text = features.count > 0 ? [features componentsJoinedByString:@", "] : @"-";
                break;
            }
            case 3: cell.detailTextLabel.text = [self dateWithRemainingTextForValue:_status[@"expires_at"]]; break;
            case 4: cell.detailTextLabel.text = [self dateWithRemainingTextForValue:_status[@"offline_until"]]; break;
            case 5: cell.detailTextLabel.text = [self dateTextForMilliseconds:_lifecycle[@"last_attempt_at_ms"]]; break;
            case 6: cell.detailTextLabel.text = [self dateTextForMilliseconds:_lifecycle[@"last_success_at_ms"]]; break;
            case 7: cell.detailTextLabel.text = [self dateTextForMilliseconds:_lifecycle[@"next_attempt_at_ms"]]; break;
            case 8: cell.detailTextLabel.text = [_status[@"enforcement_enabled"] boolValue] ? @"On" : @"Observe"; break;
            case 9: cell.detailTextLabel.text = _status[@"device_key_mode"] ?: @"none"; break;
            case 10: cell.detailTextLabel.text = [_status[@"device_key_proof"] boolValue] ? @"Verified" : @"Unavailable"; break;
            default: break;
        }
        return cell;
    }
    if (indexPath.section == 1) {
        cell.textLabel.text = @"Key";
        cell.accessoryView = _licenseField;
        return cell;
    }

    NSArray *actions = @[@"Activate", @"Refresh Lease", @"Deactivate This Device", @"Remove Local Lease (Recovery)"];
    cell.textLabel.text = actions[(NSUInteger)indexPath.row];
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    BOOL needsLease = indexPath.row == 1 || indexPath.row == 2;
    BOOL enabled = !_requestInFlight && (!needsLease || [_status[@"licensed"] boolValue]);
    cell.selectionStyle = enabled ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    if (!enabled) cell.textLabel.textColor = [UIColor tertiaryLabelColor];
    if (enabled && (indexPath.row == 2 || indexPath.row == 3)) cell.textLabel.textColor = [UIColor systemRedColor];
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    (void)tableView;
    if (section != 0) return nil;
    NSString *error = [_lifecycle[@"last_error"] isKindOfClass:[NSString class]] ? _lifecycle[@"last_error"] : @"";
    NSString *decision = [_lifecycle[@"last_decision"] isKindOfClass:[NSString class]] ? _lifecycle[@"last_decision"] : @"";
    if (error.length > 0) return [NSString stringWithFormat:@"Last refresh error: %@", error];
    return decision.length > 0 ? [NSString stringWithFormat:@"Lifecycle: %@", decision] : nil;
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
    if ((indexPath.row == 1 || indexPath.row == 2) && ![_status[@"licensed"] boolValue]) return;
    SCLicenseLifecycleCoordinator *coordinator = [SCLicenseLifecycleCoordinator sharedCoordinator];
    if (indexPath.row == 0) {
        [self setRequestInFlight:YES];
        [coordinator activateLicenseKey:_licenseField.text
                             completion:^(BOOL success, NSString *message) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setRequestInFlight:NO];
                [self reloadStatus];
                [self showResult:message success:success];
            });
        }];
    } else if (indexPath.row == 1) {
        [self setRequestInFlight:YES];
        [coordinator refreshManuallyWithCompletion:^(BOOL success, NSString *message) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setRequestInFlight:NO];
                [self reloadStatus];
                [self showResult:message success:success];
            });
        }];
    } else if (indexPath.row == 2) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Deactivate This Device"
                                                                       message:@"This releases the server device slot and removes the local lease."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Deactivate"
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(__unused UIAlertAction *action) {
            [self setRequestInFlight:YES];
            [coordinator deactivateWithCompletion:^(BOOL success, NSString *message) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self setRequestInFlight:NO];
                    [self reloadStatus];
                    [self showResult:message success:success];
                });
            }];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Remove Local Lease"
                                                                       message:@"Recovery only. This does not release the device slot on the license server."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Remove"
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(__unused UIAlertAction *action) {
            NSError *error = nil;
            BOOL ok = [coordinator removeLocalLease:&error];
            [self reloadStatus];
            [self showResult:ok ? @"local_lease_removed" : error.localizedDescription success:ok];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

@end
