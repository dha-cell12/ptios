#import "ScriptsViewController.h"
#import "TLinkSocketClient.h"

static NSString *const kTLinkScriptsPath = @"/var/mobile/Library/TLinkauto/scripts";

@interface SCScriptEntry : NSObject
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *path;
@property(nonatomic, assign) BOOL directory;
@end

@implementation SCScriptEntry
@end

@implementation SCScriptsViewController {
    NSMutableArray<SCScriptEntry *> *_entries;
    UILabel *_emptyLabel;
    NSString *_scriptsPath;
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
    self.tableView.backgroundColor = [UIColor systemBackgroundColor];
    self.tableView.rowHeight = 56.0;
    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                             target:self
                                                                             action:@selector(reloadScripts)];
    UIBarButtonItem *add = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                         target:self
                                                                         action:@selector(createDemoScript)];
    self.navigationItem.rightBarButtonItems = @[refresh, add];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                                                                                          target:self
                                                                                          action:@selector(stopScript)];

    _emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _emptyLabel.text = @"No scripts found";
    _emptyLabel.textColor = [UIColor secondaryLabelColor];
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.font = [UIFont systemFontOfSize:15.0];
    self.tableView.backgroundView = _emptyLabel;
    [self reloadScripts];
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

- (void)showMessageWithTitle:(NSString *)title message:(NSString *)message
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)createDemoScript
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *basePath = [self scriptsPath];
    [fm createDirectoryAtPath:basePath withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *scriptPath = [self uniqueScriptPathWithBaseName:@"Demo Script"];

    NSError *err = nil;
    [fm createDirectoryAtPath:scriptPath withIntermediateDirectories:YES attributes:nil error:&err];
    if (err) {
        [self showMessageWithTitle:@"Create Script" message:err.localizedDescription ?: @"create failed"];
        return;
    }

    NSDictionary *info = @{@"Entry": @"main.js", @"FrontApp": @"", @"Orientation": @"1"};
    [info writeToFile:[scriptPath stringByAppendingPathComponent:@"info.plist"] atomically:YES];

    NSDictionary *manifest = @{
        @"runtime": @"javascriptcore",
        @"runtimeLocation": @"in-process",
        @"entry": @"main.js",
        @"apiVersion": @1,
        @"coordinateSpace": @"native-pixels",
    };
    NSData *manifestData = [NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:nil];
    [manifestData writeToFile:[scriptPath stringByAppendingPathComponent:@"manifest.json"] atomically:YES];

    NSString *source =
        @"console.log('TLinkauto TrollStore demo started');\n"
         "device.toast('Hello from TLinkauto JS');\n"
         "var info = device.runtimeInfo();\n"
         "console.log('session=' + info.sessionId + ' entry=' + info.entryPath);\n"
         "var screen = device.taskResult(25, '1');\n"
         "console.log('screen=' + screen.payload);\n"
         "var languages = device.ocrLanguages();\n"
         "console.log('ocrLanguages=' + languages.payload);\n"
         "device.writeJSON('storage/last-run.json', { at: Date.now(), screen: screen.payload, languages: languages.payload });\n"
         "console.log('TLinkauto TrollStore demo finished');\n";
    [source writeToFile:[scriptPath stringByAppendingPathComponent:@"main.js"] atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (err) {
        [self showMessageWithTitle:@"Create Script" message:err.localizedDescription ?: @"write failed"];
        return;
    }

    [self reloadScripts];
    [self showMessageWithTitle:@"Create Script" message:[NSString stringWithFormat:@"Created %@", scriptPath.lastPathComponent]];
}

- (void)stopScript
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *response = [TLinkSocketClient requestTask:20 args:@[] timeout:4.0];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showMessageWithTitle:@"Stop Script" message:response ?: @"<nil>"];
        });
    });
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

    NSArray<NSString *> *names = [fm contentsOfDirectoryAtPath:basePath error:nil] ?: @[];
    NSArray<NSString *> *sorted = [names sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *name in sorted) {
        if ([name hasPrefix:@"."]) continue;
        NSString *path = [basePath stringByAppendingPathComponent:name];
        BOOL childDir = NO;
        [fm fileExistsAtPath:path isDirectory:&childDir];
        if (!childDir && ![name.pathExtension.lowercaseString isEqualToString:@"tl"]) continue;

        SCScriptEntry *entry = [[SCScriptEntry alloc] init];
        entry.name = name;
        entry.path = path;
        entry.directory = childDir;
        [_entries addObject:entry];
    }

    _emptyLabel.hidden = _entries.count > 0;
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _entries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cellID = @"ScriptCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }

    SCScriptEntry *entry = _entries[(NSUInteger)indexPath.row];
    cell.textLabel.text = entry.name;
    cell.detailTextLabel.text = entry.directory ? @"Folder" : entry.path;
    cell.imageView.image = [UIImage systemImageNamed:entry.directory ? @"folder" : @"doc.text"];
    cell.accessoryType = entry.directory ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryDetailButton;
    return cell;
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
    [self playScript:entry];
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath
{
    SCScriptEntry *entry = _entries[(NSUInteger)indexPath.row];
    [self playScript:entry];
}

- (void)playScript:(SCScriptEntry *)entry
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *response = [TLinkSocketClient requestTask:19 args:@[entry.path] timeout:8.0];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showMessageWithTitle:entry.name message:response ?: @"<nil>"];
        });
    });
}

@end
