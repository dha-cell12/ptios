#import "DashboardViewController.h"
#import "ServiceLogViewController.h"
#import "StreamSupervisor.h"
#import "TLinkLogStore.h"
#import "TLinkTheme.h"

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

// ---------------------------------------------------------------------------
// TLinkDashboardViewController
//
// Card-based control screen wired into the tab bar. Replaces the orphaned
// SCViewController debug screen. Uses TLinkTheme tokens + Auto Layout and
// routes all log output through the shared TLinkLogStore ring buffer.
// ---------------------------------------------------------------------------

typedef NS_ENUM(NSInteger, TLinkServiceState) {
    TLinkServiceStateStopped,
    TLinkServiceStateDegraded,
    TLinkServiceStateRunning,
};

@interface TLinkDashboardViewController () <SCStreamSupervisorDelegate>
@end

@implementation TLinkDashboardViewController {
    SCStreamSupervisor *_supervisor;
    UIView *_statusDot;
    UILabel *_statusTitleLabel;
    UILabel *_statusDetailLabel;
    UILabel *_portsLabel;
    UITextView *_logPreview;
}

- (instancetype)initWithSupervisor:(SCStreamSupervisor *)supervisor
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _supervisor = supervisor ?: [[SCStreamSupervisor alloc] init];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Overview";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"doc.plaintext"]
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(openFullLog)];

    _supervisor.delegate = self;
    [self buildUI];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(logStoreDidChange:)
                                                 name:TLinkLogStoreDidAppendNotification
                                               object:nil];

    [[TLinkLogStore sharedStore] appendLine:[NSString stringWithFormat:@"streamd path: %@", [_supervisor streamdPath]]];
    [self renderState:TLinkServiceStateStopped detail:@"stopped"];
    [self refreshLogPreview];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - UI construction

- (void)buildUI
{
    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:scrollView];

    UIStackView *stack = [TLinkTheme verticalStackWithSpacing:16.0];
    [scrollView addSubview:stack];

    CGFloat pad = [TLinkTheme cardPadding];
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [stack.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor constant:pad],
        [stack.leadingAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.leadingAnchor constant:pad],
        [stack.trailingAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.trailingAnchor constant:-pad],
        [stack.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor constant:-pad],
    ]];

    [stack addArrangedSubview:[self buildStatusCard]];
    [stack addArrangedSubview:[self buildActionsCard]];
    [stack addArrangedSubview:[self buildLogCard]];
}

- (UIView *)buildStatusCard
{
    UIView *card = [TLinkTheme cardContainerView];
    card.translatesAutoresizingMaskIntoConstraints = NO;

    _statusDot = [TLinkTheme statusDotViewWithDiameter:14.0];
    _statusDot.translatesAutoresizingMaskIntoConstraints = NO;

    _statusTitleLabel = [[UILabel alloc] init];
    _statusTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusTitleLabel.font = [TLinkTheme titleFont];
    _statusTitleLabel.adjustsFontForContentSizeCategory = YES;
    _statusTitleLabel.text = @"Service";

    _statusDetailLabel = [[UILabel alloc] init];
    _statusDetailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusDetailLabel.font = [TLinkTheme bodyFont];
    _statusDetailLabel.adjustsFontForContentSizeCategory = YES;
    _statusDetailLabel.textColor = [TLinkTheme subtleTextColor];
    _statusDetailLabel.numberOfLines = 0;
    _statusDetailLabel.text = @"stopped";

    _portsLabel = [[UILabel alloc] init];
    _portsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _portsLabel.font = [TLinkTheme captionFont];
    _portsLabel.adjustsFontForContentSizeCategory = YES;
    _portsLabel.textColor = [TLinkTheme subtleTextColor];
    _portsLabel.numberOfLines = 0;
    _portsLabel.text = @"Click 6000  \u00b7  Stream 7001-7006";

    [card addSubview:_statusDot];
    [card addSubview:_statusTitleLabel];
    [card addSubview:_statusDetailLabel];
    [card addSubview:_portsLabel];

    CGFloat pad = [TLinkTheme cardPadding];
    [NSLayoutConstraint activateConstraints:@[
        [_statusDot.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:pad],
        [_statusDot.centerYAnchor constraintEqualToAnchor:_statusTitleLabel.centerYAnchor],
        [_statusDot.widthAnchor constraintEqualToConstant:14.0],
        [_statusDot.heightAnchor constraintEqualToConstant:14.0],

        [_statusTitleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:pad],
        [_statusTitleLabel.leadingAnchor constraintEqualToAnchor:_statusDot.trailingAnchor constant:10.0],
        [_statusTitleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-pad],

        [_statusDetailLabel.topAnchor constraintEqualToAnchor:_statusTitleLabel.bottomAnchor constant:6.0],
        [_statusDetailLabel.leadingAnchor constraintEqualToAnchor:_statusTitleLabel.leadingAnchor],
        [_statusDetailLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-pad],

        [_portsLabel.topAnchor constraintEqualToAnchor:_statusDetailLabel.bottomAnchor constant:6.0],
        [_portsLabel.leadingAnchor constraintEqualToAnchor:_statusTitleLabel.leadingAnchor],
        [_portsLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-pad],
        [_portsLabel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-pad],
    ]];
    return card;
}

- (UIView *)buildActionsCard
{
    UIView *card = [TLinkTheme cardContainerView];
    card.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *ensureButton = [TLinkTheme buttonWithTitle:@"Ensure service" symbol:@"play.fill" style:TLinkButtonStylePrimary target:self action:@selector(onEnsure)];
    UIButton *stopButton = [TLinkTheme buttonWithTitle:@"Stop" symbol:@"stop.fill" style:TLinkButtonStyleDestructive target:self action:@selector(onStop)];
    UIButton *restartButton = [TLinkTheme buttonWithTitle:@"Restart streamd" symbol:@"arrow.clockwise" style:TLinkButtonStyleSecondary target:self action:@selector(onRestart)];
    UIButton *tapButton = [TLinkTheme buttonWithTitle:@"Self-test tap (center)" symbol:@"hand.tap" style:TLinkButtonStyleTinted target:self action:@selector(onSelfTestTap)];
    UIButton *captureButton = [TLinkTheme buttonWithTitle:@"Capture probe" symbol:@"camera.viewfinder" style:TLinkButtonStyleTinted target:self action:@selector(onCaptureProbe)];

    UIStackView *topRow = [[UIStackView alloc] initWithArrangedSubviews:@[ensureButton, stopButton]];
    topRow.axis = UILayoutConstraintAxisHorizontal;
    topRow.distribution = UIStackViewDistributionFillEqually;
    topRow.spacing = 12.0;

    UIStackView *stack = [TLinkTheme verticalStackWithSpacing:12.0];
    [stack addArrangedSubview:topRow];
    [stack addArrangedSubview:restartButton];
    [stack addArrangedSubview:tapButton];
    [stack addArrangedSubview:captureButton];
    [card addSubview:stack];

    CGFloat pad = [TLinkTheme cardPadding];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:pad],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:pad],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-pad],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-pad],
    ]];
    return card;
}

- (UIView *)buildLogCard
{
    UIView *card = [TLinkTheme cardContainerView];
    card.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *header = [[UILabel alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.font = [TLinkTheme headlineFont];
    header.adjustsFontForContentSizeCategory = YES;
    header.text = @"Recent log";

    UIButton *openButton = [TLinkTheme buttonWithTitle:@"View all" symbol:@"arrow.up.right" style:TLinkButtonStyleTinted target:self action:@selector(openFullLog)];
    openButton.translatesAutoresizingMaskIntoConstraints = NO;
    [openButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    _logPreview = [[UITextView alloc] initWithFrame:CGRectZero];
    _logPreview.translatesAutoresizingMaskIntoConstraints = NO;
    _logPreview.editable = NO;
    _logPreview.scrollEnabled = NO;
    _logPreview.font = [TLinkTheme logFont];
    _logPreview.backgroundColor = [UIColor clearColor];
    _logPreview.textColor = [TLinkTheme subtleTextColor];
    _logPreview.textContainerInset = UIEdgeInsetsZero;

    [card addSubview:header];
    [card addSubview:openButton];
    [card addSubview:_logPreview];

    CGFloat pad = [TLinkTheme cardPadding];
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:card.topAnchor constant:pad],
        [header.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:pad],

        [openButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [openButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:header.trailingAnchor constant:8.0],
        [openButton.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-pad],

        [_logPreview.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:10.0],
        [_logPreview.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:pad],
        [_logPreview.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-pad],
        [_logPreview.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-pad],
    ]];
    return card;
}

#pragma mark - State rendering

- (void)renderState:(TLinkServiceState)state detail:(NSString *)detail
{
    UIColor *color = nil;
    NSString *title = nil;
    switch (state) {
        case TLinkServiceStateRunning:
            color = [TLinkTheme statusRunningColor];
            title = @"Running";
            break;
        case TLinkServiceStateDegraded:
            color = [TLinkTheme statusDegradedColor];
            title = @"Degraded";
            break;
        case TLinkServiceStateStopped:
        default:
            color = [TLinkTheme statusStoppedColor];
            title = @"Stopped";
            break;
    }
    _statusDot.backgroundColor = color;
    _statusTitleLabel.text = title;
    _statusDetailLabel.text = detail.length > 0 ? detail : title;
}

#pragma mark - Log preview

- (void)logStoreDidChange:(NSNotification *)notification
{
    (void)notification;
    [self refreshLogPreview];
}

- (void)refreshLogPreview
{
    NSArray<NSString *> *lines = [[TLinkLogStore sharedStore] recentLines:6];
    _logPreview.text = [lines componentsJoinedByString:@"\n"];
}

- (void)openFullLog
{
    TLinkServiceLogViewController *logVC = [[TLinkServiceLogViewController alloc] init];
    [self.navigationController pushViewController:logVC animated:YES];
}

#pragma mark - Actions

- (void)onEnsure
{
    [_supervisor ensureService];
    [self scheduleStatusProbesWithPrefix:@"ensure"];
}

- (void)onRestart
{
    [_supervisor restart];
    [self scheduleStatusProbesWithPrefix:@"restart"];
}

- (void)onStop
{
    [_supervisor stop];
}

- (void)scheduleStatusProbesWithPrefix:(NSString *)prefix
{
    [[TLinkLogStore sharedStore] appendLine:[NSString stringWithFormat:@"%@: status probe scheduled; checking task 97", prefix]];
    [self scheduleStatusProbeAfter:0.8 label:[NSString stringWithFormat:@"%@ probe #1", prefix]];
    [self scheduleStatusProbeAfter:2.0 label:[NSString stringWithFormat:@"%@ probe #2", prefix]];
    [self scheduleStatusProbeAfter:4.0 label:[NSString stringWithFormat:@"%@ probe #3", prefix]];
}

- (void)scheduleStatusProbeAfter:(double)seconds label:(NSString *)label
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *resp = [self sendToClickPortAndRead:@"97\n"];
        [[TLinkLogStore sharedStore] appendLine:[NSString stringWithFormat:@"%@: %@", label, resp ?: @"<nil>"]];
    });
}

- (void)onCaptureProbe
{
    [[TLinkLogStore sharedStore] appendLine:@"capture probe: checking task 97 then sending task 98"];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *status = [self sendToClickPortAndRead:@"97\n"];
        [[TLinkLogStore sharedStore] appendLine:[NSString stringWithFormat:@"streamd status response: %@", status ?: @"<no response>"]];
        NSString *resp = [self sendToClickPortAndRead:@"98\n"];
        [[TLinkLogStore sharedStore] appendLine:[NSString stringWithFormat:@"capture probe response: %@", resp ?: @"<no response>"]];
    });
}

// Send a legacy task-10 tap at screen center to streamd's click port (6000).
- (void)onSelfTestTap
{
    CGFloat scale = [UIScreen mainScreen].scale;
    CGSize sz = [UIScreen mainScreen].bounds.size;
    int xPx = (int)(sz.width * scale / 2.0);
    int yPx = (int)(sz.height * scale / 2.0);

    // Legacy wire: "10" + count(1) + [type(1) index(2) x(5) y(5)].
    // Matches poc-trollstore: type 1=down, 0=up, 2=move; x/y are *10 fixed.
    NSString *down = [NSString stringWithFormat:@"101101%05d%05d\n", xPx * 10, yPx * 10];
    NSString *up   = [NSString stringWithFormat:@"101001%05d%05d\n", xPx * 10, yPx * 10];

    [[TLinkLogStore sharedStore] appendLine:[NSString stringWithFormat:@"self-test tap (%d,%d)px", xPx, yPx]];
    [self sendToClickPort:down];
    usleep(60000);
    [self sendToClickPort:up];
}

#pragma mark - Socket helpers (loopback to streamd click port 6000)

- (void)sendToClickPort:(NSString *)msg
{
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) { [[TLinkLogStore sharedStore] appendLine:@"socket: socket() failed"]; return; }

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(6000);
    inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);

    if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        [[TLinkLogStore sharedStore] appendLine:@"socket: connect 127.0.0.1:6000 failed (streamd running?)"];
        close(sock);
        return;
    }
    const char *buf = [msg UTF8String];
    send(sock, buf, strlen(buf), 0);
    close(sock);
}

- (NSString *)sendToClickPortAndRead:(NSString *)msg
{
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) return [NSString stringWithFormat:@"socket() failed errno=%d", errno];

    struct timeval tv;
    tv.tv_sec = 8;
    tv.tv_usec = 0;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(6000);
    inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);

    if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(sock);
        return [NSString stringWithFormat:@"connect 127.0.0.1:6000 failed errno=%d", errno];
    }

    const char *buf = [msg UTF8String];
    send(sock, buf, strlen(buf), 0);

    char resp[1024];
    ssize_t n = recv(sock, resp, sizeof(resp) - 1, 0);
    close(sock);

    if (n <= 0) return [NSString stringWithFormat:@"no response / timeout errno=%d", errno];
    resp[n] = 0;
    NSString *s = [NSString stringWithUTF8String:resp];
    return s ?: @"non-utf8 response";
}

#pragma mark - SCStreamSupervisorDelegate

- (void)supervisorDidLog:(NSString *)line
{
    [[TLinkLogStore sharedStore] appendLine:line];
}

- (void)supervisorDidChangeRunning:(BOOL)running pid:(pid_t)pid
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (running) {
            NSString *detail = pid > 0
                ? [NSString stringWithFormat:@"running (pid %d)", pid]
                : @"running (service-managed)";
            [self renderState:TLinkServiceStateRunning detail:detail];
        } else {
            [self renderState:TLinkServiceStateStopped detail:@"stopped"];
        }
    });
}

@end
