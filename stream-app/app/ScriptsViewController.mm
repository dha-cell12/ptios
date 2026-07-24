#import "ScriptsViewController.h"
#import "ImageViewerViewController.h"
#import "PlaySettingsViewController.h"
#import "ScriptEditorViewController.h"
#import "ScriptLogViewController.h"
#import "TLinkSocketClient.h"
#import "../../shared/TLinkLicenseVerifier.h"
#include <math.h>

static NSString *const kTLinkScriptsPath = @"/var/mobile/Library/TLinkauto/scripts";

@interface SCScriptEntry : NSObject
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *path;
@property(nonatomic, assign) BOOL directory;
@property(nonatomic, assign) BOOL scriptBundle;
@end

@implementation SCScriptEntry
@end

@interface SCScriptTableViewCell : UITableViewCell
@end

@implementation SCScriptTableViewCell

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat height = CGRectGetHeight(self.contentView.bounds);
    CGFloat iconSize = 44.0;
    CGFloat iconY = floor((height - iconSize) * 0.5);
    self.imageView.frame = CGRectMake(14.0, iconY, iconSize, iconSize);
    self.imageView.contentMode = UIViewContentModeCenter;

    CGFloat labelX = 72.0;
    CGFloat labelWidth = MAX(40.0, CGRectGetWidth(self.contentView.bounds) - labelX - 12.0);
    self.textLabel.frame = CGRectMake(labelX, 17.0, labelWidth, 25.0);
    self.detailTextLabel.frame = CGRectMake(labelX, 44.0, labelWidth, 20.0);
}

@end

@implementation SCScriptsViewController {
    NSMutableArray<SCScriptEntry *> *_entries;
    UILabel *_emptyLabel;
    UILabel *_statusLabel;
    UILabel *_statusTitleLabel;
    UIProgressView *_statusProgressView;
    UIView *_actionHeaderView;
    UIView *_statusFooterView;
    UIButton *_editActionButton;
    UIBarButtonItem *_addButtonItem;
    NSString *_scriptsPath;
    BOOL _attemptedCompatibilitySeed;
}

- (instancetype)initWithScriptsPath:(NSString *)path
{
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _scriptsPath = [path copy];
    }
    return self;
}

- (NSString *)scriptsPath
{
    return _scriptsPath.length > 0 ? _scriptsPath : kTLinkScriptsPath;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    if (self.title.length == 0) self.title = @"Scripts";
    _entries = [NSMutableArray array];
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.tableView.rowHeight = 82.0;
    self.tableView.estimatedRowHeight = 82.0;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 72.0, 0, 16.0);
    self.tableView.sectionHeaderHeight = 10.0;
    self.tableView.sectionFooterHeight = 10.0;
    BOOL rootScripts = [[self scriptsPath] isEqualToString:kTLinkScriptsPath];
    self.navigationItem.largeTitleDisplayMode = rootScripts
        ? UINavigationItemLargeTitleDisplayModeAlways
        : UINavigationItemLargeTitleDisplayModeNever;
    if (rootScripts) self.navigationController.navigationBar.prefersLargeTitles = YES;

    UIBarButtonItem *refresh = [self navigationButtonWithSystemImage:@"arrow.clockwise"
                                                           tintColor:[UIColor systemBlueColor]
                                                     backgroundColor:[UIColor secondarySystemBackgroundColor]
                                                              action:@selector(reloadScripts)
                                                  accessibilityLabel:@"Refresh Scripts"];
    _addButtonItem = [self navigationButtonWithSystemImage:@"plus"
                                                 tintColor:[UIColor whiteColor]
                                           backgroundColor:[UIColor systemBlueColor]
                                                    action:@selector(showAddMenu)
                                        accessibilityLabel:@"Add Script or Folder"];
    self.navigationItem.rightBarButtonItems = @[refresh, _addButtonItem];

    _emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _emptyLabel.text = @"No scripts found";
    _emptyLabel.textColor = [UIColor secondaryLabelColor];
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.font = [UIFont systemFontOfSize:15.0];
    self.tableView.backgroundView = _emptyLabel;

    [self buildActionHeader];
    [self buildStatusFooter];
    [self seedCompatibilitySuiteIfNeeded];
    [self reloadScripts];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (_actionHeaderView && fabs(CGRectGetWidth(_actionHeaderView.frame) - width) > 0.5) {
        CGRect frame = _actionHeaderView.frame;
        frame.size.width = width;
        _actionHeaderView.frame = frame;
        self.tableView.tableHeaderView = _actionHeaderView;
    }
    if (_statusFooterView && self.tableView.tableFooterView == _statusFooterView &&
        fabs(CGRectGetWidth(_statusFooterView.frame) - width) > 0.5) {
        CGRect frame = _statusFooterView.frame;
        frame.size.width = width;
        _statusFooterView.frame = frame;
        self.tableView.tableFooterView = _statusFooterView;
    }
}

- (UIBarButtonItem *)navigationButtonWithSystemImage:(NSString *)imageName
                                           tintColor:(UIColor *)tintColor
                                     backgroundColor:(UIColor *)backgroundColor
                                              action:(SEL)action
                                  accessibilityLabel:(NSString *)accessibilityLabel
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(0, 0, 44.0, 44.0);
    button.backgroundColor = backgroundColor;
    button.tintColor = tintColor;
    button.layer.cornerRadius = 12.0;
    button.layer.shadowColor = [UIColor blackColor].CGColor;
    button.layer.shadowOpacity = 0.08;
    button.layer.shadowRadius = 5.0;
    button.layer.shadowOffset = CGSizeMake(0, 2.0);
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:20.0 weight:UIImageSymbolWeightMedium];
    [button setImage:[[UIImage systemImageNamed:imageName] imageByApplyingSymbolConfiguration:configuration]
            forState:UIControlStateNormal];
    button.accessibilityLabel = accessibilityLabel;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return [[UIBarButtonItem alloc] initWithCustomView:button];
}

- (UIButton *)actionButtonWithTitle:(NSString *)title
                         systemImage:(NSString *)imageName
                           tintColor:(UIColor *)tintColor
                              action:(SEL)action
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tintColor = tintColor;
    button.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    [button setTitle:title forState:UIControlStateNormal];
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:18.0 weight:UIImageSymbolWeightMedium];
    [button setImage:[[UIImage systemImageNamed:imageName] imageByApplyingSymbolConfiguration:configuration]
            forState:UIControlStateNormal];
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    button.imageEdgeInsets = UIEdgeInsetsMake(0, -5.0, 0, 5.0);
    button.titleEdgeInsets = UIEdgeInsetsMake(0, 5.0, 0, -5.0);
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)buildActionHeader
{
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    _actionHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 92.0)];
    _actionHeaderView.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UIView *surface = [[UIView alloc] initWithFrame:CGRectZero];
    surface.translatesAutoresizingMaskIntoConstraints = NO;
    surface.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    surface.layer.cornerRadius = 8.0;
    surface.layer.shadowColor = [UIColor blackColor].CGColor;
    surface.layer.shadowOpacity = 0.05;
    surface.layer.shadowRadius = 8.0;
    surface.layer.shadowOffset = CGSizeMake(0, 3.0);
    [_actionHeaderView addSubview:surface];

    _editActionButton = [self actionButtonWithTitle:@"Edit"
                                        systemImage:@"pencil"
                                          tintColor:[UIColor systemBlueColor]
                                             action:@selector(toggleScriptEditing)];
    UIButton *stop = [self actionButtonWithTitle:@"Stop"
                                     systemImage:@"stop.fill"
                                       tintColor:[UIColor systemRedColor]
                                          action:@selector(stopScript)];
    UIButton *logs = [self actionButtonWithTitle:@"Logs"
                                     systemImage:@"doc.text"
                                       tintColor:[UIColor systemBlueColor]
                                          action:@selector(showScriptLogs)];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_editActionButton, stop, logs]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.alignment = UIStackViewAlignmentFill;
    [surface addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [surface.topAnchor constraintEqualToAnchor:_actionHeaderView.topAnchor constant:8.0],
        [surface.leadingAnchor constraintEqualToAnchor:_actionHeaderView.leadingAnchor constant:16.0],
        [surface.trailingAnchor constraintEqualToAnchor:_actionHeaderView.trailingAnchor constant:-16.0],
        [surface.bottomAnchor constraintEqualToAnchor:_actionHeaderView.bottomAnchor constant:-8.0],
        [stack.topAnchor constraintEqualToAnchor:surface.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:surface.bottomAnchor],
    ]];
    self.tableView.tableHeaderView = _actionHeaderView;
}

- (void)buildStatusFooter
{
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    _statusFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 132.0)];
    _statusFooterView.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UIView *surface = [[UIView alloc] initWithFrame:CGRectZero];
    surface.translatesAutoresizingMaskIntoConstraints = NO;
    surface.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    surface.layer.cornerRadius = 8.0;
    [_statusFooterView addSubview:surface];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"sparkles"]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.contentMode = UIViewContentModeCenter;
    icon.tintColor = [UIColor systemBlueColor];
    icon.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.08];
    icon.layer.cornerRadius = 8.0;
    [surface addSubview:icon];

    _statusTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _statusTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusTitleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    _statusTitleLabel.textColor = [UIColor labelColor];
    _statusTitleLabel.numberOfLines = 1;
    [surface addSubview:_statusTitleLabel];

    _statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.textColor = [UIColor secondaryLabelColor];
    _statusLabel.font = [UIFont systemFontOfSize:12.0];
    _statusLabel.numberOfLines = 2;
    _statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [surface addSubview:_statusLabel];

    _statusProgressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _statusProgressView.translatesAutoresizingMaskIntoConstraints = NO;
    _statusProgressView.progressTintColor = [UIColor systemBlueColor];
    _statusProgressView.trackTintColor = [UIColor tertiarySystemFillColor];
    _statusProgressView.layer.cornerRadius = 2.0;
    _statusProgressView.clipsToBounds = YES;
    [surface addSubview:_statusProgressView];

    [NSLayoutConstraint activateConstraints:@[
        [surface.topAnchor constraintEqualToAnchor:_statusFooterView.topAnchor constant:8.0],
        [surface.leadingAnchor constraintEqualToAnchor:_statusFooterView.leadingAnchor constant:16.0],
        [surface.trailingAnchor constraintEqualToAnchor:_statusFooterView.trailingAnchor constant:-16.0],
        [surface.bottomAnchor constraintEqualToAnchor:_statusFooterView.bottomAnchor constant:-8.0],
        [icon.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor constant:14.0],
        [icon.topAnchor constraintEqualToAnchor:surface.topAnchor constant:14.0],
        [icon.widthAnchor constraintEqualToConstant:44.0],
        [icon.heightAnchor constraintEqualToConstant:44.0],
        [_statusTitleLabel.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12.0],
        [_statusTitleLabel.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor constant:-14.0],
        [_statusTitleLabel.topAnchor constraintEqualToAnchor:icon.topAnchor constant:1.0],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:_statusTitleLabel.leadingAnchor],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:_statusTitleLabel.trailingAnchor],
        [_statusLabel.topAnchor constraintEqualToAnchor:_statusTitleLabel.bottomAnchor constant:3.0],
        [_statusProgressView.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor constant:14.0],
        [_statusProgressView.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor constant:-14.0],
        [_statusProgressView.bottomAnchor constraintEqualToAnchor:surface.bottomAnchor constant:-15.0],
    ]];
}

- (void)toggleScriptEditing
{
    [self setEditing:!self.isEditing animated:YES];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated
{
    [super setEditing:editing animated:animated];
    [_editActionButton setTitle:editing ? @"Done" : @"Edit" forState:UIControlStateNormal];
    [_editActionButton setImage:[UIImage systemImageNamed:editing ? @"checkmark" : @"pencil"]
                       forState:UIControlStateNormal];
}

- (NSString *)uniqueScriptPathWithBaseName:(NSString *)baseName
{
    NSString *folder = [self scriptsPath];
    NSString *candidate = [folder stringByAppendingPathComponent:[baseName stringByAppendingString:@".tl"]];
    if (![[NSFileManager defaultManager] fileExistsAtPath:candidate]) return candidate;
    for (NSInteger i = 2; i < 1000; i++) {
        candidate = [folder stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ %ld.tl", baseName, (long)i]];
        if (![[NSFileManager defaultManager] fileExistsAtPath:candidate]) return candidate;
    }
    return [folder stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ %@.tl", baseName, @((long long)[[NSDate date] timeIntervalSince1970])]];
}

- (NSString *)uniqueFolderPathWithBaseName:(NSString *)baseName
{
    NSString *folder = [self scriptsPath];
    NSString *candidate = [folder stringByAppendingPathComponent:baseName];
    if (![[NSFileManager defaultManager] fileExistsAtPath:candidate]) return candidate;
    for (NSInteger i = 2; i < 1000; i++) {
        candidate = [folder stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ %ld", baseName, (long)i]];
        if (![[NSFileManager defaultManager] fileExistsAtPath:candidate]) return candidate;
    }
    return [folder stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ %@", baseName, @((long long)[[NSDate date] timeIntervalSince1970])]];
}

- (void)showMessageWithTitle:(NSString *)title message:(NSString *)message
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showStatus:(NSString *)status
{
    NSString *value = [status isKindOfClass:[NSString class]] ? status : @"";
    if (value.length == 0) {
        _statusTitleLabel.text = @"";
        _statusLabel.text = @"";
        self.tableView.tableFooterView = nil;
        return;
    }

    NSArray<NSString *> *lines = [value componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSString *firstLine = lines.count > 0 ? lines.firstObject : value;
    NSString *detail = lines.count > 1
        ? [[lines subarrayWithRange:NSMakeRange(1, lines.count - 1)] componentsJoinedByString:@" "]
        : @"";
    BOOL starting = [firstLine hasPrefix:@"Starting"];
    BOOL running = [firstLine hasPrefix:@"Running"];
    BOOL failed = [firstLine hasPrefix:@"Failed"];
    _statusTitleLabel.text = firstLine.length > 0 ? firstLine : @"Script Status";
    _statusLabel.text = detail.length > 0 ? detail : (running ? @"Script runtime is active" : value);
    _statusProgressView.progressTintColor = failed ? [UIColor systemRedColor] : [UIColor systemBlueColor];
    float progress = failed ? 1.0f : (running ? 0.42f : (starting ? 0.16f : 0.28f));
    [_statusProgressView setProgress:progress animated:YES];
    self.tableView.tableFooterView = _statusFooterView;
}

- (BOOL)ensureScriptsPathWritableWithError:(NSString **)error
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *basePath = [self scriptsPath];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:basePath isDirectory:&isDir] || !isDir) {
        [fm createDirectoryAtPath:basePath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    if ([fm isWritableFileAtPath:basePath]) return YES;

    NSString *repairResponse = [TLinkSocketClient requestTask:44 args:@[] timeout:3.0];
    if (![fm fileExistsAtPath:basePath isDirectory:&isDir] || !isDir) {
        [fm createDirectoryAtPath:basePath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    if ([fm isWritableFileAtPath:basePath]) return YES;

    NSDictionary *attrs = [fm attributesOfItemAtPath:basePath error:nil] ?: @{};
    NSNumber *owner = attrs[NSFileOwnerAccountID];
    NSNumber *group = attrs[NSFileGroupOwnerAccountID];
    NSNumber *perms = attrs[NSFilePosixPermissions];
    if (error) {
        *error = [NSString stringWithFormat:@"Scripts path is not writable: %@ owner=%@ group=%@ mode=%@ repair=%@",
                  basePath,
                  owner ?: @"?",
                  group ?: @"?",
                  perms ? [NSString stringWithFormat:@"%o", [perms intValue]] : @"?",
                  repairResponse ?: @"<nil>"];
    }
    return NO;
}

- (NSString *)safeNameFromInput:(NSString *)input
{
    NSString *trimmed = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return nil;
    if ([trimmed isEqualToString:@"."] || [trimmed isEqualToString:@".."]) return nil;
    NSCharacterSet *invalid = [NSCharacterSet characterSetWithCharactersInString:@"/:\\"];
    if ([trimmed rangeOfCharacterFromSet:invalid].location != NSNotFound) return nil;
    return trimmed;
}

- (BOOL)isScriptBundlePath:(NSString *)path isDirectory:(BOOL)isDirectory
{
    return isDirectory && [[path.pathExtension lowercaseString] isEqualToString:@"tl"];
}

- (BOOL)isInsideScriptBundlePath:(NSString *)path
{
    for (NSString *component in path.pathComponents) {
        if ([[component.pathExtension lowercaseString] isEqualToString:@"tl"]) return YES;
    }
    return NO;
}

- (BOOL)shouldIncludeEntryNamed:(NSString *)name atPath:(NSString *)path isDirectory:(BOOL)isDirectory
{
    (void)path;
    if ([name hasPrefix:@"."]) return NO;
    if (isDirectory) return YES;
    if ([self isInsideScriptBundlePath:[self scriptsPath]]) return YES;
    NSString *ext = [name.pathExtension lowercaseString];
    return [ext isEqualToString:@"tl"] || [ext isEqualToString:@"js"] || [ext isEqualToString:@"json"] || [ext isEqualToString:@"plist"] || [ext isEqualToString:@"txt"] || [self isImageFilePath:name];
}

- (BOOL)isPlayableFileEntry:(SCScriptEntry *)entry
{
    if (entry.directory) return NO;
    NSString *ext = [entry.path.pathExtension lowercaseString];
    return [ext isEqualToString:@"tl"] || [ext isEqualToString:@"js"];
}

- (BOOL)isImageFilePath:(NSString *)path
{
    NSString *ext = [path.pathExtension lowercaseString];
    return [@[@"png", @"jpg", @"jpeg", @"bmp", @"gif", @"heic", @"heif"] containsObject:ext];
}

- (NSString *)nameByPreservingScriptExtensionForEntry:(SCScriptEntry *)entry input:(NSString *)input
{
    NSString *name = [self safeNameFromInput:input];
    if (!name) return nil;
    if (entry.scriptBundle && ![[name.pathExtension lowercaseString] isEqualToString:@"tl"]) {
        name = [name stringByAppendingPathExtension:@"tl"];
    } else if ([self isPlayableFileEntry:entry] && name.pathExtension.length == 0) {
        name = [name stringByAppendingPathExtension:entry.path.pathExtension];
    }
    return name;
}

- (NSString *)uniqueCopyPathForEntry:(SCScriptEntry *)entry
{
    NSString *parent = [entry.path stringByDeletingLastPathComponent];
    NSString *ext = entry.path.pathExtension;
    NSString *base = entry.path.lastPathComponent;
    if (ext.length > 0) base = [base stringByDeletingPathExtension];

    NSString *(^buildName)(NSInteger) = ^NSString *(NSInteger index) {
        NSString *name = index <= 1 ? [base stringByAppendingString:@" Copy"] : [NSString stringWithFormat:@"%@ Copy %ld", base, (long)index];
        return ext.length > 0 ? [name stringByAppendingPathExtension:ext] : name;
    };

    for (NSInteger i = 1; i < 1000; i++) {
        NSString *candidate = [parent stringByAppendingPathComponent:buildName(i)];
        if (![[NSFileManager defaultManager] fileExistsAtPath:candidate]) return candidate;
    }
    NSString *fallback = [NSString stringWithFormat:@"%@ Copy %@", base, @((long long)[[NSDate date] timeIntervalSince1970])];
    if (ext.length > 0) fallback = [fallback stringByAppendingPathExtension:ext];
    return [parent stringByAppendingPathComponent:fallback];
}

- (void)presentNamePromptWithTitle:(NSString *)title
                           message:(NSString *)message
                       placeholder:(NSString *)placeholder
                        completion:(void (^)(NSString *name))completion
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = placeholder;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Create"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        NSString *name = [self safeNameFromInput:alert.textFields.firstObject.text ?: @""];
        if (!name) {
            [self showMessageWithTitle:title message:@"Use a normal name without / : or \\"];
            return;
        }
        if (completion) completion(name);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (BOOL)writeScriptBundleAtPath:(NSString *)scriptPath demo:(BOOL)demo error:(NSError **)error
{
    NSString *permissionError = nil;
    if (![self ensureScriptsPathWritableWithError:&permissionError]) {
        if (error) {
            *error = [NSError errorWithDomain:@"TLinkautoScripts"
                                         code:13
                                     userInfo:@{NSLocalizedDescriptionKey: permissionError ?: @"Scripts path is not writable"}];
        }
        return NO;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm createDirectoryAtPath:scriptPath withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }

    NSDictionary *info = @{@"Entry": @"main.js", @"FrontApp": @"", @"Orientation": @"1"};
    [info writeToFile:[scriptPath stringByAppendingPathComponent:@"info.plist"] atomically:YES];

    NSDictionary *manifest = @{
        @"runtime": @"javascriptcore",
        @"runtimeLocation": @"in-process",
        @"entry": @"main.js",
        @"apiVersion": @1,
        @"coordinateSpace": @"native-pixels"
    };
    NSData *manifestData = [NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:nil];
    [manifestData writeToFile:[scriptPath stringByAppendingPathComponent:@"manifest.json"] atomically:YES];

    NSString *source = nil;
    if (demo) {
        source =
            @"console.log('TLinkauto TrollStore demo started');\n"
             "function logResult(name, value) { console.log(name + '=' + JSON.stringify(value)); return value; }\n"
             "device.toast('Rootfull compat facade smoke');\n"
             "var info = device.runtimeInfo();\n"
             "console.log('session=' + info.sessionId + ' entry=' + info.entryPath);\n"
             "console.log('run=' + info.currentRun + '/' + info.totalRuns + ' speed=' + info.playSettings.speed);\n"
             "logResult('sleep', device.sleep(0.2));\n"
             "var screen = logResult('screen', device.getScreenSize ? device.getScreenSize() : device.taskResult(25, '1'));\n"
             "var color = logResult('pickColor', device.pickColor(10, 10));\n"
             "var frame = logResult('captureFrame', device.captureFrame({ bgra: 1, ttlMs: 2000 }));\n"
             "if (frame.ok) {\n"
             "  logResult('framePickColors', device.framePickColors(frame.id, [[10, 10], [20, 20]], { maxAgeMs: 2000 }));\n"
             "  if (color.ok) logResult('frameIsColors', device.frameIsColors(frame.id, [[10, 10, color.red, color.green, color.blue]], { tolerance: 0, maxAgeMs: 2000 }));\n"
             "  logResult('releaseFrame', device.releaseFrame(frame.id));\n"
             "}\n"
             "var shot = logResult('screenshot', device.screenshot());\n"
             "var languages = logResult('ocrLanguages', device.ocrLanguages());\n"
             "device.writeJSON('storage/last-run.json', { at: Date.now(), screen: screen, color: color, screenshot: shot, languages: languages });\n"
             "console.log('TLinkauto TrollStore demo finished');\n";
    } else {
        source =
            @"console.log('script started');\n"
             "device.toast('Script started');\n"
             "var info = device.runtimeInfo();\n"
             "console.log('run=' + info.currentRun + '/' + info.totalRuns + ' speed=' + info.playSettings.speed);\n"
             "\n"
             "// Call old TLinkauto tasks through the local bridge.\n"
             "var screen = device.taskResult(25, '1');\n"
             "console.log('screen=' + screen.payload);\n";
    }

    return [source writeToFile:[scriptPath stringByAppendingPathComponent:@"main.js"]
                    atomically:YES
                      encoding:NSUTF8StringEncoding
                         error:error];
}

- (BOOL)writeCompatibilityScriptAtPath:(NSString *)scriptPath
                                source:(NSString *)source
                                 error:(NSError **)error
{
    if (![self writeScriptBundleAtPath:scriptPath demo:NO error:error]) return NO;
    return [source writeToFile:[scriptPath stringByAppendingPathComponent:@"main.js"]
                    atomically:YES
                      encoding:NSUTF8StringEncoding
                         error:error];
}

- (void)createScriptNamed:(NSString *)name
{
    NSString *scriptName = [[name.pathExtension lowercaseString] isEqualToString:@"tl"] ? name : [name stringByAppendingString:@".tl"];
    NSString *scriptPath = [[self scriptsPath] stringByAppendingPathComponent:scriptName];
    if ([[NSFileManager defaultManager] fileExistsAtPath:scriptPath]) {
        [self showMessageWithTitle:@"Create Script" message:@"A script or folder with that name already exists."];
        return;
    }
    NSError *err = nil;
    BOOL ok = [self writeScriptBundleAtPath:scriptPath demo:NO error:&err];
    if (!ok) {
        [self showMessageWithTitle:@"Create Script" message:err.localizedDescription ?: @"create failed"];
        return;
    }
    [self reloadScripts];
    [self showMessageWithTitle:@"Create Script" message:[NSString stringWithFormat:@"Created %@", scriptPath.lastPathComponent]];
}

- (void)createFolderNamed:(NSString *)name
{
    NSString *permissionError = nil;
    if (![self ensureScriptsPathWritableWithError:&permissionError]) {
        [self showMessageWithTitle:@"Create Folder" message:permissionError ?: @"Scripts path is not writable"];
        return;
    }

    NSString *folderPath = [[self scriptsPath] stringByAppendingPathComponent:name];
    if ([[NSFileManager defaultManager] fileExistsAtPath:folderPath]) {
        [self showMessageWithTitle:@"Create Folder" message:@"A script or folder with that name already exists."];
        return;
    }
    NSError *err = nil;
    BOOL ok = [[NSFileManager defaultManager] createDirectoryAtPath:folderPath
                                        withIntermediateDirectories:YES
                                                         attributes:nil
                                                              error:&err];
    if (!ok) {
        [self showMessageWithTitle:@"Create Folder" message:err.localizedDescription ?: @"create failed"];
        return;
    }
    [self reloadScripts];
}

- (void)createFileNamed:(NSString *)name
{
    NSString *permissionError = nil;
    if (![self ensureScriptsPathWritableWithError:&permissionError]) {
        [self showMessageWithTitle:@"Create File" message:permissionError ?: @"Scripts path is not writable"];
        return;
    }

    NSString *fileName = name.pathExtension.length > 0 ? name : [name stringByAppendingString:@".js"];
    NSString *filePath = [[self scriptsPath] stringByAppendingPathComponent:fileName];
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        [self showMessageWithTitle:@"Create File" message:@"A file or folder with that name already exists."];
        return;
    }
    NSString *ext = [fileName.pathExtension lowercaseString];
    NSString *source = [ext isEqualToString:@"js"] ? @"console.log('new file');\n" : @"";
    NSError *err = nil;
    BOOL ok = [source writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (!ok) {
        [self showMessageWithTitle:@"Create File" message:err.localizedDescription ?: @"write failed"];
        return;
    }
    [self reloadScripts];

    SCScriptEntry *entry = [[SCScriptEntry alloc] init];
    entry.name = fileName;
    entry.path = filePath;
    entry.directory = NO;
    entry.scriptBundle = NO;
    [self openEditorForEntry:entry];
}

- (void)showAddMenu
{
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Add"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"New Script"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [self presentNamePromptWithTitle:@"New Script"
                                 message:@"Create a .tl JavaScript bundle"
                             placeholder:@"My Script"
                              completion:^(NSString *name) {
            [self createScriptNamed:name];
        }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"New File"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [self presentNamePromptWithTitle:@"New File"
                                 message:@"Create a text file in the current location"
                             placeholder:@"helper.js"
                              completion:^(NSString *name) {
            [self createFileNamed:name];
        }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"New Folder"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [self presentNamePromptWithTitle:@"New Folder"
                                 message:@"Create a folder in the current location"
                             placeholder:@"Folder"
                              completion:^(NSString *name) {
            [self createFolderNamed:name];
        }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Demo Script"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [self createDemoScript];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Compatibility Suite"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [self installCompatibilitySuite];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover) {
        popover.barButtonItem = self.navigationItem.rightBarButtonItems.lastObject;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)createDemoScript
{
    NSString *permissionError = nil;
    if (![self ensureScriptsPathWritableWithError:&permissionError]) {
        [self showMessageWithTitle:@"Create Script" message:permissionError ?: @"Scripts path is not writable"];
        return;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *basePath = [self scriptsPath];
    [fm createDirectoryAtPath:basePath withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *scriptPath = [self uniqueScriptPathWithBaseName:@"Demo Script"];

    NSError *err = nil;
    BOOL ok = [self writeScriptBundleAtPath:scriptPath demo:YES error:&err];
    if (!ok) {
        [self showMessageWithTitle:@"Create Script" message:err.localizedDescription ?: @"write failed"];
        return;
    }

    [self reloadScripts];
    [self showMessageWithTitle:@"Create Script" message:[NSString stringWithFormat:@"Created %@", scriptPath.lastPathComponent]];
}

- (void)installCompatibilitySuite
{
    NSString *permissionError = nil;
    if (![self ensureScriptsPathWritableWithError:&permissionError]) {
        [self showMessageWithTitle:@"Compatibility Suite" message:permissionError ?: @"Scripts path is not writable"];
        return;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *resourcePath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"CompatibilityExamples"];
    NSError *listError = nil;
    NSArray<NSString *> *resourceNames = [fm contentsOfDirectoryAtPath:resourcePath error:&listError];
    NSMutableArray<NSString *> *javascriptNamesMutable = [NSMutableArray array];
    for (NSString *name in resourceNames ?: @[]) {
        if ([[name.pathExtension lowercaseString] isEqualToString:@"js"]) {
            [javascriptNamesMutable addObject:name];
        }
    }
    NSArray<NSString *> *javascriptNames = [javascriptNamesMutable sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    if (javascriptNames.count == 0) {
        [self showMessageWithTitle:@"Compatibility Suite"
                           message:listError.localizedDescription ?: @"Packaged compatibility examples are missing"];
        return;
    }

    NSString *suitePath = [self uniqueFolderPathWithBaseName:@"Compatibility Tests"];
    NSError *createError = nil;
    if (![fm createDirectoryAtPath:suitePath withIntermediateDirectories:YES attributes:nil error:&createError]) {
        [self showMessageWithTitle:@"Compatibility Suite" message:createError.localizedDescription ?: @"Unable to create suite folder"];
        return;
    }

    NSUInteger installed = 0;
    NSMutableArray<NSString *> *failures = [NSMutableArray array];
    for (NSString *resourceName in javascriptNames) {
        NSString *sourcePath = [resourcePath stringByAppendingPathComponent:resourceName];
        NSError *readError = nil;
        NSString *source = [NSString stringWithContentsOfFile:sourcePath encoding:NSUTF8StringEncoding error:&readError];
        if (!source) {
            [failures addObject:[NSString stringWithFormat:@"%@: %@", resourceName, readError.localizedDescription ?: @"read failed"]];
            continue;
        }

        NSString *scriptName = [[resourceName stringByDeletingPathExtension] stringByAppendingPathExtension:@"tl"];
        NSString *scriptPath = [suitePath stringByAppendingPathComponent:scriptName];
        if ([[NSFileManager defaultManager] fileExistsAtPath:scriptPath]) {
            continue;
        }
        NSError *writeError = nil;
        if ([self writeCompatibilityScriptAtPath:scriptPath source:source error:&writeError]) {
            installed++;
        } else {
            [failures addObject:[NSString stringWithFormat:@"%@: %@", scriptName, writeError.localizedDescription ?: @"write failed"]];
        }
    }

    [self reloadScripts];
    NSString *message = [NSString stringWithFormat:@"Installed %lu scripts in %@",
                         (unsigned long)installed, suitePath.lastPathComponent];
    if (failures.count > 0) {
        message = [message stringByAppendingFormat:@"\n\nFailures:\n%@", [failures componentsJoinedByString:@"\n"]];
    }
    [self showMessageWithTitle:@"Compatibility Suite" message:message];
}

- (NSArray<NSString *> *)packagedCompatibilityExampleNamesWithError:(NSError **)error
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *resourcePath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"CompatibilityExamples"];
    NSArray<NSString *> *resourceNames = [fm contentsOfDirectoryAtPath:resourcePath error:error];
    NSMutableArray<NSString *> *javascriptNamesMutable = [NSMutableArray array];
    for (NSString *name in resourceNames ?: @[]) {
        if ([[name.pathExtension lowercaseString] isEqualToString:@"js"]) {
            [javascriptNamesMutable addObject:name];
        }
    }
    return [javascriptNamesMutable sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

- (NSUInteger)installCompatibilityExamples:(NSArray<NSString *> *)javascriptNames
                                suitePath:(NSString *)suitePath
                                 failures:(NSMutableArray<NSString *> *)failures
{
    NSString *resourcePath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"CompatibilityExamples"];
    NSUInteger installed = 0;
    for (NSString *resourceName in javascriptNames) {
        NSString *sourcePath = [resourcePath stringByAppendingPathComponent:resourceName];
        NSError *readError = nil;
        NSString *source = [NSString stringWithContentsOfFile:sourcePath encoding:NSUTF8StringEncoding error:&readError];
        if (!source) {
            [failures addObject:[NSString stringWithFormat:@"%@: %@", resourceName, readError.localizedDescription ?: @"read failed"]];
            continue;
        }

        NSString *scriptName = [[resourceName stringByDeletingPathExtension] stringByAppendingPathExtension:@"tl"];
        NSString *scriptPath = [suitePath stringByAppendingPathComponent:scriptName];
        NSError *writeError = nil;
        if ([self writeCompatibilityScriptAtPath:scriptPath source:source error:&writeError]) {
            installed++;
        } else {
            [failures addObject:[NSString stringWithFormat:@"%@: %@", scriptName, writeError.localizedDescription ?: @"write failed"]];
        }
    }
    return installed;
}

- (void)seedCompatibilitySuiteIfNeeded
{
    if (_attemptedCompatibilitySeed) return;
    _attemptedCompatibilitySeed = YES;
    if (![[self scriptsPath] isEqualToString:kTLinkScriptsPath]) return;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *suitePath = [[self scriptsPath] stringByAppendingPathComponent:@"Compatibility Tests"];
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:suitePath isDirectory:&isDir] && isDir) {
        NSString *firstScript = [suitePath stringByAppendingPathComponent:@"01 Runtime Storage.tl"];
        NSString *lastScript = [suitePath stringByAppendingPathComponent:@"08 License Heartbeat.tl"];
        if ([fm fileExistsAtPath:firstScript] && [fm fileExistsAtPath:lastScript]) return;
    }

    NSString *permissionError = nil;
    if (![self ensureScriptsPathWritableWithError:&permissionError]) {
        [self showStatus:permissionError ?: @"Scripts path is not writable"];
        return;
    }

    NSError *listError = nil;
    NSArray<NSString *> *javascriptNames = [self packagedCompatibilityExampleNamesWithError:&listError];
    if (javascriptNames.count == 0) {
        [self showStatus:listError.localizedDescription ?: @"Packaged compatibility examples are missing"];
        return;
    }

    NSError *createError = nil;
    if (![fm createDirectoryAtPath:suitePath withIntermediateDirectories:YES attributes:nil error:&createError]) {
        [self showStatus:createError.localizedDescription ?: @"Unable to create Compatibility Tests"];
        return;
    }

    NSMutableArray<NSString *> *failures = [NSMutableArray array];
    NSUInteger installed = [self installCompatibilityExamples:javascriptNames suitePath:suitePath failures:failures];
    if (failures.count > 0) {
        [self showStatus:[NSString stringWithFormat:@"Compatibility seed: %lu/%lu installed, %lu failed",
                          (unsigned long)installed,
                          (unsigned long)javascriptNames.count,
                          (unsigned long)failures.count]];
    } else if (installed > 0) {
        [self showStatus:[NSString stringWithFormat:@"Compatibility Tests installed: %lu scripts", (unsigned long)installed]];
    }
}

- (void)stopScript
{
    [self showStatus:@"Stopping script...\nWaiting for streamd"];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *response = [TLinkSocketClient requestTask:20 args:@[] timeout:4.0];
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL ok = [response hasPrefix:@"0;;"] || [response isEqualToString:@"0"];
            [self showStatus:[NSString stringWithFormat:@"%@\n%@",
                              ok ? @"Script stopped" : @"Failed to stop script",
                              response ?: @"<nil>"]];
            if (!ok) [self showMessageWithTitle:@"Stop Script" message:response ?: @"<nil>"];
        });
    });
}

- (void)showScriptLogs
{
    SCScriptLogViewController *logs = [[SCScriptLogViewController alloc] init];
    [self.navigationController pushViewController:logs animated:YES];
}

- (void)reloadScripts
{
    [_entries removeAllObjects];

    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    NSString *basePath = [self scriptsPath];
    if (![fm fileExistsAtPath:basePath isDirectory:&isDir] || !isDir) {
        [fm createDirectoryAtPath:basePath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    if (![fm isWritableFileAtPath:basePath]) {
        NSString *permissionError = nil;
        if ([self ensureScriptsPathWritableWithError:&permissionError]) {
            [self showStatus:@""];
        } else {
            [self showStatus:permissionError ?: @"Scripts path is read-only"];
        }
    }

    NSArray<NSString *> *names = [fm contentsOfDirectoryAtPath:basePath error:nil] ?: @[];
    NSArray<NSString *> *sorted = [names sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *name in sorted) {
        NSString *path = [basePath stringByAppendingPathComponent:name];
        BOOL childDir = NO;
        [fm fileExistsAtPath:path isDirectory:&childDir];
        if (![self shouldIncludeEntryNamed:name atPath:path isDirectory:childDir]) continue;

        SCScriptEntry *entry = [[SCScriptEntry alloc] init];
        entry.name = name;
        entry.path = path;
        entry.directory = childDir;
        entry.scriptBundle = [self isScriptBundlePath:path isDirectory:childDir];
        [_entries addObject:entry];
    }

    _emptyLabel.hidden = _entries.count > 0;
    [self.tableView reloadData];
}

- (void)refreshEmptyState
{
    _emptyLabel.hidden = _entries.count > 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _entries.count;
}

- (UIButton *)playButtonForRow:(NSInteger)row
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(0.0, 0.0, 44.0, 44.0);
    button.backgroundColor = [UIColor systemGreenColor];
    button.tintColor = [UIColor whiteColor];
    button.layer.cornerRadius = 12.0;
    button.layer.shadowColor = [UIColor blackColor].CGColor;
    button.layer.shadowOpacity = 0.12;
    button.layer.shadowRadius = 4.0;
    button.layer.shadowOffset = CGSizeMake(0, 2.0);
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:18.0 weight:UIImageSymbolWeightBold];
    [button setImage:[[UIImage systemImageNamed:@"play.fill"] imageByApplyingSymbolConfiguration:configuration]
            forState:UIControlStateNormal];
    button.accessibilityLabel = @"Run Script";
    button.tag = row;
    [button addTarget:self action:@selector(playButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIButton *)settingsButtonForRow:(NSInteger)row
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(0.0, 0.0, 42.0, 44.0);
    button.backgroundColor = [UIColor secondarySystemBackgroundColor];
    button.layer.cornerRadius = 12.0;
    button.layer.borderWidth = 0.5;
    button.layer.borderColor = [UIColor separatorColor].CGColor;
    [button setImage:[UIImage systemImageNamed:@"gearshape.fill"] forState:UIControlStateNormal];
    button.tintColor = [UIColor systemGrayColor];
    button.accessibilityLabel = @"Play Settings";
    button.tag = row;
    [button addTarget:self action:@selector(settingsButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIView *)scriptAccessoryViewForRow:(NSInteger)row
{
    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectMake(0.0, 0.0, 96.0, 44.0)];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.distribution = UIStackViewDistributionEqualSpacing;
    stack.spacing = 8.0;
    [stack addArrangedSubview:[self settingsButtonForRow:row]];
    [stack addArrangedSubview:[self playButtonForRow:row]];
    return stack;
}

- (UIButton *)folderActionsButtonForRow:(NSInteger)row
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(0.0, 0.0, 44.0, 44.0);
    [button setImage:[UIImage systemImageNamed:@"ellipsis.circle"] forState:UIControlStateNormal];
    button.tintColor = [UIColor systemBlueColor];
    button.accessibilityLabel = @"Folder Actions";
    button.tag = row;
    [button addTarget:self action:@selector(folderActionsButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)folderActionsButtonTapped:(UIButton *)button
{
    NSInteger row = button.tag;
    if (row < 0 || (NSUInteger)row >= _entries.count) return;
    SCScriptEntry *entry = _entries[(NSUInteger)row];
    if (!entry.directory || entry.scriptBundle) return;

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:entry.name ?: @"Folder"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Rename Folder"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [self renameEntry:entry completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Duplicate"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [self duplicateEntry:entry completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Delete Folder"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *action) {
        NSUInteger currentIndex = [self->_entries indexOfObjectIdenticalTo:entry];
        if (currentIndex == NSNotFound) return;
        [self confirmDeleteEntryAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)currentIndex inSection:0]
                                 completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover) {
        popover.sourceView = button;
        popover.sourceRect = button.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cellID = @"ScriptCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[SCScriptTableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }

    SCScriptEntry *entry = _entries[(NSUInteger)indexPath.row];
    cell.textLabel.text = entry.name;
    if (entry.directory) {
        cell.detailTextLabel.text = entry.scriptBundle ? @"Script Bundle" : @"Folder";
    } else {
        cell.detailTextLabel.text = entry.path.lastPathComponent;
    }
    if (entry.scriptBundle) {
        cell.imageView.image = [UIImage systemImageNamed:@"doc.text"];
    } else if (entry.directory) {
        cell.imageView.image = [UIImage systemImageNamed:@"folder"];
    } else if ([self isImageFilePath:entry.path]) {
        cell.imageView.image = [UIImage systemImageNamed:@"photo"];
    } else {
        cell.imageView.image = [UIImage systemImageNamed:@"doc.text"];
    }
    cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    cell.textLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.numberOfLines = 1;
    cell.imageView.tintColor = [UIColor systemBlueColor];
    cell.imageView.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.08];
    cell.imageView.layer.cornerRadius = 8.0;
    cell.imageView.clipsToBounds = YES;
    cell.imageView.preferredSymbolConfiguration =
        [UIImageSymbolConfiguration configurationWithPointSize:21.0 weight:UIImageSymbolWeightRegular];
    BOOL canRun = entry.scriptBundle || [self isPlayableFileEntry:entry];
    BOOL plainFolder = entry.directory && !entry.scriptBundle;
    cell.accessoryView = canRun
        ? [self scriptAccessoryViewForRow:indexPath.row]
        : (plainFolder ? [self folderActionsButtonForRow:indexPath.row] : nil);
    cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    (void)tableView;
    return indexPath.row >= 0 && (NSUInteger)indexPath.row < _entries.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath
{
    (void)tableView;
    (void)indexPath;
    return @"Delete";
}

- (void)confirmDeleteEntryAtIndexPath:(NSIndexPath *)indexPath completion:(void (^)(BOOL finished))completion
{
    if (indexPath.row < 0 || (NSUInteger)indexPath.row >= _entries.count) {
        if (completion) completion(NO);
        return;
    }

    SCScriptEntry *entry = _entries[(NSUInteger)indexPath.row];
    NSString *kind = entry.scriptBundle ? @"script bundle" : (entry.directory ? @"folder" : @"file");
    NSString *message = [NSString stringWithFormat:@"Delete %@ \"%@\"?", kind, entry.name ?: entry.path.lastPathComponent];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:^(__unused UIAlertAction *action) {
        if (completion) completion(NO);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *action) {
        NSError *err = nil;
        BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:entry.path error:&err];
        if (!ok) {
            NSString *detail = err.localizedDescription ?: @"delete failed";
            [self showMessageWithTitle:@"Delete" message:detail];
            if (completion) completion(NO);
            return;
        }

        NSUInteger idx = [self->_entries indexOfObjectIdenticalTo:entry];
        if (idx != NSNotFound) {
            [self->_entries removeObjectAtIndex:idx];
            NSIndexPath *deletedPath = [NSIndexPath indexPathForRow:(NSInteger)idx inSection:0];
            [self.tableView deleteRowsAtIndexPaths:@[deletedPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        } else {
            [self reloadScripts];
        }
        [self refreshEmptyState];
        if (completion) completion(YES);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    [self confirmDeleteEntryAtIndexPath:indexPath completion:nil];
}

- (void)renameEntry:(SCScriptEntry *)entry completion:(void (^)(BOOL finished))completion
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename"
                                                                   message:entry.path.lastPathComponent
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = entry.name ?: entry.path.lastPathComponent;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) {
        if (completion) completion(NO);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *newName = [self nameByPreservingScriptExtensionForEntry:entry input:alert.textFields.firstObject.text ?: @""];
        if (!newName) {
            [self showMessageWithTitle:@"Rename" message:@"Use a normal name without / : or \\"];
            if (completion) completion(NO);
            return;
        }
        NSString *newPath = [[entry.path stringByDeletingLastPathComponent] stringByAppendingPathComponent:newName];
        if ([newPath isEqualToString:entry.path]) {
            if (completion) completion(NO);
            return;
        }
        if ([[NSFileManager defaultManager] fileExistsAtPath:newPath]) {
            [self showMessageWithTitle:@"Rename" message:@"A file or folder with that name already exists."];
            if (completion) completion(NO);
            return;
        }
        NSError *err = nil;
        BOOL ok = [[NSFileManager defaultManager] moveItemAtPath:entry.path toPath:newPath error:&err];
        if (!ok) {
            [self showMessageWithTitle:@"Rename" message:err.localizedDescription ?: @"rename failed"];
            if (completion) completion(NO);
            return;
        }
        [self reloadScripts];
        if (completion) completion(YES);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)duplicateEntry:(SCScriptEntry *)entry completion:(void (^)(BOOL finished))completion
{
    NSString *target = [self uniqueCopyPathForEntry:entry];
    NSError *err = nil;
    BOOL ok = [[NSFileManager defaultManager] copyItemAtPath:entry.path toPath:target error:&err];
    if (!ok) {
        [self showMessageWithTitle:@"Duplicate" message:err.localizedDescription ?: @"copy failed"];
        if (completion) completion(NO);
        return;
    }
    [self reloadScripts];
    if (completion) completion(YES);
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
{
    (void)tableView;
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                               title:@"Delete"
                                                                             handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
        [self confirmDeleteEntryAtIndexPath:indexPath completion:completionHandler];
    }];
    SCScriptEntry *entry = _entries[(NSUInteger)indexPath.row];
    NSMutableArray<UIContextualAction *> *actions = [NSMutableArray arrayWithObject:deleteAction];
    UIContextualAction *renameAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                               title:@"Rename"
                                                                             handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
        [self renameEntry:entry completion:completionHandler];
    }];
    renameAction.backgroundColor = [UIColor systemBlueColor];
    [actions addObject:renameAction];

    UIContextualAction *duplicateAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                                  title:@"Duplicate"
                                                                                handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
        [self duplicateEntry:entry completion:completionHandler];
    }];
    duplicateAction.backgroundColor = [UIColor systemIndigoColor];
    [actions addObject:duplicateAction];

    if (entry.scriptBundle || [self isPlayableFileEntry:entry]) {
        UIContextualAction *settingsAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                                     title:@"Settings"
                                                                                   handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
            [self showPlaySettingsForEntry:entry];
            completionHandler(YES);
        }];
        settingsAction.backgroundColor = [UIColor systemGrayColor];
        [actions addObject:settingsAction];
    }
    UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:actions];
    config.performsFirstActionWithFullSwipe = NO;
    return config;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    SCScriptEntry *entry = _entries[(NSUInteger)indexPath.row];
    if (entry.directory) {
        SCScriptsViewController *child = [[SCScriptsViewController alloc] initWithScriptsPath:entry.path];
        child.title = entry.name;
        [self.navigationController pushViewController:child animated:YES];
        return;
    }
    [self openEditorForEntry:entry];
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath
{
    SCScriptEntry *entry = _entries[(NSUInteger)indexPath.row];
    if (entry.scriptBundle || [self isPlayableFileEntry:entry]) {
        [self playScript:entry];
    }
}

- (void)playButtonTapped:(UIButton *)button
{
    NSInteger row = button.tag;
    if (row < 0 || (NSUInteger)row >= _entries.count) return;
    SCScriptEntry *entry = _entries[(NSUInteger)row];
    if (entry.scriptBundle || [self isPlayableFileEntry:entry]) {
        [self playScript:entry];
    }
}

- (void)settingsButtonTapped:(UIButton *)button
{
    NSInteger row = button.tag;
    if (row < 0 || (NSUInteger)row >= _entries.count) return;
    [self showPlaySettingsForEntry:_entries[(NSUInteger)row]];
}

- (void)showPlaySettingsForEntry:(SCScriptEntry *)entry
{
    SCPlaySettingsViewController *settings = [[SCPlaySettingsViewController alloc] initWithScriptPath:entry.path];
    [self.navigationController pushViewController:settings animated:YES];
}

- (void)openEditorForEntry:(SCScriptEntry *)entry
{
    if ([self isImageFilePath:entry.path]) {
        SCImageViewerViewController *viewer = [[SCImageViewerViewController alloc] initWithImagePath:entry.path];
        [self.navigationController pushViewController:viewer animated:YES];
        return;
    }
    SCScriptEditorViewController *editor = [[SCScriptEditorViewController alloc] initWithFilePath:entry.path];
    [self.navigationController pushViewController:editor animated:YES];
}

- (void)playScript:(SCScriptEntry *)entry
{
    NSString *licenseError = nil;
    if (!TLinkLicenseFeatureAllowed(@"script", &licenseError)) {
        NSDictionary *status = TLinkLicenseStatusDictionary();
        NSString *message = [NSString stringWithFormat:@"Script license denied.\nstate=%@\nerror=%@",
                             status[@"state"] ?: @"invalid",
                             licenseError ?: status[@"error"] ?: @"license_required"];
        [self showMessageWithTitle:@"License Required" message:message];
        return;
    }
    [self showStatus:[NSString stringWithFormat:@"Starting %@...", entry.name ?: entry.path.lastPathComponent]];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"TLinkVisualFeedbackNeedsPoll" object:nil];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *response = [TLinkSocketClient requestTask:19 args:@[entry.path] timeout:8.0];
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL ok = [response hasPrefix:@"0;;"] || [response isEqualToString:@"0"];
            if (ok) {
                [self showStatus:[NSString stringWithFormat:@"Running %@\n%@", entry.name ?: entry.path.lastPathComponent, response ?: @""]];
                [[NSNotificationCenter defaultCenter] postNotificationName:@"TLinkVisualFeedbackNeedsPoll" object:nil];
            } else {
                [self showStatus:[NSString stringWithFormat:@"Failed %@\n%@", entry.name ?: entry.path.lastPathComponent, response ?: @"<nil>"]];
                [self showMessageWithTitle:entry.name message:response ?: @"<nil>"];
            }
        });
    });
}

@end
