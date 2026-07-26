#import "LicenseViewController.h"
#import "LicenseLifecycleCoordinator.h"
#import "LicenseManager.h"
#include <math.h>

typedef NS_ENUM(NSInteger, SCLicenseSection) {
    SCLicenseSectionAccess = 0,
    SCLicenseSectionLease,
    SCLicenseSectionDevice,
    SCLicenseSectionActivation,
    SCLicenseSectionActions,
    SCLicenseSectionCount,
};

static UIColor *SCLicenseLabelColor(void)
{
    if (@available(iOS 13.0, *)) return [UIColor labelColor];
    return [UIColor blackColor];
}

static UIColor *SCLicenseSecondaryLabelColor(void)
{
    if (@available(iOS 13.0, *)) return [UIColor secondaryLabelColor];
    return [UIColor darkGrayColor];
}

static UIColor *SCLicenseDisabledLabelColor(void)
{
    if (@available(iOS 13.0, *)) return [UIColor tertiaryLabelColor];
    return [UIColor lightGrayColor];
}

static UIColor *SCLicenseBackgroundColor(void)
{
    if (@available(iOS 13.0, *)) return [UIColor systemBackgroundColor];
    return [UIColor whiteColor];
}

static UIColor *SCLicenseDestructiveColor(void)
{
    if (@available(iOS 13.0, *)) return [UIColor systemRedColor];
    return [UIColor redColor];
}

static UIFont *SCLicenseMonospacedFont(void)
{
    if (@available(iOS 13.0, *)) {
        return [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightRegular];
    }
    return [UIFont fontWithName:@"Menlo-Regular" size:12.0] ?: [UIFont systemFontOfSize:12.0];
}

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
    (void)tableView;
    return SCLicenseSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    (void)tableView;
    if (section == SCLicenseSectionAccess) return 7;
    if (section == SCLicenseSectionLease) return 10;
    if (section == SCLicenseSectionDevice) return 8;
    if (section == SCLicenseSectionActivation) return 1;
    return 6;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    (void)tableView;
    if (section == SCLicenseSectionAccess) return @"Access";
    if (section == SCLicenseSectionLease) return @"Lease And Renewal";
    if (section == SCLicenseSectionDevice) return @"Device Binding";
    if (section == SCLicenseSectionActivation) return @"Activation";
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
    NSInteger days = (NSInteger)(absolute / 86400.0);
    NSInteger hours = (NSInteger)((absolute - days * 86400.0) / 3600.0);
    NSInteger minutes = (NSInteger)((absolute - days * 86400.0 - hours * 3600.0) / 60.0);
    NSString *relative = nil;
    if (days > 0) relative = [NSString stringWithFormat:@"%ldd %ldh", (long)days, (long)hours];
    else if (hours > 0) relative = [NSString stringWithFormat:@"%ldh %ldm", (long)hours, (long)minutes];
    else relative = [NSString stringWithFormat:@"%ldm", (long)minutes];
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

- (NSString *)durationTextForSeconds:(id)value
{
    NSInteger seconds = [value integerValue];
    if (seconds <= 0) return @"-";
    NSInteger days = seconds / 86400;
    NSInteger hours = (seconds % 86400) / 3600;
    if (days > 0) return [NSString stringWithFormat:@"%ldd %ldh", (long)days, (long)hours];
    NSInteger minutes = (seconds % 3600) / 60;
    if (hours > 0) return [NSString stringWithFormat:@"%ldh %ldm", (long)hours, (long)minutes];
    return [NSString stringWithFormat:@"%ldm", (long)minutes];
}

- (NSString *)licenseExpirationText
{
    NSTimeInterval expiration = [_status[@"license_expires_at"] doubleValue];
    if (expiration > 0) return [self dateWithRemainingTextForValue:@(expiration)];
    NSString *renewalMode = [_status[@"renewal_mode"] isKindOfClass:[NSString class]]
        ? _status[@"renewal_mode"]
        : @"legacy_lease";
    return [renewalMode isEqualToString:@"legacy_lease"] ? @"Legacy lease - refresh once" : @"Perpetual";
}

- (NSString *)renewalText
{
    NSString *mode = [_status[@"renewal_mode"] isKindOfClass:[NSString class]]
        ? _status[@"renewal_mode"]
        : @"legacy_lease";
    if ([mode isEqualToString:@"server_refresh_until_license_expiry"]) {
        return [_status[@"license_expires_at"] doubleValue] > 0
            ? @"Automatic, until license expiry"
            : @"Automatic, perpetual license";
    }
    return @"Legacy lease";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *identifier = indexPath.section == SCLicenseSectionActivation
        ? @"LicenseInputCell"
        : @"LicenseCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:identifier];
    }
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.textAlignment = NSTextAlignmentNatural;
    cell.textLabel.textColor = SCLicenseLabelColor();
    cell.detailTextLabel.textColor = SCLicenseSecondaryLabelColor();
    cell.detailTextLabel.adjustsFontSizeToFitWidth = YES;
    cell.detailTextLabel.minimumScaleFactor = 0.62;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if (indexPath.section == SCLicenseSectionAccess) {
        NSArray *labels = @[@"State", @"Effective Access", @"License Expires", @"Renewal",
                            @"Features", @"Enforcement", @"Contract"];
        cell.textLabel.text = labels[(NSUInteger)indexPath.row];
        switch (indexPath.row) {
            case 0: cell.detailTextLabel.text = _status[@"state"] ?: @"unknown"; break;
            case 1: cell.detailTextLabel.text = [_status[@"effective_access"] boolValue] ? @"Allowed" : @"Blocked"; break;
            case 2: cell.detailTextLabel.text = [self licenseExpirationText]; break;
            case 3: cell.detailTextLabel.text = [self renewalText]; break;
            case 4: {
                NSArray *features = [_status[@"features"] isKindOfClass:[NSArray class]] ? _status[@"features"] : @[];
                cell.detailTextLabel.text = features.count > 0 ? [features componentsJoinedByString:@", "] : @"-";
                break;
            }
            case 5: cell.detailTextLabel.text = [_status[@"enforcement_enabled"] boolValue] ? @"On" : @"Observe"; break;
            case 6: cell.detailTextLabel.text = [NSString stringWithFormat:@"v%@ | %@",
                                                 _status[@"license_contract_version"] ?: @1,
                                                 _status[@"build_mode"] ?: @"unknown"]; break;
            default: break;
        }
        return cell;
    }

    if (indexPath.section == SCLicenseSectionLease) {
        NSArray *labels = @[@"Issued", @"Lease Valid Until", @"Offline Until", @"Lease Policy",
                            @"Offline Policy", @"Last Trigger", @"Last Result", @"Last Attempt",
                            @"Last Success", @"Next Attempt"];
        cell.textLabel.text = labels[(NSUInteger)indexPath.row];
        switch (indexPath.row) {
            case 0: cell.detailTextLabel.text = [self dateTextForValue:_status[@"issued_at"]]; break;
            case 1: {
                id leaseExpiration = _status[@"lease_expires_at"];
                if (!leaseExpiration) leaseExpiration = _status[@"expires_at"];
                cell.detailTextLabel.text = [self dateWithRemainingTextForValue:leaseExpiration];
                break;
            }
            case 2: cell.detailTextLabel.text = [self dateWithRemainingTextForValue:_status[@"offline_until"]]; break;
            case 3: cell.detailTextLabel.text = [self durationTextForSeconds:_status[@"lease_policy_seconds"]]; break;
            case 4: cell.detailTextLabel.text = [self durationTextForSeconds:_status[@"offline_grace_policy_seconds"]]; break;
            case 5: cell.detailTextLabel.text = _lifecycle[@"last_trigger"] ?: @"-"; break;
            case 6: {
                NSString *result = _lifecycle[@"last_result"];
                if (result.length == 0) result = _lifecycle[@"last_decision"];
                cell.detailTextLabel.text = result.length > 0 ? result : @"-";
                break;
            }
            case 7: cell.detailTextLabel.text = [self dateTextForMilliseconds:_lifecycle[@"last_attempt_at_ms"]]; break;
            case 8: cell.detailTextLabel.text = [self dateTextForMilliseconds:_lifecycle[@"last_success_at_ms"]]; break;
            case 9: cell.detailTextLabel.text = [self dateTextForMilliseconds:_lifecycle[@"next_attempt_at_ms"]]; break;
            default: break;
        }
        return cell;
    }

    if (indexPath.section == SCLicenseSectionDevice) {
        NSArray *labels = @[@"License ID", @"Device ID", @"Lease Token", @"Device Key",
                            @"Device Proof", @"Private Key", @"Public Key", @"Recovery"];
        cell.textLabel.text = labels[(NSUInteger)indexPath.row];
        switch (indexPath.row) {
            case 0: cell.detailTextLabel.text = _status[@"license_id"] ?: @"-"; break;
            case 1: cell.detailTextLabel.text = _status[@"device_id"] ?: @"-"; break;
            case 2: cell.detailTextLabel.text = _status[@"token_id"] ?: @"-"; break;
            case 3: cell.detailTextLabel.text = _status[@"device_key_mode"] ?: @"none"; break;
            case 4: cell.detailTextLabel.text = [_status[@"device_key_proof"] boolValue] ? @"Verified" : @"Unavailable"; break;
            case 5: cell.detailTextLabel.text = [_status[@"device_private_key_present"] boolValue] ? @"Present" : @"Missing"; break;
            case 6: cell.detailTextLabel.text = [_status[@"device_public_key_present"] boolValue] ? @"Present" : @"Missing"; break;
            case 7: cell.detailTextLabel.text = _status[@"recovery_action"] ?: @"none"; break;
            default: break;
        }
        if (indexPath.row <= 2 && [cell.detailTextLabel.text length] > 1) {
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        return cell;
    }

    if (indexPath.section == SCLicenseSectionActivation) {
        cell.textLabel.text = @"Key";
        cell.accessoryView = _licenseField;
        return cell;
    }

    NSArray *actions = @[@"Activate", @"Refresh Lease", @"View Refresh History",
                         @"Deactivate This Device", @"Repair Device Binding",
                         @"Remove Local Lease (Recovery)"];
    cell.textLabel.text = actions[(NSUInteger)indexPath.row];
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    BOOL needsLease = indexPath.row == 1 || indexPath.row == 3;
    BOOL repairAvailable = indexPath.row != 4 || [_status[@"device_private_key_present"] boolValue];
    BOOL enabled = !_requestInFlight && repairAvailable && (!needsLease || [_status[@"licensed"] boolValue]);
    cell.selectionStyle = enabled ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    if (!enabled) cell.textLabel.textColor = SCLicenseDisabledLabelColor();
    if (enabled && (indexPath.row == 3 || indexPath.row == 5)) {
        cell.textLabel.textColor = SCLicenseDestructiveColor();
    }
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    (void)tableView;
    if (section == SCLicenseSectionAccess) {
        NSDictionary *recovery = [_status[@"recovery"] isKindOfClass:[NSDictionary class]] ? _status[@"recovery"] : @{};
        if (recovery.count > 0) {
            return [NSString stringWithFormat:@"Recovery: %@. Reactivate after reviewing the quarantined lease.",
                    recovery[@"reason"] ?: @"license_data_quarantined"];
        }
        return @"License expiry is controlled by the server. A perpetual license displays Perpetual.";
    }
    if (section == SCLicenseSectionLease) {
        NSString *error = [_lifecycle[@"last_error"] isKindOfClass:[NSString class]] ? _lifecycle[@"last_error"] : @"";
        if (error.length > 0) return [NSString stringWithFormat:@"Last refresh error: %@", error];
        return @"The signed lease is short-lived and its date moves after a successful refresh. Automatic refresh starts inside the final 6 hours and can never extend beyond License Expires.";
    }
    if (section == SCLicenseSectionDevice) {
        return @"Tap License ID, Device ID, or Lease Token to copy it.";
    }
    return nil;
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
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:SCLicenseSectionActions]
                  withRowAnimation:UITableViewRowAnimationNone];
}

- (void)dismissDetails
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)showRefreshHistory
{
    NSArray *history = [_lifecycle[@"refresh_history"] isKindOfClass:[NSArray class]]
        ? _lifecycle[@"refresh_history"]
        : @[];
    NSMutableArray *lines = [NSMutableArray array];
    for (NSDictionary *event in [history reverseObjectEnumerator]) {
        if (![event isKindOfClass:[NSDictionary class]]) continue;
        NSString *line = [NSString stringWithFormat:@"%@  %@  %@\nLease: %@ -> %@\nExtended: %@s%@",
                          [self dateTextForMilliseconds:event[@"at_ms"]],
                          event[@"trigger"] ?: @"unknown",
                          event[@"result"] ?: @"unknown",
                          [self dateTextForValue:event[@"lease_before_expires_at"]],
                          [self dateTextForValue:event[@"lease_after_expires_at"]],
                          event[@"extended_seconds"] ?: @0,
                          [event[@"error"] length] > 0
                              ? [NSString stringWithFormat:@"\nError: %@", event[@"error"]]
                              : @""];
        [lines addObject:line];
    }
    if (lines.count == 0) [lines addObject:@"No refresh attempts have been recorded on this installation."];

    UIViewController *controller = [[UIViewController alloc] initWithNibName:nil bundle:nil];
    controller.title = @"Refresh History";
    controller.view.backgroundColor = SCLicenseBackgroundColor();
    UITextView *textView = [[UITextView alloc] initWithFrame:CGRectZero];
    textView.translatesAutoresizingMaskIntoConstraints = NO;
    textView.editable = NO;
    textView.selectable = YES;
    textView.font = SCLicenseMonospacedFont();
    textView.text = [lines componentsJoinedByString:@"\n\n"];
    textView.textContainerInset = UIEdgeInsetsMake(16, 14, 16, 14);
    [controller.view addSubview:textView];
    [NSLayoutConstraint activateConstraints:@[
        [textView.topAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.topAnchor],
        [textView.leadingAnchor constraintEqualToAnchor:controller.view.leadingAnchor],
        [textView.trailingAnchor constraintEqualToAnchor:controller.view.trailingAnchor],
        [textView.bottomAnchor constraintEqualToAnchor:controller.view.bottomAnchor],
    ]];
    controller.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                     target:self
                                                     action:@selector(dismissDetails)];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)copyDeviceValueAtRow:(NSInteger)row
{
    NSArray *keys = @[@"license_id", @"device_id", @"token_id"];
    if (row < 0 || row >= (NSInteger)keys.count) return;
    NSString *value = [_status[keys[(NSUInteger)row]] isKindOfClass:[NSString class]]
        ? _status[keys[(NSUInteger)row]]
        : @"";
    if (value.length == 0) return;
    [UIPasteboard generalPasteboard].string = value;
    self.navigationItem.prompt = @"Copied";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        self.navigationItem.prompt = nil;
    });
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == SCLicenseSectionDevice && indexPath.row <= 2) {
        [self copyDeviceValueAtRow:indexPath.row];
        return;
    }
    if (indexPath.section != SCLicenseSectionActions || _requestInFlight) return;
    if ((indexPath.row == 1 || indexPath.row == 3) && ![_status[@"licensed"] boolValue]) return;
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
        [self showRefreshHistory];
    } else if (indexPath.row == 3) {
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
    } else if (indexPath.row == 4) {
        NSError *error = nil;
        BOOL ok = [coordinator repairDevicePublicKey:&error];
        [self reloadStatus];
        [self showResult:ok ? @"device_public_key_repaired" : error.localizedDescription success:ok];
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
