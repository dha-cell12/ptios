//
//  SettingsPageViewController.m
//  TLinkauto
//
//  Created by Jason on 2021/1/18.
//

#import "SettingsPageViewController.h"
#import "ScriptListTableCell.h"
#import "TouchIndicatorConfigurationViewController.h"
#import "ActivatorConfigurationViewController.h"
#import "Util.h"
#import "Socket.h"

#import "TableViewCellWithSwitch.h"
#import "TableViewCellWithSlider.h"
#import "TableViewCellWithEntry.h"

#import "libactivator.h"
#import <dlfcn.h>
#import <objc/runtime.h>
#import "Config.h"
#import "ConfigManager.h"
#import "../../../stream-app/app/LicenseViewController.h"
#import "../../../stream-app/app/LicenseLifecycleCoordinator.h"
#import "TLinkVPNSettingsViewController.h"

#define SETTING_CELL_SWITCH 0
#define SETTING_CELL_ENTRY 1

@interface SettingsPageViewController ()
@end

@implementation SettingsPageViewController
{
    NSArray *sections;
    NSArray<NSArray*> *cellsForEachSection;
    ConfigManager *configManager;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    sections = @[@"License", @"VPN", NSLocalizedString(@"remoteManagement", nil), NSLocalizedString(@"control", nil), NSLocalizedString(@"script", nil)]; // , @"HELP"
    configManager = [[ConfigManager alloc] initWithPath:SPRINGBOARD_CONFIG_PATH];
    BOOL doubleClickPopup = YES;
    if ([configManager getValueFromKey:@"double_click_volume_show_popup"])
    {
        doubleClickPopup = [[configManager getValueFromKey:@"double_click_volume_show_popup"] boolValue];
    }
    
    BOOL switchAppBeforeRunScript = YES;
    if ([configManager getValueFromKey:@"switch_app_before_run_script"])
    {
        switchAppBeforeRunScript = [[configManager getValueFromKey:@"switch_app_before_run_script"] boolValue];
    }

    BOOL jsHelperExecutionEnabled = NO;
    NSData *runtimeConfigData = [NSData dataWithContentsOfFile:RUNTIME_CONFIG_PATH];
    if (runtimeConfigData.length > 0) {
        NSDictionary *runtimeConfig = [NSJSONSerialization JSONObjectWithData:runtimeConfigData
                                                                       options:0
                                                                         error:nil];
        if ([runtimeConfig isKindOfClass:[NSDictionary class]]) {
            id helperEnabled = runtimeConfig[@"javascript_helper_runtime_enabled"]
                ?: runtimeConfig[@"enable_js_helper_execution"];
            if ([helperEnabled respondsToSelector:@selector(boolValue)]) {
                jsHelperExecutionEnabled = [helperEnabled boolValue];
            }
        }
    }
    
    // [@{"type": ?, @"title": ?, @"content": ?, ... more depends on the cell type}]
    //
    cellsForEachSection = @[
        @[
            @{@"type": @(SETTING_CELL_ENTRY), @"title": @"License", @"secondary_title": @"Activation and device binding", @"row_click_handler": NSStringFromSelector(@selector(handleLicenseWithEntryCellInstance:))}
        ],
        @[
            @{@"type": @(SETTING_CELL_ENTRY), @"title": @"Managed IKEv2 VPN", @"feature": @"automation", @"secondary_title": @"Configure the TLink-owned profile", @"row_click_handler": NSStringFromSelector(@selector(handleVPNWithEntryCellInstance:))}
        ],
        @[
            @{@"type": @(SETTING_CELL_SWITCH), @"title": NSLocalizedString(@"webServer", nil), @"feature": @"stream", @"switch_click_handler": NSStringFromSelector(@selector(handleWebServerWithSwitchCellInstance:)), @"switch_init_status": @(NO)}
        ],
        @[
            @{@"type": @(SETTING_CELL_ENTRY), @"title": @"Activator", @"feature": @"automation", @"secondary_title": @"", @"row_click_handler": NSStringFromSelector(@selector(handleActivatorWithEntryCellInstance:))},
            @{@"type": @(SETTING_CELL_ENTRY), @"title": NSLocalizedString(@"configActivatorEvents", nil), @"feature": @"automation", @"secondary_title": @"", @"row_click_handler": NSStringFromSelector(@selector(handleConfigActivatorEventsWithEntryCellInstance:))},
            @{@"type": @(SETTING_CELL_ENTRY), @"title": NSLocalizedString(@"touchIndicator", nil), @"feature": @"automation", @"secondary_title": @"", @"row_click_handler": NSStringFromSelector(@selector(handleTouchIndicatorWithEntryCellInstance:))},
            @{@"type": @(SETTING_CELL_SWITCH), @"title": NSLocalizedString(@"doubleClickShowPopup", nil), @"feature": @"automation", @"switch_click_handler": NSStringFromSelector(@selector(handlePopupWindowDoubleClick:)), @"switch_init_status": @(doubleClickPopup)}
        ],
        @[
            @{@"type": @(SETTING_CELL_SWITCH), @"title": NSLocalizedString(@"switchAppBeforePlaying", nil), @"feature": @"script", @"switch_click_handler": NSStringFromSelector(@selector(handleSwitchAppBeforePlaying:)), @"switch_init_status": @(switchAppBeforeRunScript)},
            @{@"type": @(SETTING_CELL_SWITCH), @"title": NSLocalizedString(@"enableJSHelperExecution", nil), @"feature": @"script", @"switch_click_handler": NSStringFromSelector(@selector(handleJSHelperExecution:)), @"switch_init_status": @(jsHelperExecutionEnabled)}
        ]
    ];
     
    UINib *SwitchCellNib = [UINib nibWithNibName:@"TableViewCellWithSwitch" bundle:nil];
    [_tableView registerNib:SwitchCellNib forCellReuseIdentifier:@"SwitchCell"];

    UINib *entryCellNib = [UINib nibWithNibName:@"TableViewCellWithEntry" bundle:nil];
    [_tableView registerNib:entryCellNib forCellReuseIdentifier:@"EntryCell"];
    
    _tableView.backgroundColor = [UIColor colorWithRed:243/255.0f green:242/255.0f blue:248/255.0f alpha:1.0f];
    _tableView.tableFooterView = [[UIView alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(licenseSnapshotDidChange:)
                                                 name:SCLicenseLifecycleDidChangeNotification
                                               object:nil];
    [[SCLicenseLifecycleCoordinator sharedCoordinator]
        refreshLicenseUISnapshotAsyncForReason:@"settings_view_loaded"];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)licenseSnapshotDidChange:(NSNotification *)notification
{
    (void)notification;
    [self.tableView reloadData];
}

- (BOOL)licenseAllowsCellInfo:(NSDictionary *)cellInfo reason:(NSString **)reason
{
    NSString *feature = [cellInfo[@"feature"] isKindOfClass:[NSString class]]
        ? cellInfo[@"feature"]
        : nil;
    if (feature.length == 0) return YES;
    return [[SCLicenseLifecycleCoordinator sharedCoordinator]
        cachedFeatureAllowed:feature
                      reason:reason];
}

- (void)handleLicenseWithEntryCellInstance:(TableViewCellWithEntry *)cell
{
    (void)cell;
    SCLicenseViewController *controller =
        [[SCLicenseViewController alloc] initWithStyle:UITableViewStyleGrouped];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)handleVPNWithEntryCellInstance:(TableViewCellWithEntry *)cell
{
    (void)cell;
    TLinkVPNSettingsViewController *controller =
        [[TLinkVPNSettingsViewController alloc] init];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)notifySpringBoardConfigurationChanged:(NSString *)task
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        Socket *socket = [[Socket alloc] init];
        if ([socket connect:@"127.0.0.1" byPort:6000] == 0) {
            [socket send:[task stringByAppendingString:@"\r\n"]];
            [socket recv:1024];
        }
        [socket close];
    });
}

- (void)handleSwitchAppBeforePlaying:(UISwitch*)s {
    if ([s isOn])
    {
        [configManager updateKey:@"switch_app_before_run_script" forValue:@(true)];
        [configManager save];
    }
    else
    {
        [configManager updateKey:@"switch_app_before_run_script" forValue:@(false)];
        [configManager save];
    }
    
    [self notifySpringBoardConfigurationChanged:@"902"];
}

- (void)handleJSHelperExecution:(UISwitch *)sender
{
    NSMutableDictionary *runtimeConfig = [NSMutableDictionary dictionary];
    NSData *existingData = [NSData dataWithContentsOfFile:RUNTIME_CONFIG_PATH];
    if (existingData.length > 0) {
        id existing = [NSJSONSerialization JSONObjectWithData:existingData options:0 error:nil];
        if ([existing isKindOfClass:[NSDictionary class]]) {
            [runtimeConfig addEntriesFromDictionary:(NSDictionary *)existing];
        }
    }

    runtimeConfig[@"javascript_helper_runtime_enabled"] = @([sender isOn]);
    [runtimeConfig removeObjectForKey:@"enable_js_helper_execution"];
    if (!runtimeConfig[@"javascript_helper_runtime_default"]) {
        runtimeConfig[@"javascript_helper_runtime_default"] = @NO;
    }
    if (!runtimeConfig[@"javascript_helper_allow_admin_rpc"]) {
        runtimeConfig[@"javascript_helper_allow_admin_rpc"] = @NO;
    }

    NSError *jsonError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:runtimeConfig
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:&jsonError];
    BOOL saved = data && [data writeToFile:RUNTIME_CONFIG_PATH
                                   options:NSDataWritingAtomic
                                     error:&jsonError];
    if (!saved) {
        [sender setOn:![sender isOn] animated:YES];
        [Util showAlertBoxWithOneOption:self
                                  title:@"Error"
                                message:[NSString stringWithFormat:@"Cannot save JavaScript helper setting: %@",
                                         jsonError.localizedDescription ?: @"unknown error"]
                           buttonString:@"OK"];
    }
}

- (void)handlePopupWindowDoubleClick:(UISwitch*)s {
    if ([s isOn])
    {
        [configManager updateKey:@"double_click_volume_show_popup" forValue:@(true)];
        [configManager save];
    }
    else
    {
        [configManager updateKey:@"double_click_volume_show_popup" forValue:@(false)];
        [configManager save];
    }
    [self notifySpringBoardConfigurationChanged:@"901"];
}

- (void)handleConfigActivatorEventsWithEntryCellInstance:(TableViewCellWithEntry*)cell {
    dlopen("/usr/lib/libactivator.dylib", RTLD_LAZY);
    Class ac = objc_getClass("LAActivator");
    if (ac) {
        
        UIStoryboard *sb = [UIStoryboard storyboardWithName:@"SettingPages" bundle:nil];
        ActivatorConfigurationViewController *vc = [sb instantiateViewControllerWithIdentifier:@"ActivatorConfigurationViewController"];
        vc.title = NSLocalizedString(@"configActivatorEvents", nil);
        [self.navigationController pushViewController:vc animated:YES];
    }
    else
    {
        [Util showAlertBoxWithOneOption:self title:@"Error" message:NSLocalizedString(@"activatorNeedInstall", nil) buttonString:@"OK"];
    }
}

- (void)handleWebServerWithSwitchCellInstance:(UISwitch*)s {
    if ([s isOn])
    {
        [Util showAlertBoxWithOneOption:self
                                  title:@"TLinkauto"
                                 message:@"Screen stream (MPEG-TS over TCP) is available on:\n- 7001: Fast (lower latency, higher CPU/heat)\n- 7002: Eco (higher latency, lower CPU/heat)\nUse an MPEG-TS/H.264 capable client (ffplay, VLC, mpegts.js via a bridge)."
                            buttonString:@"OK"];
        [s setOn:NO];
    }
}

- (void)handleActivatorWithEntryCellInstance:(TableViewCellWithEntry*)cell {
    dlopen("/usr/lib/libactivator.dylib", RTLD_LAZY);
    Class la = objc_getClass("LAListenerSettingsViewController");
    if (la) {
        LAListenerSettingsViewController *vc = [[la alloc] init];
        [vc setListenerName:@"com.tlinkauto.tlinkauto"];
        vc.title = @"Assign Activator Events";
        [self.navigationController pushViewController:vc animated:YES];
    }
    else
    {
        [Util showAlertBoxWithOneOption:self title:@"Error" message:NSLocalizedString(@"activatorNeedInstall", nil) buttonString:@"OK"];
    }
}

- (void)handleTouchIndicatorWithEntryCellInstance:(TableViewCellWithEntry*)cell {
    if ([cell isSelected])
    {
        UIStoryboard *sb = [UIStoryboard storyboardWithName:@"SettingPages" bundle:nil];
        TouchIndicatorConfigurationViewController *touchIndicatorConfigurationViewController = [sb instantiateViewControllerWithIdentifier:@"TouchIndicatorConfigurationPage"];
        [self.navigationController pushViewController:touchIndicatorConfigurationViewController animated:YES];
        //[self.navigationController setTitle:@"Touch Indicator"];
    }

}


//配置每个section(段）有多少row（行） cell
//默认只有一个section
-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{
    return cellsForEachSection[section].count;
}

-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return sections.count;
}

//每行显示什么东西
-(UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{

    UITableViewCell *result;
    

    NSInteger indexInCurrentSection = indexPath.row;

    
    NSArray* cellList = cellsForEachSection[indexPath.section];

    NSDictionary *cellInfo = cellList[indexInCurrentSection];
    if ([cellInfo[@"type"] intValue] == SETTING_CELL_SWITCH)
    {
        static NSString *cellID = @"SwitchCell";

        TableViewCellWithSwitch *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
        
        //判断队列里面是否有这个cell 没有自己创建，有直接使用
        if (cell == nil) {
            //没有,创建一个
            cell = [[TableViewCellWithSwitch alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellID];
        }
        
        cell.title.text = cellInfo[@"title"];
        [cell.switchBtn removeTarget:nil action:NULL forControlEvents:UIControlEventValueChanged];
        [cell.switchBtn addTarget:self action:NSSelectorFromString(cellInfo[@"switch_click_handler"]) forControlEvents:UIControlEventValueChanged];
        [cell.switchBtn setOn:[cellInfo[@"switch_init_status"] boolValue]];
        NSString *licenseReason = nil;
        BOOL allowed = [self licenseAllowsCellInfo:cellInfo reason:&licenseReason];
        cell.switchBtn.enabled = allowed;
        cell.contentView.alpha = allowed ? 1.0 : 0.45;
        
        result = cell;
    }
    else if ([cellInfo[@"type"] intValue] == SETTING_CELL_ENTRY)
    {
        static NSString *cellID = @"EntryCell";

        TableViewCellWithEntry *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
        
        //判断队列里面是否有这个cell 没有自己创建，有直接使用
        if (cell == nil) {
            //没有,创建一个
            NSLog(@"create a setting cell switch");
            cell = [[TableViewCellWithEntry alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellID];
        }
        
        cell.title.text = cellInfo[@"title"];
        NSString *licenseReason = nil;
        BOOL allowed = [self licenseAllowsCellInfo:cellInfo reason:&licenseReason];
        if (indexPath.section == 0 && indexPath.row == 0) {
            NSDictionary *status = [[SCLicenseLifecycleCoordinator sharedCoordinator]
                cachedLicenseStatus];
            NSString *state = status[@"state"] ?: @"loading";
            cell.subTitle.text = [NSString stringWithFormat:@"State: %@", state];
        } else {
            cell.subTitle.text = allowed
                ? cellInfo[@"secondary_title"]
                : [NSString stringWithFormat:@"Requires %@ license", cellInfo[@"feature"] ?: @"feature"];
        }
        cell.clickHandler = cellInfo[@"row_click_handler"];
        cell.contentView.alpha = allowed ? 1.0 : 0.55;
        
        result = cell;
    }
    
    
    return result;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    UITableViewCell *cell = [_tableView cellForRowAtIndexPath:indexPath];
    NSDictionary *cellInfo = cellsForEachSection[indexPath.section][indexPath.row];
    NSString *licenseReason = nil;
    if (![self licenseAllowsCellInfo:cellInfo reason:&licenseReason]) {
        [Util showAlertBoxWithOneOption:self
                                  title:@"License Required"
                                message:[licenseReason isEqualToString:@"license_status_loading"]
                                    ? @"License status is loading. Please try again."
                                    : (licenseReason ?: @"This feature is not enabled by the current license.")
                           buttonString:@"OK"];
        return;
    }
    if ([cell isKindOfClass:[TableViewCellWithEntry class]])
    {
        TableViewCellWithEntry *entry = (TableViewCellWithEntry*)cell;
        [self performSelector:NSSelectorFromString(entry.clickHandler) withObject:entry];
    }
}

// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {

}


- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *resultView = [[UIView alloc] init];
    //view.backgroundColor = [UIColor greenColor];
    
    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [UIFont boldSystemFontOfSize:13];
    title.textColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.7];

    title.text = sections[section];

    
    [resultView addSubview:title];
    
    [[title.leftAnchor constraintEqualToAnchor:resultView.leftAnchor constant:10] setActive:YES];
    [[title.bottomAnchor constraintEqualToAnchor:resultView.bottomAnchor constant:-5] setActive:YES];

    return resultView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 60;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    (void)tableView;
    if (section == 4) {
        return NSLocalizedString(@"scriptRuntimeSettingsHint", nil);
    }
    return nil;
}
/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
