#import "TLinkVPNSettingsViewController.h"

#import "../../../shared/TLinkVPNManager.h"

@interface TLinkVPNSettingsViewController ()
@property(nonatomic, strong) UISegmentedControl *protocolControl;
@property(nonatomic, strong) UITextField *serverField;
@property(nonatomic, strong) UITextField *remoteIdentifierField;
@property(nonatomic, strong) UITextField *usernameField;
@property(nonatomic, strong) UITextField *passwordField;
@property(nonatomic, strong) UITextField *sharedSecretField;
@property(nonatomic, strong) UITextField *groupField;
@property(nonatomic, strong) UILabel *securityLabel;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UISwitch *onDemandSwitch;
@property(nonatomic, strong) UIStackView *onDemandRow;
@property(nonatomic, strong) UIActivityIndicatorView *transitionSpinner;
@property(nonatomic, strong) UIButton *saveProfileButton;
@property(nonatomic, copy) NSString *activeProtocolType;
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
    [button addTarget:self action:action
      forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (NSString *)selectedProtocolType
{
    NSInteger index = self.protocolControl.selectedSegmentIndex;
    if (index < 0 || index >= self.protocolControl.numberOfSegments) {
        return @"IKEv2";
    }
    return [self.protocolControl titleForSegmentAtIndex:index] ?: @"IKEv2";
}

- (NSString *)defaultsKey:(NSString *)base protocol:(NSString *)protocol
{
    return [NSString stringWithFormat:@"%@.%@", base, protocol ?: @"IKEv2"];
}

- (void)persistNonSecretFieldsForProtocol:(NSString *)protocol
{
    if (protocol.length == 0) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:self.serverField.text ?: @""
                 forKey:[self defaultsKey:@"TLinkVPNServerAddress"
                                  protocol:protocol]];
    [defaults setObject:self.usernameField.text ?: @""
                 forKey:[self defaultsKey:@"TLinkVPNUsername"
                                  protocol:protocol]];
    [defaults setObject:self.groupField.text ?: @""
                 forKey:[self defaultsKey:@"TLinkVPNGroup"
                                  protocol:protocol]];
    if ([protocol isEqualToString:@"IKEv2"]) {
        [defaults setObject:self.remoteIdentifierField.text ?: @""
                     forKey:[self defaultsKey:@"TLinkVPNRemoteIdentifier"
                                      protocol:protocol]];
        // Preserve the original IKEv2-only keys during an app upgrade.
        [defaults setObject:self.serverField.text ?: @""
                     forKey:@"TLinkVPNServerAddress"];
        [defaults setObject:self.remoteIdentifierField.text ?: @""
                     forKey:@"TLinkVPNRemoteIdentifier"];
        [defaults setObject:self.usernameField.text ?: @""
                     forKey:@"TLinkVPNUsername"];
    }
}

- (void)loadNonSecretFieldsForProtocol:(NSString *)protocol
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *server = [defaults stringForKey:
        [self defaultsKey:@"TLinkVPNServerAddress" protocol:protocol]];
    NSString *username = [defaults stringForKey:
        [self defaultsKey:@"TLinkVPNUsername" protocol:protocol]];
    if ([protocol isEqualToString:@"IKEv2"]) {
        server = server ?: [defaults stringForKey:@"TLinkVPNServerAddress"];
        username = username ?: [defaults stringForKey:@"TLinkVPNUsername"];
    }
    self.serverField.text = server ?: @"";
    self.usernameField.text = username ?: @"";
    self.remoteIdentifierField.text = [defaults stringForKey:
        [self defaultsKey:@"TLinkVPNRemoteIdentifier" protocol:protocol]]
        ?: ([protocol isEqualToString:@"IKEv2"]
            ? [defaults stringForKey:@"TLinkVPNRemoteIdentifier"] : @"");
    self.groupField.text = [defaults stringForKey:
        [self defaultsKey:@"TLinkVPNGroup" protocol:protocol]] ?: @"";
    // TLink never persists these two secrets in its own preferences.
    self.passwordField.text = @"";
    self.sharedSecretField.text = @"";
}

- (void)updateProtocolControls
{
    NSString *protocol = [self selectedProtocolType];
    BOOL ikev2 = [protocol isEqualToString:@"IKEv2"];
    BOOL pptp = [protocol isEqualToString:@"PPTP"];
    BOOL l2tp = [protocol isEqualToString:@"L2TP"];
    self.serverField.placeholder = [NSString stringWithFormat:
        @"%@ server address", protocol];
    self.remoteIdentifierField.hidden = !ikev2;
    self.sharedSecretField.hidden = ikev2 || pptp;
    self.sharedSecretField.placeholder = l2tp
        ? @"IPSec shared secret (required)"
        : @"Shared secret (optional)";
    self.groupField.hidden = ikev2 || pptp;
    self.onDemandRow.hidden = !ikev2;
    self.onDemandSwitch.enabled = ikev2;
    [self.saveProfileButton setTitle:
        [NSString stringWithFormat:@"Save %@ Profile", protocol]
                              forState:UIControlStateNormal];
    self.securityLabel.text = ikev2
        ? @"IKEv2 uses Apple's NEVPNManager and ThisDeviceOnly Keychain. "
           "iOS may request approval once. Auto-Reconnect is supported."
        : @"PPTP/L2TP/IPSec use the TrollStore private VPNConnectionStore "
           "compatibility path mirrored from XXTouch, so saving does not "
           "show the iOS approval sheet. L2TP requires a separate IPSec "
           "shared secret in addition to the account password. Secrets are "
           "passed directly to the system store and are not retained by "
           "TLink. Auto-Reconnect is unavailable for this backend.";
}

- (void)protocolChanged:(UISegmentedControl *)sender
{
    (void)sender;
    [self persistNonSecretFieldsForProtocol:self.activeProtocolType];
    self.activeProtocolType = [self selectedProtocolType];
    [[NSUserDefaults standardUserDefaults]
        setObject:self.activeProtocolType forKey:@"TLinkVPNProtocolType"];
    [self loadNonSecretFieldsForProtocol:self.activeProtocolType];
    [self updateProtocolControls];
    [self refreshStatus];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Managed VPN";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray<NSString *> *protocols = @[@"IKEv2", @"PPTP", @"L2TP", @"IPSec"];
    self.protocolControl = [[UISegmentedControl alloc] initWithItems:protocols];
    NSString *savedProtocol =
        [defaults stringForKey:@"TLinkVPNProtocolType"] ?: @"IKEv2";
    NSUInteger savedIndex = [protocols indexOfObject:savedProtocol];
    self.protocolControl.selectedSegmentIndex =
        savedIndex == NSNotFound ? 0 : (NSInteger)savedIndex;
    [self.protocolControl addTarget:self
                             action:@selector(protocolChanged:)
                   forControlEvents:UIControlEventValueChanged];
    self.activeProtocolType = [self selectedProtocolType];

    self.serverField = [self fieldWithPlaceholder:@"Server address" secure:NO];
    self.remoteIdentifierField = [self
        fieldWithPlaceholder:@"Remote identifier (defaults to server)"
                      secure:NO];
    self.usernameField = [self fieldWithPlaceholder:@"Username" secure:NO];
    self.passwordField = [self fieldWithPlaceholder:@"Password" secure:YES];
    self.sharedSecretField =
        [self fieldWithPlaceholder:@"Shared secret (optional)" secure:YES];
    self.groupField =
        [self fieldWithPlaceholder:@"Group (optional)" secure:NO];
    [self loadNonSecretFieldsForProtocol:self.activeProtocolType];

    self.securityLabel = [[UILabel alloc] init];
    self.securityLabel.numberOfLines = 0;
    self.securityLabel.font = [UIFont systemFontOfSize:12];
    self.securityLabel.textColor = [UIColor secondaryLabelColor];

    UILabel *onDemandLabel = [[UILabel alloc] init];
    onDemandLabel.text = @"Auto-Reconnect (On Demand)";
    onDemandLabel.font = [UIFont systemFontOfSize:16];
    self.onDemandSwitch = [[UISwitch alloc] init];
    [self.onDemandSwitch addTarget:self
                            action:@selector(onDemandChanged:)
                  forControlEvents:UIControlEventValueChanged];
    self.onDemandRow = [[UIStackView alloc]
        initWithArrangedSubviews:@[onDemandLabel, self.onDemandSwitch]];
    self.onDemandRow.axis = UILayoutConstraintAxisHorizontal;
    self.onDemandRow.alignment = UIStackViewAlignmentCenter;
    self.onDemandRow.distribution = UIStackViewDistributionEqualSpacing;

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont monospacedSystemFontOfSize:12
                                                      weight:UIFontWeightRegular];
    self.statusLabel.text = @"Status: loading";

    self.transitionSpinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.transitionSpinner.hidesWhenStopped = YES;

    self.saveProfileButton =
        [self buttonWithTitle:@"Save Profile" action:@selector(saveProfile)];
    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.saveProfileButton,
        [self buttonWithTitle:@"Connect" action:@selector(connectVPN)],
        [self buttonWithTitle:@"Disconnect" action:@selector(disconnectVPN)],
        [self buttonWithTitle:@"Refresh" action:@selector(refreshStatus)],
    ]];
    buttons.axis = UILayoutConstraintAxisVertical;
    buttons.spacing = 8;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.protocolControl,
        self.serverField,
        self.remoteIdentifierField,
        self.usernameField,
        self.passwordField,
        self.sharedSecretField,
        self.groupField,
        self.securityLabel,
        self.onDemandRow,
        buttons,
        self.transitionSpinner,
        self.statusLabel,
    ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;

    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scrollView];
    [scrollView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor constant:20],
        [stack.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor constant:-20],
        [stack.widthAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor constant:-40],
    ]];
    [self updateProtocolControls];
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
            ? result[@"connection_status"] : @"unknown";
        NSString *code = [result[@"code"] isKindOfClass:[NSString class]]
            ? result[@"code"] : @"vpn_status_unknown";
        self.statusLabel.text = [NSString stringWithFormat:
            @"%@... %.0fs\nConnection: %@\nStatus probe: %@",
            self.transitionAction, elapsed, connection, code];

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
            ? result[@"code"] : @"unknown";
        NSString *connection = [result[@"connection_status"]
            isKindOfClass:[NSString class]]
            ? result[@"connection_status"] : @"unknown";
        NSNumber *osStatus = [result[@"os_status"] isKindOfClass:[NSNumber class]]
            ? result[@"os_status"] : nil;
        NSString *nativeError = [result[@"native_error"]
            isKindOfClass:[NSString class]] ? result[@"native_error"] : @"";
        NSNumber *onDemand = [result[@"on_demand_enabled"]
            isKindOfClass:[NSNumber class]] ? result[@"on_demand_enabled"] : nil;
        NSString *profileType = [result[@"profile_type"]
            isKindOfClass:[NSString class]] ? result[@"profile_type"] : @"";
        NSString *backend = [result[@"backend"] isKindOfClass:[NSString class]]
            ? result[@"backend"] : @"unknown";
        NSString *approvalPath = [result[@"approval_path"]
            isKindOfClass:[NSString class]] ? result[@"approval_path"] : @"unknown";
        if (onDemand) {
            [self.onDemandSwitch setOn:onDemand.boolValue animated:YES];
        }
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
            @"Code: %@\nType: %@\nBackend: %@\nApproval path: %@\nConfigured: %@\nEnabled: %@\nAuto-Reconnect: %@\nConnection: %@%@",
            code,
            profileType.length > 0 ? profileType : [self selectedProtocolType],
            backend,
            approvalPath,
            [result[@"configured"] boolValue] ? @"yes" : @"no",
            [result[@"enabled"] boolValue] ? @"yes" : @"no",
            onDemand.boolValue ? @"on" : @"off",
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

- (void)onDemandChanged:(UISwitch *)sender
{
    BOOL requested = sender.isOn;
    sender.enabled = NO;
    self.statusLabel.text = requested
        ? @"Enabling Auto-Reconnect..."
        : @"Disabling Auto-Reconnect...";
    TLinkVPNSetOnDemandEnabled(requested, ^(NSDictionary *result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            sender.enabled = YES;
            if (![result[@"ok"] boolValue] &&
                ![result[@"on_demand_enabled"] isKindOfClass:[NSNumber class]]) {
                [sender setOn:!requested animated:YES];
            }
            [self showResult:result title:@"VPN Auto-Reconnect"];
        });
    });
}

- (void)saveProfile
{
    if (!self.saveProfileButton.enabled) return;
    self.saveProfileButton.enabled = NO;
    [self.transitionSpinner startAnimating];
    NSString *server = self.serverField.text ?: @"";
    NSString *remote = self.remoteIdentifierField.text ?: @"";
    NSString *username = self.usernameField.text ?: @"";
    NSString *password = self.passwordField.text ?: @"";
    NSString *sharedSecret = self.sharedSecretField.text ?: @"";
    NSString *group = self.groupField.text ?: @"";
    NSString *protocol = [self selectedProtocolType];

    [self persistNonSecretFieldsForProtocol:protocol];
    TLinkVPNResultCompletion saved = ^(NSDictionary *result) {
        self.saveProfileButton.enabled = YES;
        [self.transitionSpinner stopAnimating];
        self.passwordField.text = @"";
        self.sharedSecretField.text = @"";
        [self showResult:result title:@"VPN Profile"];
    };
    if ([protocol isEqualToString:@"IKEv2"]) {
        self.statusLabel.text = @"Saving the native TLink-owned IKEv2 profile... iOS may request one-time approval.";
        TLinkVPNConfigureIKEv2(server, remote, username, password, saved);
    } else {
        self.statusLabel.text = [NSString stringWithFormat:
            @"Saving %@ through the no-confirm private backend...", protocol];
        TLinkVPNConfigureLegacyPrivate(
            protocol, server, username, password, sharedSecret, group, saved);
    }
}

- (void)connectVPN
{
    if (self.transitionAction.length > 0) return;
    self.statusLabel.text = @"Connecting...";
    [self beginTransitionStatusPolling:@"Connecting"];
    TLinkVPNSetConnected(YES, 20.0, ^(NSDictionary *result) {
        [self endTransitionStatusPolling];
        [self showResult:result title:@"VPN Connect"];
    });
}

- (void)disconnectVPN
{
    if (self.transitionAction.length > 0) return;
    self.statusLabel.text = @"Disconnecting... For IKEv2 this explicitly also disables Auto-Reconnect.";
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
