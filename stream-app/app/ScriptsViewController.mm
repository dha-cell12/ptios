#import "ScriptsViewController.h"
#import "ScriptEditorViewController.h"
#import "ScriptLogViewController.h"
#import "TLinkSocketClient.h"

static NSString *const kTLinkScriptsPath = @"/var/mobile/Library/TLinkauto/scripts";

@interface SCScriptEntry : NSObject
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *path;
@property(nonatomic, assign) BOOL directory;
@property(nonatomic, assign) BOOL scriptBundle;
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
                                                                         action:@selector(showAddMenu)];
    self.navigationItem.rightBarButtonItems = @[refresh, add];
    UIBarButtonItem *stop = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                                                                          target:self
                                                                          action:@selector(stopScript)];
    UIBarButtonItem *logs = [[UIBarButtonItem alloc] initWithTitle:@"Logs"
                                                             style:UIBarButtonItemStylePlain
                                                            target:self
                                                            action:@selector(showScriptLogs)];
    self.navigationItem.leftBarButtonItems = @[self.editButtonItem, stop, logs];

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
    return [ext isEqualToString:@"tl"] || [ext isEqualToString:@"js"] || [ext isEqualToString:@"json"] || [ext isEqualToString:@"plist"] || [ext isEqualToString:@"txt"];
}

- (BOOL)isPlayableFileEntry:(SCScriptEntry *)entry
{
    if (entry.directory) return NO;
    NSString *ext = [entry.path.pathExtension lowercaseString];
    return [ext isEqualToString:@"tl"] || [ext isEqualToString:@"js"];
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
             "device.toast('Hello from TLinkauto JS');\n"
             "var info = device.runtimeInfo();\n"
             "console.log('session=' + info.sessionId + ' entry=' + info.entryPath);\n"
             "var screen = device.taskResult(25, '1');\n"
             "console.log('screen=' + screen.payload);\n"
             "var languages = device.ocrLanguages();\n"
             "console.log('ocrLanguages=' + languages.payload);\n"
             "device.writeJSON('storage/last-run.json', { at: Date.now(), screen: screen.payload, languages: languages.payload });\n"
             "console.log('TLinkauto TrollStore demo finished');\n";
    } else {
        source =
            @"console.log('script started');\n"
             "device.toast('Script started');\n"
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
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover) {
        popover.barButtonItem = self.navigationItem.rightBarButtonItems.lastObject;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)createDemoScript
{
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

- (void)stopScript
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *response = [TLinkSocketClient requestTask:20 args:@[] timeout:4.0];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showMessageWithTitle:@"Stop Script" message:response ?: @"<nil>"];
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
    if (entry.directory) {
        cell.detailTextLabel.text = entry.scriptBundle ? @"Script Bundle" : @"Folder";
    } else {
        cell.detailTextLabel.text = entry.path.lastPathComponent;
    }
    cell.imageView.image = [UIImage systemImageNamed:entry.directory ? @"folder" : @"doc.text"];
    cell.accessoryType = entry.directory ? (entry.scriptBundle ? UITableViewCellAccessoryDetailDisclosureButton : UITableViewCellAccessoryDisclosureIndicator) : ([self isPlayableFileEntry:entry] ? UITableViewCellAccessoryDetailButton : UITableViewCellAccessoryNone);
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

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
{
    (void)tableView;
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                               title:@"Delete"
                                                                             handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
        [self confirmDeleteEntryAtIndexPath:indexPath completion:completionHandler];
    }];
    UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
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

- (void)openEditorForEntry:(SCScriptEntry *)entry
{
    SCScriptEditorViewController *editor = [[SCScriptEditorViewController alloc] initWithFilePath:entry.path];
    [self.navigationController pushViewController:editor animated:YES];
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
