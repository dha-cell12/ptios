#import "ServiceLogViewController.h"
#import "TLinkLogStore.h"
#import "TLinkTheme.h"

@implementation TLinkServiceLogViewController {
    UITextView *_textView;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Service log";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    _textView = [[UITextView alloc] initWithFrame:CGRectZero];
    _textView.editable = NO;
    _textView.translatesAutoresizingMaskIntoConstraints = NO;
    _textView.font = [TLinkTheme logFont];
    _textView.textColor = [UIColor labelColor];
    _textView.backgroundColor = [UIColor systemBackgroundColor];
    _textView.textContainerInset = UIEdgeInsetsMake(12.0, 12.0, 12.0, 12.0);
    _textView.alwaysBounceVertical = YES;
    [self.view addSubview:_textView];

    [NSLayoutConstraint activateConstraints:@[
        [_textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_textView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash
                                                      target:self
                                                      action:@selector(clearLog)];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(logStoreDidChange:)
                                                 name:TLinkLogStoreDidAppendNotification
                                               object:nil];
    [self reloadLog:YES];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)logStoreDidChange:(NSNotification *)notification
{
    (void)notification;
    [self reloadLog:YES];
}

- (void)reloadLog:(BOOL)scrollToBottom
{
    NSArray<NSString *> *lines = [[TLinkLogStore sharedStore] allLines];
    _textView.text = [lines componentsJoinedByString:@"\n"];
    if (scrollToBottom && _textView.text.length > 0) {
        NSRange end = NSMakeRange(_textView.text.length - 1, 1);
        [_textView scrollRangeToVisible:end];
    }
}

- (void)clearLog
{
    [[TLinkLogStore sharedStore] clear];
}

@end
