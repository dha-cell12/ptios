#import "ScriptEditorViewController.h"

@interface SCScriptEditorViewController () <UITextViewDelegate, UITextFieldDelegate>
@end

@implementation SCScriptEditorViewController {
    NSString *_filePath;
    UITextView *_textView;
    UIView *_findBar;
    UITextField *_findField;
    UILabel *_statusLabel;
    NSLayoutConstraint *_findBarHeight;
    UIBarButtonItem *_saveButton;
    UIBarButtonItem *_toolsButton;
    CGFloat _fontSize;
    BOOL _dirty;
    BOOL _restoreInteractivePopGesture;
}

- (instancetype)initWithFilePath:(NSString *)filePath
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _filePath = [filePath copy];
        _fontSize = 14.0;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    [self buildNavigationItems];
    [self buildFindBar];
    [self buildEditor];
    [self buildStatusBar];
    [self activateEditorConstraints];
    [self loadFile];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (self.navigationController.interactivePopGestureRecognizer) {
        _restoreInteractivePopGesture = self.navigationController.interactivePopGestureRecognizer.enabled;
        self.navigationController.interactivePopGestureRecognizer.enabled = NO;
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    if (self.navigationController.interactivePopGestureRecognizer) {
        self.navigationController.interactivePopGestureRecognizer.enabled = _restoreInteractivePopGesture;
    }
}

- (void)buildNavigationItems
{
    UIImage *backImage = [UIImage systemImageNamed:@"chevron.left"];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithImage:backImage
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(attemptClose)];
    self.navigationItem.leftBarButtonItem.accessibilityLabel = @"Back";

    _saveButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                               target:self
                                                               action:@selector(saveFile)];
    UIImage *toolsImage = [UIImage systemImageNamed:@"ellipsis.circle"];
    _toolsButton = [[UIBarButtonItem alloc] initWithImage:toolsImage
                                                    style:UIBarButtonItemStylePlain
                                                   target:self
                                                   action:@selector(showTools:)];
    _toolsButton.accessibilityLabel = @"Editor tools";
    self.navigationItem.rightBarButtonItems = @[_saveButton, _toolsButton];
}

- (UIButton *)findButtonWithImage:(NSString *)imageName
               accessibilityLabel:(NSString *)accessibilityLabel
                            action:(SEL)action
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setImage:[UIImage systemImageNamed:imageName] forState:UIControlStateNormal];
    button.accessibilityLabel = accessibilityLabel;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.widthAnchor constraintEqualToConstant:36.0].active = YES;
    return button;
}

- (void)buildFindBar
{
    _findBar = [[UIView alloc] initWithFrame:CGRectZero];
    _findBar.translatesAutoresizingMaskIntoConstraints = NO;
    _findBar.backgroundColor = [UIColor secondarySystemBackgroundColor];
    _findBar.clipsToBounds = YES;
    [self.view addSubview:_findBar];

    _findField = [[UITextField alloc] initWithFrame:CGRectZero];
    _findField.translatesAutoresizingMaskIntoConstraints = NO;
    _findField.placeholder = @"Find in file";
    _findField.borderStyle = UITextBorderStyleRoundedRect;
    _findField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _findField.autocorrectionType = UITextAutocorrectionTypeNo;
    _findField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _findField.returnKeyType = UIReturnKeySearch;
    _findField.delegate = self;
    [_findField addTarget:self action:@selector(findTextDidChange:) forControlEvents:UIControlEventEditingChanged];

    UIButton *previous = [self findButtonWithImage:@"chevron.up"
                                accessibilityLabel:@"Previous match"
                                             action:@selector(findPrevious)];
    UIButton *next = [self findButtonWithImage:@"chevron.down"
                            accessibilityLabel:@"Next match"
                                         action:@selector(findNext)];
    UIButton *close = [self findButtonWithImage:@"xmark"
                             accessibilityLabel:@"Close find"
                                          action:@selector(hideFind)];
    [_findBar addSubview:_findField];
    [_findBar addSubview:previous];
    [_findBar addSubview:next];
    [_findBar addSubview:close];

    [NSLayoutConstraint activateConstraints:@[
        [_findField.leadingAnchor constraintEqualToAnchor:_findBar.leadingAnchor constant:10.0],
        [_findField.centerYAnchor constraintEqualToAnchor:_findBar.centerYAnchor],
        [_findField.trailingAnchor constraintEqualToAnchor:previous.leadingAnchor constant:-4.0],
        [previous.centerYAnchor constraintEqualToAnchor:_findBar.centerYAnchor],
        [next.leadingAnchor constraintEqualToAnchor:previous.trailingAnchor],
        [next.centerYAnchor constraintEqualToAnchor:_findBar.centerYAnchor],
        [close.leadingAnchor constraintEqualToAnchor:next.trailingAnchor],
        [close.trailingAnchor constraintEqualToAnchor:_findBar.trailingAnchor constant:-4.0],
        [close.centerYAnchor constraintEqualToAnchor:_findBar.centerYAnchor],
    ]];
}

- (void)buildEditor
{
    _textView = [[UITextView alloc] initWithFrame:CGRectZero];
    _textView.translatesAutoresizingMaskIntoConstraints = NO;
    _textView.alwaysBounceVertical = YES;
    _textView.delegate = self;
    _textView.font = [UIFont monospacedSystemFontOfSize:_fontSize weight:UIFontWeightRegular];
    _textView.textColor = [UIColor labelColor];
    _textView.backgroundColor = [UIColor systemBackgroundColor];
    _textView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    _textView.autocorrectionType = UITextAutocorrectionTypeNo;
    _textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _textView.smartQuotesType = UITextSmartQuotesTypeNo;
    _textView.smartDashesType = UITextSmartDashesTypeNo;
    _textView.spellCheckingType = UITextSpellCheckingTypeNo;
    _textView.textContainerInset = UIEdgeInsetsMake(12.0, 10.0, 18.0, 10.0);
    _textView.inputAccessoryView = [self editorKeyboardToolbar];
    [self.view addSubview:_textView];
}

- (void)buildStatusBar
{
    _statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.backgroundColor = [UIColor secondarySystemBackgroundColor];
    _statusLabel.textColor = [UIColor secondaryLabelColor];
    _statusLabel.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular];
    _statusLabel.textAlignment = NSTextAlignmentRight;
    _statusLabel.numberOfLines = 1;
    [self.view addSubview:_statusLabel];
}

- (void)activateEditorConstraints
{
    _findBarHeight = [_findBar.heightAnchor constraintEqualToConstant:0.0];
    [NSLayoutConstraint activateConstraints:@[
        [_findBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_findBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_findBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        _findBarHeight,
        [_textView.topAnchor constraintEqualToAnchor:_findBar.bottomAnchor],
        [_textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_textView.bottomAnchor constraintEqualToAnchor:_statusLabel.topAnchor],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_statusLabel.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [_statusLabel.heightAnchor constraintEqualToConstant:24.0],
    ]];
}

- (UIBarButtonItem *)toolbarItemWithTitle:(NSString *)title action:(SEL)action
{
    return [[UIBarButtonItem alloc] initWithTitle:title
                                            style:UIBarButtonItemStylePlain
                                           target:self
                                           action:action];
}

- (UIToolbar *)editorKeyboardToolbar
{
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 0, 44)];
    UIBarButtonItem *undo = [self toolbarItemWithTitle:@"Undo" action:@selector(undoEditing)];
    UIBarButtonItem *redo = [self toolbarItemWithTitle:@"Redo" action:@selector(redoEditing)];
    UIBarButtonItem *tab = [self toolbarItemWithTitle:@"Tab" action:@selector(indentSelection)];
    UIBarButtonItem *braces = [self toolbarItemWithTitle:@"{}" action:@selector(insertBraces)];
    UIBarButtonItem *parentheses = [self toolbarItemWithTitle:@"()" action:@selector(insertParentheses)];
    UIBarButtonItem *quotes = [self toolbarItemWithTitle:@"\"\"" action:@selector(insertQuotes)];
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                         target:self
                                                                         action:@selector(dismissKeyboard)];
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                          target:nil
                                                                          action:nil];
    toolbar.items = @[undo, redo, flex, tab, braces, parentheses, quotes, flex, done];
    return toolbar;
}

- (void)loadFile
{
    NSError *error = nil;
    NSString *text = [NSString stringWithContentsOfFile:_filePath
                                               encoding:NSUTF8StringEncoding
                                                  error:&error];
    if (!text && error) {
        text = [NSString stringWithFormat:@"// Could not read file: %@\n",
                error.localizedDescription ?: @"read failed"];
    }
    _textView.text = text ?: @"";
    [self setDirty:NO];
    [self updateCursorStatus];
}

- (void)setDirty:(BOOL)dirty
{
    _dirty = dirty;
    _saveButton.enabled = dirty;
    NSString *name = _filePath.lastPathComponent ?: @"Editor";
    self.title = dirty ? [NSString stringWithFormat:@"%@ *", name] : name;
}

- (void)showTransientStatus:(NSString *)message
{
    self.navigationItem.prompt = message;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if ([self.navigationItem.prompt isEqualToString:message]) {
            self.navigationItem.prompt = nil;
        }
    });
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
    NSError *error = nil;
    BOOL saved = [(_textView.text ?: @"") writeToFile:_filePath
                                            atomically:YES
                                              encoding:NSUTF8StringEncoding
                                                 error:&error];
    if (!saved) {
        [self showMessageWithTitle:@"Save Failed" message:error.localizedDescription ?: @"write failed"];
        return;
    }
    [self setDirty:NO];
    [self showTransientStatus:@"Saved"];
}

- (void)attemptClose
{
    if (!_dirty) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Unsaved Changes"
                                                                   message:@"Save main.js before closing?"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Discard"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *action) {
        [self.navigationController popViewControllerAnimated:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [self saveFile];
        if (!self->_dirty) [self.navigationController popViewControllerAnimated:YES];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showFind
{
    _findBarHeight.constant = 48.0;
    [UIView animateWithDuration:0.2 animations:^{
        [self.view layoutIfNeeded];
    }];
    [_findField becomeFirstResponder];
    if (_textView.selectedRange.length > 0 && _textView.selectedRange.length < 128) {
        _findField.text = [_textView.text substringWithRange:_textView.selectedRange];
    }
}

- (void)hideFind
{
    [_findField resignFirstResponder];
    _findBarHeight.constant = 0.0;
    [UIView animateWithDuration:0.2 animations:^{
        [self.view layoutIfNeeded];
    }];
}

- (BOOL)findForward:(BOOL)forward
{
    NSString *needle = _findField.text ?: @"";
    NSString *source = _textView.text ?: @"";
    if (needle.length == 0 || source.length == 0) return NO;

    NSStringCompareOptions options = NSCaseInsensitiveSearch;
    NSRange range = NSMakeRange(0, 0);
    if (forward) {
        NSUInteger start = NSMaxRange(_textView.selectedRange);
        if (start > source.length) start = source.length;
        range = [source rangeOfString:needle
                             options:options
                               range:NSMakeRange(start, source.length - start)];
        if (range.location == NSNotFound && start > 0) {
            range = [source rangeOfString:needle options:options range:NSMakeRange(0, start)];
        }
    } else {
        options |= NSBackwardsSearch;
        NSUInteger end = MIN(_textView.selectedRange.location, source.length);
        range = [source rangeOfString:needle options:options range:NSMakeRange(0, end)];
        if (range.location == NSNotFound && end < source.length) {
            range = [source rangeOfString:needle
                                 options:options
                                   range:NSMakeRange(end, source.length - end)];
        }
    }
    if (range.location == NSNotFound) {
        [self showTransientStatus:@"No match"];
        return NO;
    }
    _textView.selectedRange = range;
    [_textView scrollRangeToVisible:range];
    [self updateCursorStatus];
    return YES;
}

- (void)findNext
{
    [self findForward:YES];
}

- (void)findPrevious
{
    [self findForward:NO];
}

- (void)findTextDidChange:(UITextField *)field
{
    (void)field;
    if (_findField.text.length > 0) [self findForward:YES];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    (void)textField;
    [self findNext];
    return NO;
}

- (void)replaceAll
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Replace All"
                                                                   message:@"Replacement is case-insensitive."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Find";
        field.text = self->_findField.text;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Replace with";
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Replace"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        NSString *needle = alert.textFields.firstObject.text ?: @"";
        NSString *replacement = alert.textFields.lastObject.text ?: @"";
        if (needle.length == 0) return;
        NSString *before = self->_textView.text ?: @"";
        NSString *after = [before stringByReplacingOccurrencesOfString:needle
                                                            withString:replacement
                                                               options:NSCaseInsensitiveSearch
                                                                 range:NSMakeRange(0, before.length)];
        if (![after isEqualToString:before]) {
            self->_textView.text = after;
            [self setDirty:YES];
            [self updateCursorStatus];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)goToLine
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Go To Line"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Line number";
        field.keyboardType = UIKeyboardTypeNumberPad;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Go"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        NSInteger target = MAX(1, [alert.textFields.firstObject.text integerValue]);
        NSString *text = self->_textView.text ?: @"";
        __block NSInteger line = 1;
        __block NSUInteger location = 0;
        [text enumerateSubstringsInRange:NSMakeRange(0, text.length)
                                 options:NSStringEnumerationByLines | NSStringEnumerationSubstringNotRequired
                              usingBlock:^(__unused NSString *substring,
                                           NSRange substringRange,
                                           __unused NSRange enclosingRange,
                                           BOOL *stop) {
            if (line == target) {
                location = substringRange.location;
                *stop = YES;
            } else {
                line++;
                location = NSMaxRange(enclosingRange);
            }
        }];
        location = MIN(location, text.length);
        self->_textView.selectedRange = NSMakeRange(location, 0);
        [self->_textView scrollRangeToVisible:self->_textView.selectedRange];
        [self->_textView becomeFirstResponder];
        [self updateCursorStatus];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)changeFontSize:(CGFloat)delta
{
    _fontSize = MIN(24.0, MAX(11.0, _fontSize + delta));
    _textView.font = [UIFont monospacedSystemFontOfSize:_fontSize weight:UIFontWeightRegular];
    [self updateCursorStatus];
}

- (void)increaseFont
{
    [self changeFontSize:1.0];
}

- (void)decreaseFont
{
    [self changeFontSize:-1.0];
}

- (void)showTools:(UIBarButtonItem *)sender
{
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Find" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self showFind];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Replace All" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self replaceAll];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Go To Line" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self goToLine];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Increase Font" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self increaseFont];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Decrease Font" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self decreaseFont];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = sender;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)insertText:(NSString *)text cursorOffsetFromEnd:(NSInteger)offset
{
    NSRange selection = _textView.selectedRange;
    [_textView replaceRange:_textView.selectedTextRange withText:text];
    NSUInteger end = selection.location + text.length;
    NSInteger adjusted = (NSInteger)end + offset;
    adjusted = MAX(0, MIN((NSInteger)_textView.text.length, adjusted));
    _textView.selectedRange = NSMakeRange((NSUInteger)adjusted, 0);
    [_textView becomeFirstResponder];
}

- (void)insertBraces
{
    [self insertText:@"{}" cursorOffsetFromEnd:-1];
}

- (void)insertParentheses
{
    [self insertText:@"()" cursorOffsetFromEnd:-1];
}

- (void)insertQuotes
{
    [self insertText:@"\"\"" cursorOffsetFromEnd:-1];
}

- (void)indentSelection
{
    NSRange selection = _textView.selectedRange;
    if (selection.length == 0) {
        [self insertText:@"    " cursorOffsetFromEnd:0];
        return;
    }
    NSString *source = _textView.text ?: @"";
    NSRange lineRange = [source lineRangeForRange:selection];
    NSString *block = [source substringWithRange:lineRange];
    NSString *indented = [@"    " stringByAppendingString:
        [block stringByReplacingOccurrencesOfString:@"\n" withString:@"\n    "]];
    if ([block hasSuffix:@"\n"] && [indented hasSuffix:@"    "]) {
        indented = [indented substringToIndex:indented.length - 4];
    }
    [_textView replaceRange:[_textView textRangeFromPosition:[_textView positionFromPosition:_textView.beginningOfDocument
                                                                                     offset:(NSInteger)lineRange.location]
                                                 toPosition:[_textView positionFromPosition:_textView.beginningOfDocument
                                                                                     offset:(NSInteger)NSMaxRange(lineRange)]]
                    withText:indented];
    _textView.selectedRange = NSMakeRange(lineRange.location, indented.length);
}

- (void)undoEditing
{
    [_textView.undoManager undo];
}

- (void)redoEditing
{
    [_textView.undoManager redo];
}

- (void)dismissKeyboard
{
    [_textView resignFirstResponder];
}

- (void)updateCursorStatus
{
    NSString *text = _textView.text ?: @"";
    NSUInteger location = MIN(_textView.selectedRange.location, text.length);
    NSString *prefix = [text substringToIndex:location];
    NSArray *lines = [prefix componentsSeparatedByString:@"\n"];
    NSUInteger line = MAX((NSUInteger)1, lines.count);
    NSUInteger column = [lines.lastObject length] + 1;
    NSUInteger totalLines = MAX((NSUInteger)1, [[text componentsSeparatedByString:@"\n"] count]);
    _statusLabel.text = [NSString stringWithFormat:@"Ln %lu, Col %lu  |  %lu lines  |  %.0f pt   ",
                         (unsigned long)line,
                         (unsigned long)column,
                         (unsigned long)totalLines,
                         _fontSize];
}

- (void)textViewDidChange:(UITextView *)textView
{
    (void)textView;
    [self setDirty:YES];
    [self updateCursorStatus];
}

- (void)textViewDidChangeSelection:(UITextView *)textView
{
    (void)textView;
    [self updateCursorStatus];
}

- (NSArray<UIKeyCommand *> *)keyCommands
{
    return @[
        [UIKeyCommand keyCommandWithInput:@"s" modifierFlags:UIKeyModifierCommand action:@selector(saveFile)],
        [UIKeyCommand keyCommandWithInput:@"f" modifierFlags:UIKeyModifierCommand action:@selector(showFind)],
        [UIKeyCommand keyCommandWithInput:@"g" modifierFlags:UIKeyModifierCommand action:@selector(goToLine)],
    ];
}

@end
