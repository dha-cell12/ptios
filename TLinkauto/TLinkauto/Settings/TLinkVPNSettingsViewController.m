#import "TLinkVPNSettingsViewController.h"

#import "../../../shared/TLinkVPNManager.h"

@interface TLinkVPNSettingsViewController ()
@property(nonatomic, strong) UITextField *serverField;
@property(nonatomic, strong) UITextField *remoteIdentifierField;
@property(nonatomic, strong) UITextField *usernameField;
@property(nonatomic, strong) UITextField *passwordField;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UIActivityIndicatorView *transitionSpinner;
@property(nonatomic, copy) NSString *transitionAction;
@property(nonatomic, strong) NSDate *transitionStartedAt;
@property(nonatomic, assign) NSUInteger transitionGeneration;
@end

@implementation TLinkVPNSettingsViewController

- (UITextField *)fieldWithPlaceholder:(NSString *)placeholder secure:(BOOL)secure
{
    UITextField *field = [[UITextField alloc] init];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.placeholder = placeholder;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.secureTextEntry = secure;
    return field;
}

- (UIButton *)buttonWithTitle:(NSString *)title action:(SEL)action
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Managed VPN";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.serverField = [self fieldWithPlaceholder:@"IKEv2 server address" secure:NO];
    self.remoteIdentifierField =
        [self fieldWithPlaceholder:@"Remote identifier (defaults to server)" secure:NO];
    self.usernameField = [self fieldWithPlaceholder:@"Username" secure:NO];
    self.passwordField = [self fieldWithPlaceholder:@"Password" secure:YES];
    self.serverField.text = [defaults stringForKey:@"TLinkVPNServerAddress"] ?: @"";
    self.remoteIdentifierField.text =
        [defaults stringForKey:@"TLinkVPNRemoteIdentifier"] ?: @"";
    self.usernameField.text = [defaults stringForKey:@"TLinkVPNUsername"] ?: @"";

    UILabel *security = [[UILabel alloc] init];
    security.numberOfLines = 0;
    security.font = [UIFont systemFontOfSize:12];
    security.textColor = [UIColor secondaryLabelColor];
    security.text =
        @"The password is stored in ThisDeviceOnly Keychain. VPN configuration "
         "and credentials are never sent through port 6000.";

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont monospacedSystemFontOfSize:12
                                                      weight:UIFontWeightRegular];
    self.statusLabel.text = @"Status: loading";

    self.transitionSpinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.transitionSpinner.hidesWhenStopped = YES;

    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self buttonWithTitle:@"Save Profile" action:@selector(saveProfile)],
        [self buttonWithTitle:@"Connect" action:@selector(connectVPN)],
        [self buttonWithTitle:@"Disconnect" action:@selector(disconnectVPN)],
        [self buttonWithTitle:@"Refresh" action:@selector(refreshStatus)],
    ]];
    buttons.axis = UILayoutConstraintAxisVertical;
    buttons.spacing = 8;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.serverField,
        self.remoteIdentifierField,
        self.usernameField,
        self.passwordField,
        security,
        buttons,
        self.transitionSpinner,
        self.statusLabel,
    ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    [self.view addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20],
    ]];
    [self refreshStatus];
}

- (void)pollTransitionStatusForGeneration:(NSUInteger)generation
{
    if (generation != self.transitionGeneration ||
        self.transitionAction.length == 0) return;

    TLinkVPNReadManagerStatus(^(NSDictionary *result) {
        if (generation != self.transitionGeneration ||
            self.transitionAction.length == 0) return;
        NSTimeInterval elapsed = -[self.transitionStartedAt timeIntervalSinceNow];
        NSString *connection = [result[@"connection_status"]
            isKindOfClass:[NSString class]]
            ? result[@"connection_status"]
            : @"unknown";
        NSString *code = [result[@"code"] isKindOfClass:[NSString class]]
            ? result[@"code"]
            : @"vpn_status_unknown";
        self.statusLabel.text = [NSString stringWithFormat:
            @"%@… %.0fs\nConnection: %@\nStatus probe: %@",
            self.transitionAction,
            elapsed,
            connection,
            code];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
            (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self pollTransitionStatusForGeneration:generation];
        });
    });
}

- (void)beginTransitionStatusPolling:(NSString *)action
{
    self.transitionGeneration += 1;
    self.transitionAction = action;
    self.transitionStartedAt = [NSDate date];
    [self.transitionSpinner startAnimating];
    [self pollTransitionStatusForGeneration:self.transitionGeneration];
}

- (void)endTransitionStatusPolling
{
    self.transitionGeneration += 1;
    self.transitionAction = nil;
    self.transitionStartedAt = nil;
    [self.transitionSpinner stopAnimating];
}

- (void)showResult:(NSDictionary *)result title:(NSString *)title
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *code = [result[@"code"] isKindOfClass:[NSString class]]
            ? result[@"code"]
            : @"unknown";
        NSString *connection = [result[@"connection_status"] isKindOfClass:[NSString class]]
            ? result[@"connection_status"]
            : @"unknown";
        NSNumber *osStatus = [result[@"os_status"] isKindOfClass:[NSNumber class]]
            ? result[@"os_status"]
            : nil;
        NSString *nativeError = [result[@"native_error"] isKindOfClass:[NSString class]]
            ? result[@"native_error"]
            : @"";
        NSString *diagnostic = @"";
        if (osStatus) {
            diagnostic = [diagnostic stringByAppendingFormat:
                @"\nOSStatus: %@", osStatus];
        }
        if (nativeError.length > 0) {
            diagnostic = [diagnostic stringByAppendingFormat:
                @"\nNative error: %@", nativeError];
        }
        self.statusLabel.text = [NSString stringWithFormat:
            @"Code: %@\nConfigured: %@\nEnabled: %@\nConnection: %@%@",
            code,
            [result[@"configured"] boolValue] ? @"yes" : @"no",
            [result[@"enabled"] boolValue] ? @"yes" : @"no",
            connection,
            diagnostic];
        if (![result[@"ok"] boolValue]) {
            NSString *alertMessage = diagnostic.length > 0
                ? [NSString stringWithFormat:@"%@%@", code, diagnostic]
                : code;
            UIAlertController *alert = [UIAlertController
                alertControllerWithTitle:title
                                 message:alertMessage
                          preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                     style:UIAlertActionStyleDefault
                                                   handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    });
}

- (void)saveProfile
{
    NSString *server = self.serverField.text ?: @"";
    NSString *remote = self.remoteIdentifierField.text ?: @"";
    NSString *username = self.usernameField.text ?: @"";
    NSString *password = self.passwordField.text ?: @"";

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:server forKey:@"TLinkVPNServerAddress"];
    [defaults setObject:remote forKey:@"TLinkVPNRemoteIdentifier"];
    [defaults setObject:username forKey:@"TLinkVPNUsername"];

    self.statusLabel.text = @"Saving profile; approve the iOS VPN prompt if shown…";
    TLinkVPNConfigureIKEv2(
        server,
        remote,
        username,
        password,
        ^(NSDictionary *result) {
            self.passwordField.text = @"";
            [self showResult:result title:@"VPN Profile"];
        });
}

- (void)connectVPN
{
    if (self.transitionAction.length > 0) return;
    self.statusLabel.text = @"Connecting…";
    [self beginTransitionStatusPolling:@"Connecting"];
    TLinkVPNSetConnected(YES, 20.0, ^(NSDictionary *result) {
        [self endTransitionStatusPolling];
        [self showResult:result title:@"VPN Connect"];
    });
}

- (void)disconnectVPN
{
    if (self.transitionAction.length > 0) return;
    self.statusLabel.text = @"Disconnecting…";
    [self beginTransitionStatusPolling:@"Disconnecting"];
    TLinkVPNSetConnected(NO, 20.0, ^(NSDictionary *result) {
        [self endTransitionStatusPolling];
        [self showResult:result title:@"VPN Disconnect"];
    });
}

- (void)refreshStatus
{
    TLinkVPNReadManagerStatus(^(NSDictionary *result) {
        [self showResult:result title:@"VPN Status"];
    });
}

@end
