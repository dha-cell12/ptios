#import "ScriptLogViewController.h"
#import "TLinkSocketClient.h"

@implementation SCScriptLogViewController {
    UITextView *_textView;
    NSTimer *_timer;
    BOOL _refreshInFlight;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Logs";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    _textView = [[UITextView alloc] initWithFrame:CGRectZero];
    _textView.translatesAutoresizingMaskIntoConstraints = NO;
    _textView.editable = NO;
    _textView.alwaysBounceVertical = YES;
    _textView.font = [UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightRegular];
    _textView.textColor = [UIColor labelColor];
    _textView.backgroundColor = [UIColor systemBackgroundColor];
    _textView.textContainerInset = UIEdgeInsetsMake(14.0, 12.0, 14.0, 12.0);
    [self.view addSubview:_textView];

    [NSLayoutConstraint activateConstraints:@[
        [_textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_textView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                           target:self
                                                                                           action:@selector(refresh)];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self refresh];
    _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [_timer invalidate];
    _timer = nil;
}

- (void)refresh
{
    if (_refreshInFlight) return;
    _refreshInFlight = YES;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *response = [TLinkSocketClient requestTask:60 args:@[] timeout:4.0];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_refreshInFlight = NO;
            [self renderStatusResponse:response];
        });
    });
}

- (NSString *)stringValue:(id)value
{
    if ([value isKindOfClass:[NSString class]]) return value;
    if ([value respondsToSelector:@selector(stringValue)]) return [value stringValue];
    return @"";
}

- (void)renderStatusResponse:(NSString *)response
{
    if (![response hasPrefix:@"0;;"]) {
        _textView.text = response ?: @"<nil>";
        return;
    }
    NSString *payload = [[response substringFromIndex:3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSData *jsonData = [[NSData alloc] initWithBase64EncodedString:payload options:0];
    NSDictionary *status = jsonData.length > 0 ? [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil] : nil;
    if (![status isKindOfClass:[NSDictionary class]]) {
        _textView.text = response ?: @"<decode failed>";
        return;
    }

    NSDictionary *script = [status[@"script"] isKindOfClass:[NSDictionary class]] ? status[@"script"] : @{};
    NSMutableString *text = [NSMutableString string];
    [text appendFormat:@"state: %@\n", [self stringValue:script[@"state"]]];
    [text appendFormat:@"playing: %@\n", [script[@"is_playing"] boolValue] ? @"yes" : @"no"];
    [text appendFormat:@"session: %@\n", [self stringValue:script[@"session_id"]]];
    [text appendFormat:@"entry: %@\n", [self stringValue:script[@"entry_path"]]];
    [text appendFormat:@"last_error: %@\n", [self stringValue:script[@"last_error"]]];
    [text appendString:@"\n"];

    NSArray *tail = [script[@"log_tail"] isKindOfClass:[NSArray class]] ? script[@"log_tail"] : @[];
    if (tail.count == 0) {
        [text appendString:@"<no script log lines>\n"];
    } else {
        for (id line in tail) {
            [text appendFormat:@"%@\n", [self stringValue:line]];
        }
    }
    _textView.text = text;
}

@end
