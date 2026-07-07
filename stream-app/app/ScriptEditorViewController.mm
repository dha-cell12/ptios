#import "ScriptEditorViewController.h"

@interface SCScriptEditorViewController () <UITextViewDelegate>
@end

@implementation SCScriptEditorViewController {
    NSString *_filePath;
    UITextView *_textView;
    BOOL _dirty;
}

- (instancetype)initWithFilePath:(NSString *)filePath
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _filePath = [filePath copy];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = _filePath.lastPathComponent ?: @"Editor";

    _textView = [[UITextView alloc] initWithFrame:CGRectZero];
    _textView.translatesAutoresizingMaskIntoConstraints = NO;
    _textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _textView.alwaysBounceVertical = YES;
    _textView.delegate = self;
    _textView.font = [UIFont monospacedSystemFontOfSize:14.0 weight:UIFontWeightRegular];
    _textView.textColor = [UIColor labelColor];
    _textView.backgroundColor = [UIColor systemBackgroundColor];
    _textView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    _textView.autocorrectionType = UITextAutocorrectionTypeNo;
    _textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _textView.smartQuotesType = UITextSmartQuotesTypeNo;
    _textView.smartDashesType = UITextSmartDashesTypeNo;
    _textView.textContainerInset = UIEdgeInsetsMake(14.0, 12.0, 14.0, 12.0);
    [self.view addSubview:_textView];

    [NSLayoutConstraint activateConstraints:@[
        [_textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_textView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                                                           target:self
                                                                                           action:@selector(saveFile)];
    [self loadFile];
}

- (void)loadFile
{
    NSError *err = nil;
    NSString *text = [NSString stringWithContentsOfFile:_filePath encoding:NSUTF8StringEncoding error:&err];
    if (!text && err) {
        text = [NSString stringWithFormat:@"// Could not read file: %@\n", err.localizedDescription ?: @"read failed"];
    }
    _textView.text = text ?: @"";
    _dirty = NO;
}

- (void)showMessageWithTitle:(NSString *)title message:(NSString *)message
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)saveFile
{
    NSError *err = nil;
    BOOL ok = [(_textView.text ?: @"") writeToFile:_filePath
                                        atomically:YES
                                          encoding:NSUTF8StringEncoding
                                             error:&err];
    if (!ok) {
        [self showMessageWithTitle:@"Save" message:err.localizedDescription ?: @"write failed"];
        return;
    }
    _dirty = NO;
    [self showMessageWithTitle:@"Save" message:@"Saved"];
}

- (void)textViewDidChange:(UITextView *)textView
{
    (void)textView;
    _dirty = YES;
}

@end
