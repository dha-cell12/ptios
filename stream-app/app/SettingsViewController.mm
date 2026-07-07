#import "SettingsViewController.h"
#import "TLinkSocketClient.h"

@implementation SCSettingsViewController {
    NSArray<NSArray<NSString *> *> *_sections;
    UITextView *_resultView;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Settings";
    _sections = @[
        @[@"Capability Probe", @"Hello Status", @"Capture Probe", @"Native Tap Center", @"Color Pick Center", @"Color Search Smoke", @"Frame Capture", @"OCR Languages", @"App Info Self", @"Frontmost App", @"List Bundles"],
        @[@"Color/Image/Frame: active", @"Vision OCR: active", @"App/Process: helper launch", @"Keyboard Clipboard: limited_on_trollstore", @"Touch Indicator: limited_on_trollstore", @"Activator: limited_on_trollstore", @"Privhelper: restart_streamd_only"],
    ];

    _resultView = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 180)];
    _resultView.editable = NO;
    _resultView.font = [UIFont fontWithName:@"Menlo" size:11.0] ?: [UIFont systemFontOfSize:11.0];
    _resultView.text = @"Diagnostics will appear here.";
    self.tableView.tableFooterView = _resultView;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return (NSInteger)_sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)_sections[(NSUInteger)section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return section == 0 ? @"Diagnostics" : @"TrollStore Compatibility";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cellID = @"SettingsCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
    }
    NSString *title = _sections[(NSUInteger)indexPath.section][(NSUInteger)indexPath.row];
    cell.textLabel.text = title;
    cell.detailTextLabel.text = indexPath.section == 0 ? @"Tap to run" : @"Planned compatibility fallback";
    cell.accessoryType = indexPath.section == 0 ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    cell.selectionStyle = indexPath.section == 0 ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 0) return;

    NSString *line = nil;
    switch (indexPath.row) {
        case 0: line = @"97\n"; break;
        case 1: line = @"60\n"; break;
        case 2: line = @"98\n"; break;
        case 3: {
            CGFloat scale = [UIScreen mainScreen].scale;
            CGSize size = [UIScreen mainScreen].bounds.size;
            int x = (int)(size.width * scale / 2.0);
            int y = (int)(size.height * scale / 2.0);
            line = [NSString stringWithFormat:@"62%d;;%d;;50;;0\n", x, y];
            break;
        }
        case 4: {
            CGFloat scale = [UIScreen mainScreen].scale;
            CGSize size = [UIScreen mainScreen].bounds.size;
            int x = (int)(size.width * scale / 2.0);
            int y = (int)(size.height * scale / 2.0);
            line = [NSString stringWithFormat:@"23%d;;%d\n", x, y];
            break;
        }
        case 5:
            line = @"281;;0;;0;;0;;0;;0;;255;;0;;255;;0;;255;;8\n";
            break;
        case 6:
            line = @"661;;1;;1000\n";
            break;
        case 7:
            line = @"272;;0\n";
            break;
        case 8: {
            NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
            line = [NSString stringWithFormat:@"33%@\n", bundleId];
            break;
        }
        case 9:
            line = @"34\n";
            break;
        case 10:
            line = @"530\n";
            break;
        default: return;
    }

    _resultView.text = @"Running...";
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *response = [TLinkSocketClient sendLineAndRead:line timeout:8.0];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_resultView.text = response ?: @"<nil>";
        });
    });
}

@end
