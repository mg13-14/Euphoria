//
//  EUSettingsController.m
//  Euphoria
//
//  Created by tomt000 on 08/01/2024.
//

#import "EUSettingsController.h"
#import <objc/runtime.h>
#import <Photos/Photos.h>
#import <sys/sysctl.h>
#import <sys/types.h>
#import <libjailbreak/util.h>
#import "EUUIManager.h"
#import "EUPkgManagerPickerViewController.h"
#import "EUHeaderCell.h"
#import "EUEnvironmentManager.h"
#import "EUPreferenceManager.h"
#import "EUExploitManager.h"
#import "EUPSListItemsController.h"
#import "EUPSExploitListItemsController.h"
#import "EUThemeManager.h"
#import "EUSceneDelegate.h"
#import "EUPSJetsamListItemsController.h"
#import "EUButtonCell.h"

@interface EUSettingsController ()

@end

@implementation EUSettingsController

- (void)viewDidLoad
{
    _lastKnownTheme = [[EUThemeManager sharedInstance] enabledTheme].key;
    [super viewDidLoad];
}

- (void)viewWillAppear:(BOOL)arg1
{
    [super viewWillAppear:arg1];
    if (_lastKnownTheme != [[EUThemeManager sharedInstance] enabledTheme].key)
    {
        [EUSceneDelegate relaunch];
        NSString *icon = [[EUThemeManager sharedInstance] enabledTheme].icon;
        [[UIApplication sharedApplication] setAlternateIconName:icon completionHandler:^(NSError * _Nullable error) {
            if (error)
                NSLog(@"Error changing app icon: %@", error);
        }];

        if ([EUEnvironmentManager sharedManager].isJailbroken) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [[EUEnvironmentManager sharedManager] updateBootLogo];
            });
        }
    }
}

- (NSArray *)availableKernelExploitIdentifiers
{
    NSMutableArray *identifiers = [NSMutableArray new];
    for (EUExploit *exploit in _availableKernelExploits) {
        [identifiers addObject:exploit.identifier];
    }
    return identifiers;
}

- (NSArray *)availableKernelExploitNames
{
    NSMutableArray *names = [NSMutableArray new];
    for (EUExploit *exploit in _availableKernelExploits) {
        [names addObject:exploit.name];
    }
    return names;
}

- (NSArray *)availablePACBypassIdentifiers
{
    NSMutableArray *identifiers = [NSMutableArray new];
    if (![EUEnvironmentManager sharedManager].isPACBypassRequired) {
        [identifiers addObject:@"none"];
    }
    for (EUExploit *exploit in _availablePACBypasses) {
        [identifiers addObject:exploit.identifier];
    }
    return identifiers;
}

- (NSArray *)availablePACBypassNames
{
    NSMutableArray *names = [NSMutableArray new];
    if (![EUEnvironmentManager sharedManager].isPACBypassRequired) {
        [names addObject:EULocalizedString(@"None")];
    }
    for (EUExploit *exploit in _availablePACBypasses) {
        [names addObject:exploit.name];
    }
    return names;
}

- (NSArray *)availablePPLBypassIdentifiers
{
    NSMutableArray *identifiers = [NSMutableArray new];
    for (EUExploit *exploit in _availablePPLBypasses) {
        [identifiers addObject:exploit.identifier];
    }
    return identifiers;
}

- (NSArray *)availablePPLBypassNames
{
    NSMutableArray *names = [NSMutableArray new];
    for (EUExploit *exploit in _availablePPLBypasses) {
        [names addObject:exploit.name];
    }
    return names;
}

- (NSArray *)themeIdentifiers
{
    return [[EUThemeManager sharedInstance] getAvailableThemeKeys];
}

- (NSArray *)themeNames
{
    return [[EUThemeManager sharedInstance] getAvailableThemeNames];
}

- (NSArray *)jetsamOptionNumbers
{
    return @[
    @2,
    @3,
    @4,
    @5,
    @6,
    @7,
    @8,
    ];
}

- (NSArray *)jetsamOptionTitles
{
    return @[
        @"1x",
        @"1.5x",
        @"2x",
        @"2.5x",
        [NSString stringWithFormat:@"3x (%@)", EULocalizedString(@"Recommended")],
        @"3.5x",
        @"4x",
    ];
}

- (id)specifiers
{
    if(_specifiers == nil) {
        NSMutableArray *specifiers = [NSMutableArray new];
        EUEnvironmentManager *envManager = [EUEnvironmentManager sharedManager];
        EUExploitManager *exploitManager = [EUExploitManager sharedManager];

        NSNumber *buttonHeight = @(44);
        
        SEL defGetter = @selector(readPreferenceValue:);
        SEL defSetter = @selector(setPreferenceValue:specifier:);
        SEL expGetter = @selector(readExploitPreferenceValue:);
        
        NSSortDescriptor *prioritySortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"priority" ascending:NO];
        
        _availableKernelExploits = [[exploitManager availableExploitsForType:EXPLOIT_TYPE_KERNEL] sortedArrayUsingDescriptors:@[prioritySortDescriptor]];
        if (envManager.isArm64e) {
            _availablePACBypasses = [[exploitManager availableExploitsForType:EXPLOIT_TYPE_PAC] sortedArrayUsingDescriptors:@[prioritySortDescriptor]];
            _availablePPLBypasses = [[exploitManager availableExploitsForType:EXPLOIT_TYPE_PPL] sortedArrayUsingDescriptors:@[prioritySortDescriptor]];
        }
        
        PSSpecifier *headerSpecifier = [PSSpecifier emptyGroupSpecifier];
        [headerSpecifier setProperty:@"EUHeaderCell" forKey:@"headerCellClass"];
        [headerSpecifier setProperty:[NSString stringWithFormat:@"Settings"] forKey:@"title"];
        [specifiers addObject:headerSpecifier];
        
        if (envManager.isSupported) {
            if (!envManager.isJailbroken) {
                PSSpecifier *exploitGroupSpecifier = [PSSpecifier emptyGroupSpecifier];
                exploitGroupSpecifier.name = EULocalizedString(@"Section_Exploits");
                [specifiers addObject:exploitGroupSpecifier];
                
                PSSpecifier *kernelExploitSpecifier = [PSSpecifier preferenceSpecifierNamed:EULocalizedString(@"Kernel Exploit") target:self set:defSetter get:expGetter detail:nil cell:PSLinkListCell edit:nil];
                [kernelExploitSpecifier setProperty:@YES forKey:@"enabled"];
                [kernelExploitSpecifier setProperty:exploitManager.preferredKernelExploit.identifier forKey:@"default"];
                kernelExploitSpecifier.detailControllerClass = [EUPSExploitListItemsController class];
                [kernelExploitSpecifier setProperty:@"availableKernelExploitIdentifiers" forKey:@"valuesDataSource"];
                [kernelExploitSpecifier setProperty:@"availableKernelExploitNames" forKey:@"titlesDataSource"];
                [kernelExploitSpecifier setProperty:@"selectedKernelExploit" forKey:@"key"];
                [kernelExploitSpecifier setProperty:(_availableKernelExploits.firstObject.identifier ?: @"none") forKey:@"recommendedExploitIdentifier"];
                [specifiers addObject:kernelExploitSpecifier];
                
                if (envManager.isArm64e) {
                    PSSpecifier *pacBypassSpecifier = [PSSpecifier preferenceSpecifierNamed:EULocalizedString(@"PAC Bypass") target:self set:defSetter get:expGetter detail:nil cell:PSLinkListCell edit:nil];
                    [pacBypassSpecifier setProperty:@YES forKey:@"enabled"];
                    EUExploit *preferredPACBypass = exploitManager.preferredPACBypass;
                    if (!preferredPACBypass) {
                        [pacBypassSpecifier setProperty:@"none" forKey:@"default"];
                    }
                    else {
                        [pacBypassSpecifier setProperty:preferredPACBypass.identifier forKey:@"default"];
                    }
                    pacBypassSpecifier.detailControllerClass = [EUPSExploitListItemsController class];
                    [pacBypassSpecifier setProperty:@"availablePACBypassIdentifiers" forKey:@"valuesDataSource"];
                    [pacBypassSpecifier setProperty:@"availablePACBypassNames" forKey:@"titlesDataSource"];
                    [pacBypassSpecifier setProperty:@"selectedPACBypass" forKey:@"key"];
                    [pacBypassSpecifier setProperty:([envManager isPACBypassRequired] ? _availablePACBypasses.firstObject.identifier : @"none") forKey:@"recommendedExploitIdentifier"];
                    [specifiers addObject:pacBypassSpecifier];
                    
                    NSString *pplBypassName = @"PPL Bypass";
                    if ([EUEnvironmentManager sharedManager].isSPTM) {
                        // SPTM bypasses are also handled as PPL bypasses in the code, we just change the name of the setting in the UI
                        pplBypassName = @"SPTM Bypass";
                    }

                    PSSpecifier *pplBypassSpecifier = [PSSpecifier preferenceSpecifierNamed:EULocalizedString(pplBypassName) target:self set:defSetter get:expGetter detail:nil cell:PSLinkListCell edit:nil];
                    [pplBypassSpecifier setProperty:@YES forKey:@"enabled"];
                    [pplBypassSpecifier setProperty:exploitManager.preferredPPLBypass.identifier forKey:@"default"];
                    pplBypassSpecifier.detailControllerClass = [EUPSExploitListItemsController class];
                    [pplBypassSpecifier setProperty:@"availablePPLBypassIdentifiers" forKey:@"valuesDataSource"];
                    [pplBypassSpecifier setProperty:@"availablePPLBypassNames" forKey:@"titlesDataSource"];
                    [pplBypassSpecifier setProperty:@"selectedPPLBypass" forKey:@"key"];
                    [pplBypassSpecifier setProperty:(_availablePPLBypasses.firstObject.identifier ?: @"none") forKey:@"recommendedExploitIdentifier"];
                    [specifiers addObject:pplBypassSpecifier];
                }
            }
            
            PSSpecifier *settingsGroupSpecifier = [PSSpecifier emptyGroupSpecifier];
            settingsGroupSpecifier.name = EULocalizedString(@"Section_Jailbreak_Settings");
            [specifiers addObject:settingsGroupSpecifier];
            
            PSSpecifier *tweakInjectionSpecifier = [PSSpecifier preferenceSpecifierNamed:EULocalizedString(@"Settings_Tweak_Injection") target:self set:@selector(setTweakInjectionEnabled:specifier:) get:@selector(readTweakInjectionEnabled:) detail:nil cell:PSSwitchCell edit:nil];
            [tweakInjectionSpecifier setProperty:@YES forKey:@"enabled"];
            [tweakInjectionSpecifier setProperty:@"tweakInjectionEnabled" forKey:@"key"];
            [tweakInjectionSpecifier setProperty:@YES forKey:@"default"];
            [specifiers addObject:tweakInjectionSpecifier];
            
            if (!envManager.isJailbroken) {
                PSSpecifier *verboseLogSpecifier = [PSSpecifier preferenceSpecifierNamed:EULocalizedString(@"Settings_Verbose_Logs") target:self set:defSetter get:defGetter detail:nil cell:PSSwitchCell edit:nil];
                [verboseLogSpecifier setProperty:@YES forKey:@"enabled"];
                [verboseLogSpecifier setProperty:@"verboseLogsEnabled" forKey:@"key"];
                [verboseLogSpecifier setProperty:@NO forKey:@"default"];
                [specifiers addObject:verboseLogSpecifier];
            }
            
            PSSpecifier *idownloadSpecifier = [PSSpecifier preferenceSpecifierNamed:EULocalizedString(@"Settings_iDownload") target:self set:@selector(setIDownloadEnabled:specifier:) get:@selector(readIDownloadEnabled:) detail:nil cell:PSSwitchCell edit:nil];
            [idownloadSpecifier setProperty:@YES forKey:@"enabled"];
            [idownloadSpecifier setProperty:@"idownloadEnabled" forKey:@"key"];
            [idownloadSpecifier setProperty:@NO forKey:@"default"];
            [specifiers addObject:idownloadSpecifier];
            
            PSSpecifier *appJitSpecifier = [PSSpecifier preferenceSpecifierNamed:EULocalizedString(@"Settings_Apps_JIT") target:self set:@selector(setAppJITEnabled:specifier:) get:@selector(readAppJITEnabled:) detail:nil cell:PSSwitchCell edit:nil];
            [appJitSpecifier setProperty:@YES forKey:@"enabled"];
            [appJitSpecifier setProperty:@"appJITEnabled" forKey:@"key"];
            [appJitSpecifier setProperty:@YES forKey:@"default"];
            [specifiers addObject:appJitSpecifier];
            
            PSSpecifier *jetsamSpecifier = [PSSpecifier preferenceSpecifierNamed:EULocalizedString(@"Settings_Jetsam_Multiplier") target:self set:@selector(setJetsamMultiplier:specifier:) get:@selector(readJetsamMultiplier:) detail:nil cell:PSLinkListCell edit:nil];
            [jetsamSpecifier setProperty:@YES forKey:@"enabled"];
            [jetsamSpecifier setProperty:@"jetsamMultiplier" forKey:@"key"];
            [jetsamSpecifier setProperty:@6 forKey:@"default"];
            jetsamSpecifier.detailControllerClass = [EUPSJetsamListItemsController class];
            [jetsamSpecifier setProperty:@"jetsamOptionNumbers" forKey:@"valuesDataSource"];
            [jetsamSpecifier setProperty:@"jetsamOptionTitles" forKey:@"titlesDataSource"];
            [specifiers addObject:jetsamSpecifier];

            // R34 rootful 开关=C 侧统一落地（jbctl rootful enable/disable 实测后端，
            // 见下方 Section_Rootful 段+eutrolle_rootfulSupported 矩阵判定）；
            // B 侧 jbsettings 路线已去重移除，避免双开关/双访问器冲突。
            
            if (!envManager.isJailbroken && !envManager.isInstalledThroughTrollStore) {
                PSSpecifier *removeJailbreakSwitchSpecifier = [PSSpecifier preferenceSpecifierNamed:EULocalizedString(@"Button_Remove_Jailbreak") target:self set:@selector(setRemoveJailbreakEnabled:specifier:) get:defGetter detail:nil cell:PSSwitchCell edit:nil];
                [removeJailbreakSwitchSpecifier setProperty:@YES forKey:@"enabled"];
                [removeJailbreakSwitchSpecifier setProperty:@"removeJailbreakEnabled" forKey:@"key"];
                [specifiers addObject:removeJailbreakSwitchSpecifier];
            }

            if (envManager.isBootstrapped) {
                PSSpecifier *actionsGroupSpecifier = [PSSpecifier emptyGroupSpecifier];
                actionsGroupSpecifier.name = EULocalizedString(@"Section_Actions");
                [specifiers addObject:actionsGroupSpecifier];

                if (envManager.isJailbroken) {
                    PSSpecifier *refreshAppsSpecifier = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:defSetter get:defGetter detail:nil cell:PSStaticTextCell edit:nil];
                    [refreshAppsSpecifier setProperty:@"Button_Refresh_Jailbreak_Apps" forKey:@"title"];
                    [refreshAppsSpecifier setProperty:[EUButtonCell class] forKey:@"cellClass"];
                    [refreshAppsSpecifier setProperty:buttonHeight forKey:@"height"];
                    [refreshAppsSpecifier setProperty:@"arrow.triangle.2.circlepath" forKey:@"image"];
                    [refreshAppsSpecifier setProperty:@"refreshJailbreakAppsPressed" forKey:@"action"];
                    [specifiers addObject:refreshAppsSpecifier];
                    
                    PSSpecifier *changeMobilePasswordSpecifier = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:defSetter get:defGetter detail:nil cell:PSStaticTextCell edit:nil];
                    [changeMobilePasswordSpecifier setProperty:@"Button_Change_Mobile_Password" forKey:@"title"];
                    [changeMobilePasswordSpecifier setProperty:[EUButtonCell class] forKey:@"cellClass"];
                    [changeMobilePasswordSpecifier setProperty:buttonHeight forKey:@"height"];
                    [changeMobilePasswordSpecifier setProperty:@"key" forKey:@"image"];
                    [changeMobilePasswordSpecifier setProperty:@"changeMobilePasswordWithAuthenticationPressed" forKey:@"action"];
                    [specifiers addObject:changeMobilePasswordSpecifier];
                    
                    PSSpecifier *reinstallPackageManagersSpecifier = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:defSetter get:defGetter detail:nil cell:PSStaticTextCell edit:nil];
                    [reinstallPackageManagersSpecifier setProperty:@"Button_Reinstall_Package_Managers" forKey:@"title"];
                    [reinstallPackageManagersSpecifier setProperty:[EUButtonCell class] forKey:@"cellClass"];
                    [reinstallPackageManagersSpecifier setProperty:buttonHeight forKey:@"height"];
                    if (@available(iOS 16.0, *))
                        [reinstallPackageManagersSpecifier setProperty:@"shippingbox.and.arrow.backward" forKey:@"image"];
                    else
                        [reinstallPackageManagersSpecifier setProperty:@"shippingbox" forKey:@"image"];
                    [reinstallPackageManagersSpecifier setProperty:@"reinstallPackageManagersPressed" forKey:@"action"];
                    [specifiers addObject:reinstallPackageManagersSpecifier];
                }

                // 【固定 rootful 化（2026-10-11 用户定案：固定 rootful、砍无根、
                // 保留隐藏）】roothide/aegis/cloak/rootless-hideJb 四个模式开关全部
                // 退役：rootful 是本构建的身份而非选项（服务端 jbsettings 对
                // rootfulUserEnabled/roothideUserEnabled 恒答 true 且拒绝写入）；
                // 隐藏环境（cloak+aegis 白名单制）随 rootful 恒随行（R4），运维退
                // 路走 marker 文件（/basebin/.cloak_disabled 等），UI 不再提供第二
                // 退路（D2 拍板）。矩阵外设备整段由 eutrolle_rootfulSupported 隐藏。

                // （原 aegis/cloak/rootless-hideJb 三开关区已随固定 rootful 化移除）

                // 移除越狱按钮（用户 08-28 00:19："越狱后移除越狱的按钮被吃掉了吗"——恢复越狱态可见）
                // 越狱中按下=deleteBootstrap 后 userspace reboot 完成卸载（removeJailbreakPressed 现有逻辑）；
                // 未越狱=任意安装渠道（TrollStore/自签）都可清残留 /var/jb。
                // 原 Dopamine 注释的" russian roulette"担忧仅指不重启的半卸载；本流程删后必重启，安全。
                {
                    PSSpecifier *removeJailbreakSpecifier = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:defSetter get:defGetter detail:nil cell:PSStaticTextCell edit:nil];
                    [removeJailbreakSpecifier setProperty:@"Button_Remove_Jailbreak" forKey:@"title"];
                    [removeJailbreakSpecifier setProperty:[EUButtonCell class] forKey:@"cellClass"];
                    [removeJailbreakSpecifier setProperty:buttonHeight forKey:@"height"];
                    [removeJailbreakSpecifier setProperty:@"trash" forKey:@"image"];
                    [removeJailbreakSpecifier setProperty:@"removeJailbreakPressed" forKey:@"action"];
                    [specifiers addObject:removeJailbreakSpecifier];
                }
            }
        }

        // Rootful——固定启用（2026-10-11 用户定案：固定 rootful、砍无根）。
        // 开关退役为静态说明：rootful 是本构建的身份而非选项（服务端 jbsettings
        // 恒答 true 且拒绝写入）。矩阵（R4：A12/A13 @ iOS 16.6.1-18.7.1）外整段
        // 隐藏（D1 App 层 UX 预检；daemon 侧硬停才是权威门，见 euphoria/main.m）。
        if ([self eutrolle_rootfulSupported]) {
            PSSpecifier *rootfulGroupSpecifier = [PSSpecifier emptyGroupSpecifier];
            rootfulGroupSpecifier.name = EULocalizedString(@"Section_Rootful");
            [specifiers addObject:rootfulGroupSpecifier];

            PSSpecifier *rootfulFixedSpecifier = [PSSpecifier preferenceSpecifierNamed:EULocalizedString(@"Rootful_Mode") target:self set:defSetter get:defGetter detail:nil cell:PSStaticTextCell edit:nil];
            [rootfulFixedSpecifier setProperty:EULocalizedString(@"Enabled") forKey:@"title"];
            [rootfulFixedSpecifier setProperty:EULocalizedString(@"Rootful_Mode_Fixed_Footer") forKey:@"footer"];
            [specifiers addObject:rootfulFixedSpecifier];
        }

        PSSpecifier *themingGroupSpecifier = [PSSpecifier emptyGroupSpecifier];
        themingGroupSpecifier.name = EULocalizedString(@"Section_Customization");
        [specifiers addObject:themingGroupSpecifier];

        // 皮肤选择器（用户 08-28 10:18 裁定"背景板一个就行"）：单一品牌色后仅 1 套主题
        // →选择器入口隐藏（无意义的多选一）；未来若恢复多皮肤（皮肤↔图标 1:1 联动）
        // 数组自然 >1，入口自动回来——按数量动态显隐，不写死。
        if ([[self themeIdentifiers] count] > 1) {
            PSSpecifier *themeSpecifier = [PSSpecifier preferenceSpecifierNamed:EULocalizedString(@"Theme") target:self set:defSetter get:defGetter detail:nil cell:PSLinkListCell edit:nil];
            themeSpecifier.detailControllerClass = [EUPSListItemsController class];
            [themeSpecifier setProperty:@YES forKey:@"enabled"];
            [themeSpecifier setProperty:@"theme" forKey:@"key"];
            [themeSpecifier setProperty:[[self themeIdentifiers] firstObject] forKey:@"default"];
            [themeSpecifier setProperty:@"themeIdentifiers" forKey:@"valuesDataSource"];
            [themeSpecifier setProperty:@"themeNames" forKey:@"titlesDataSource"];
            [specifiers addObject:themeSpecifier];
        }

        PSSpecifier *bootlogoGropSpecifier = [PSSpecifier emptyGroupSpecifier];
        bootlogoGropSpecifier.name = EULocalizedString(@"Section_Boot_Logo");
        [specifiers addObject:bootlogoGropSpecifier];

        PSSpecifier *bootlogoEnabledSpecifier = [PSSpecifier preferenceSpecifierNamed:EULocalizedString(@"Enabled") target:self set:@selector(setBootlogoEnabled:specifier:) get:defGetter detail:nil cell:PSSwitchCell edit:nil];
        [bootlogoEnabledSpecifier setProperty:@YES forKey:@"enabled"];
        [bootlogoEnabledSpecifier setProperty:@"bootlogoEnabled" forKey:@"key"];
        [bootlogoEnabledSpecifier setProperty:@YES forKey:@"default"];
        bootlogoEnabledSpecifier.identifier = @"bootlogoEnabled";
        [specifiers addObject:bootlogoEnabledSpecifier];

        _customBootlogoEnabledSpecifier = [PSSpecifier preferenceSpecifierNamed:EULocalizedString(@"Custom_Boot_Logo") target:self set:@selector(setCustomBootlogoEnabled:specifier:) get:defGetter detail:nil cell:PSSwitchCell edit:nil];
        [_customBootlogoEnabledSpecifier setProperty:@YES forKey:@"enabled"];
        [_customBootlogoEnabledSpecifier setProperty:@"customBootlogoEnabled" forKey:@"key"];
        [_customBootlogoEnabledSpecifier setProperty:@NO forKey:@"default"];
        _customBootlogoEnabledSpecifier.identifier = @"customBootlogoEnabled";

        _customBootlogoSpecifier = [PSSpecifier preferenceSpecifierNamed:EULocalizedString(@"Select_Image") target:self set:defSetter get:defGetter detail:nil cell:PSButtonCell edit:nil];
        _customBootlogoSpecifier.buttonAction = @selector(selectCustomBootlogoPressed);
        [_customBootlogoSpecifier setProperty:@YES forKey:@"enabled"];
        [_customBootlogoSpecifier setProperty:@"customBootlogo" forKey:@"key"];
        _customBootlogoSpecifier.identifier = @"customBootlogo";

        if ([[EUPreferenceManager sharedManager] boolPreferenceValueForKey:@"bootlogoEnabled" fallback:YES]) {
            [specifiers addObject:_customBootlogoEnabledSpecifier];

            if ([[EUPreferenceManager sharedManager] boolPreferenceValueForKey:@"customBootlogoEnabled" fallback:NO]) {
                [specifiers addObject:_customBootlogoSpecifier];
            }
        }

        _specifiers = specifiers;
    }
    return _specifiers;
}

#pragma mark - Getters & Setters

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier
{
    NSString *key = [specifier propertyForKey:@"key"];
    [[EUPreferenceManager sharedManager] setPreferenceValue:value forKey:key];
}

- (id)readPreferenceValue:(PSSpecifier*)specifier
{
    NSString *key = [specifier propertyForKey:@"key"];
    id value = [[EUPreferenceManager sharedManager] preferenceValueForKey:key];
    if (!value) {
        return [specifier propertyForKey:@"default"];
    }
    return value;
}

- (id)readExploitPreferenceValue:(PSSpecifier *)specifier
{
    id value = [self readPreferenceValue:specifier];

    SEL dataSourceSel = nil;
    NSString *selString = [specifier propertyForKey:@"valuesDataSource"];
    if (selString) {
        dataSourceSel = NSSelectorFromString(selString);
    }

    if (dataSourceSel && [value isKindOfClass:[NSString class]]) {
        NSString *valueString = (NSString *)value;

        IMP imp = [specifier.target methodForSelector:dataSourceSel];
        if (imp) {
            NSArray *(*func)(id, SEL) = (void *)imp;
            NSArray *availableIdentifiers = func(specifier.target, dataSourceSel);
            if (![availableIdentifiers containsObject:valueString]) {
                return [specifier propertyForKey:@"default"];
            }
        }
    }

    return value;
}

- (id)readIDownloadEnabled:(PSSpecifier *)specifier
{
    EUEnvironmentManager *envManager = [EUEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        return @([EUEnvironmentManager sharedManager].isIDownloadEnabled);
    }
    return [self readPreferenceValue:specifier];
}

- (void)setIDownloadEnabled:(id)value specifier:(PSSpecifier *)specifier
{
    [self setPreferenceValue:value specifier:specifier];
    EUEnvironmentManager *envManager = [EUEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        [[EUEnvironmentManager sharedManager] setIDownloadLoaded:((NSNumber *)value).boolValue needsUnsandbox:YES];
    }
}

- (id)readTweakInjectionEnabled:(PSSpecifier *)specifier
{
    EUEnvironmentManager *envManager = [EUEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        return @([EUEnvironmentManager sharedManager].isTweakInjectionEnabled);
    }
    return [self readPreferenceValue:specifier];
}

- (void)setTweakInjectionEnabled:(id)value specifier:(PSSpecifier *)specifier
{
    [self setPreferenceValue:value specifier:specifier];
    EUEnvironmentManager *envManager = [EUEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        [[EUEnvironmentManager sharedManager] setTweakInjectionEnabled:((NSNumber *)value).boolValue];
        UIAlertController *userspaceRebootAlertController = [UIAlertController alertControllerWithTitle:EULocalizedString(@"Alert_Tweak_Injection_Toggled_Title") message:EULocalizedString(@"Alert_Tweak_Injection_Toggled_Body") preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *rebootNowAction = [UIAlertAction actionWithTitle:EULocalizedString(@"Alert_Tweak_Injection_Toggled_Reboot_Now") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [[EUEnvironmentManager sharedManager] rebootUserspace];
        }];
        UIAlertAction *rebootLaterAction = [UIAlertAction actionWithTitle:EULocalizedString(@"Alert_Tweak_Injection_Toggled_Reboot_Later") style:UIAlertActionStyleCancel handler:nil];
        
        [userspaceRebootAlertController addAction:rebootNowAction];
        [userspaceRebootAlertController addAction:rebootLaterAction];
        [self presentViewController:userspaceRebootAlertController animated:YES completion:nil];
    }
}

- (id)readAppJITEnabled:(PSSpecifier *)specifier
{
    EUEnvironmentManager *envManager = [EUEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        bool v = jbclient_jbsettings_get_bool("markAppsAsDebugged");
        return @(v);
    }
    return [self readPreferenceValue:specifier];
}

- (void)setAppJITEnabled:(id)value specifier:(PSSpecifier *)specifier
{
    [self setPreferenceValue:value specifier:specifier];
    EUEnvironmentManager *envManager = [EUEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        jbclient_platform_jbsettings_set_bool("markAppsAsDebugged", ((NSNumber *)value).boolValue);
    }
}

- (id)readJetsamMultiplier:(PSSpecifier *)specifier
{
    EUEnvironmentManager *envManager = [EUEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        double v = jbclient_jbsettings_get_double("jetsamMultiplier");
        return @((v < 1 || isnan(v)) ? 6 : ceil(v * 2));
    }
    return [self readPreferenceValue:specifier];
}

- (void)setJetsamMultiplier:(id)value specifier:(PSSpecifier *)specifier
{
    [self setPreferenceValue:value specifier:specifier];
    EUEnvironmentManager *envManager = [EUEnvironmentManager sharedManager];
    if (envManager.isJailbroken) {
        jbclient_platform_jbsettings_set_double("jetsamMultiplier", ((NSNumber *)value).doubleValue / 2);
    }
}

- (void)setRemoveJailbreakEnabled:(id)value specifier:(PSSpecifier *)specifier
{
    [self setPreferenceValue:value specifier:specifier];
    if (((NSNumber *)value).boolValue) {
        UIAlertController *confirmationAlertController = [UIAlertController alertControllerWithTitle:EULocalizedString(@"Alert_Remove_Jailbreak_Title") message:EULocalizedString(@"Alert_Remove_Jailbreak_Enabled_Body") preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *uninstallAction = [UIAlertAction actionWithTitle:EULocalizedString(@"Button_Continue") style:UIAlertActionStyleDestructive handler:nil];
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:EULocalizedString(@"Button_Cancel") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self setPreferenceValue:@NO specifier:specifier];
            [self reloadSpecifiers];
        }];
        [confirmationAlertController addAction:uninstallAction];
        [confirmationAlertController addAction:cancelAction];
        [self presentViewController:confirmationAlertController animated:YES completion:nil];
    }
}

- (void)setBootlogoEnabled:(id)value specifier:(PSSpecifier *)specifier
{
    bool prevValueBool = ((NSNumber *)[self readPreferenceValue:specifier]).boolValue;
    [self setPreferenceValue:value specifier:specifier];
    bool valueBool = ((NSNumber *)value).boolValue;

    if (prevValueBool != valueBool) {
        NSMutableArray *affectedSpecifiers = [NSMutableArray new];
        [affectedSpecifiers addObject:_customBootlogoEnabledSpecifier];

        if (valueBool == ![self containsSpecifier:_customBootlogoSpecifier]) {
            [affectedSpecifiers addObject:_customBootlogoSpecifier];
        }

        if (valueBool) {
            [self insertContiguousSpecifiers:affectedSpecifiers afterSpecifier:specifier animated:YES];
        }
        else {
            [self removeContiguousSpecifiers:affectedSpecifiers animated:YES];
        }
    }

    if ([EUEnvironmentManager sharedManager].isJailbroken) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [[EUEnvironmentManager sharedManager] updateBootLogo];
        });
    }
}

- (void)setCustomBootlogoEnabled:(id)value specifier:(PSSpecifier *)specifier
{
    bool prevValueBool = ((NSNumber *)[self readPreferenceValue:specifier]).boolValue;
    [self setPreferenceValue:value specifier:specifier];
    bool valueBool = ((NSNumber *)value).boolValue;

    if (prevValueBool != valueBool) {
        if (valueBool) {
            [self insertSpecifier:_customBootlogoSpecifier afterSpecifier:specifier animated:YES];
        }
        else {
            [self removeSpecifier:_customBootlogoSpecifier animated:YES];
        }
    }

    if ([EUEnvironmentManager sharedManager].isJailbroken) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [[EUEnvironmentManager sharedManager] updateBootLogo];
        });
    }
}

- (void)selectCustomBootlogoPressed
{
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if (status == PHAuthorizationStatusDenied || status == PHAuthorizationStatusRestricted) {
        return;
    } else if (status == PHAuthorizationStatusNotDetermined) {
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            if (status == PHAuthorizationStatusAuthorized) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self selectCustomBootlogoPressed];
                });
            }
        }];
        return;
    }

    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - Boot Logo Picker

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info {
    UIImage *chosenImage = info[UIImagePickerControllerEditedImage];
    if (!chosenImage) {
        chosenImage = info[UIImagePickerControllerOriginalImage];
    }

    // Force correct the orientation
    // For some reason without rerendering the image, the stored file will have a wrong orientation for photos taken with the camera‚
    UIGraphicsBeginImageContextWithOptions(chosenImage.size, NO, 1.0);
    [chosenImage drawInRect:CGRectMake(0,0, chosenImage.size.width, chosenImage.size.height)];
    chosenImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    [UIImagePNGRepresentation(chosenImage) writeToFile:[EUUIManager sharedInstance].bootlogoPath atomically:YES];

    if ([EUEnvironmentManager sharedManager].isJailbroken) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [[EUEnvironmentManager sharedManager] updateBootLogo];
        });
    }

    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Button Actions

- (void)refreshJailbreakAppsPressed
{
    [[EUEnvironmentManager sharedManager] refreshJailbreakApps];
}

- (void)reinstallPackageManagersPressed
{
    [self.navigationController pushViewController:[[EUPkgManagerPickerViewController alloc] init] animated:YES];
}

- (void)changeMobilePasswordWithAuthenticationPressed
{
        LAContext *context = [[LAContext alloc] init];
        NSError *authError = nil;
        NSString *reason = EULocalizedString(@"Password_Auth_Required");
        
        if ([context canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication error:&authError]) {
                [context evaluatePolicy:LAPolicyDeviceOwnerAuthentication
                        localizedReason:reason
                        reply:^(BOOL success, NSError * _Nullable error) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                                if (success) {
                                        [self changeMobilePassword];
                                }
                        });
                }];
        }
        else {
                [self changeMobilePassword];
        }
}

- (void)changeMobilePassword
{
    UIAlertController *changeMobilePasswordAlert = [UIAlertController alertControllerWithTitle:EULocalizedString(@"Button_Change_Mobile_Password") message:EULocalizedString(@"Alert_Change_Mobile_Password_Body") preferredStyle:UIAlertControllerStyleAlert];
    
    [changeMobilePasswordAlert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = EULocalizedString(@"Password_Placeholder");
        textField.secureTextEntry = YES;
    }];
    
    [changeMobilePasswordAlert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = EULocalizedString(@"Repeat_Password_Placeholder");
        textField.secureTextEntry = YES;
    }];
    
    UIAlertAction *changeButton = [UIAlertAction actionWithTitle:EULocalizedString(@"Button_Change") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action){
        NSString *password = changeMobilePasswordAlert.textFields[0].text;
        NSString *repeatPassword = changeMobilePasswordAlert.textFields[1].text;
        if (![password isEqualToString:repeatPassword]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self changeMobilePassword];
            });
        }
        else {
            [[EUEnvironmentManager sharedManager] changeMobilePassword:password];
        }
    }];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:EULocalizedString(@"Button_Cancel") style:UIAlertActionStyleCancel handler:nil];
    [changeMobilePasswordAlert addAction:changeButton];
    [changeMobilePasswordAlert addAction:cancelAction];
    [self presentViewController:changeMobilePasswordAlert animated:YES completion:nil];
}

- (void)removeJailbreakPressed
{
    UIAlertController *confirmationAlertController = [UIAlertController alertControllerWithTitle:EULocalizedString(@"Alert_Remove_Jailbreak_Title") message:EULocalizedString(@"Alert_Remove_Jailbreak_Pressed_Body") preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *uninstallAction = [UIAlertAction actionWithTitle:EULocalizedString(@"Button_Continue") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [[EUEnvironmentManager sharedManager] deleteBootstrap];
        if ([EUEnvironmentManager sharedManager].isJailbroken) {
            [[EUEnvironmentManager sharedManager] reboot];
        }
        else {
            if (gSystemInfo.jailbreakInfo.rootPath) {
                free(gSystemInfo.jailbreakInfo.rootPath);
                gSystemInfo.jailbreakInfo.rootPath = NULL;
                [[EUEnvironmentManager sharedManager] locateJailbreakRoot];
            }
            [self reloadSpecifiers];
        }
    }];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:EULocalizedString(@"Button_Cancel") style:UIAlertActionStyleDefault handler:nil];
    [confirmationAlertController addAction:uninstallAction];
    [confirmationAlertController addAction:cancelAction];
    [self presentViewController:confirmationAlertController animated:YES completion:nil];
}

- (void)resetSettingsPressed
{
    [[EUUIManager sharedInstance] resetSettings];
    [self.navigationController popToRootViewControllerAnimated:YES];
    [self reloadSpecifiers];
}

#pragma mark - Rootful（T15）与 Aegis（R27 恢复）

// R4 rootful 矩阵：A12/A13 @ iOS 16.6.1–18.7.1
// （cpufamily 值与 dmaFail.c 设备表同源：A12=0x07D34B9F / A13=0x462504D2）
- (BOOL)eutrolle_rootfulSupported
{
    cpu_subtype_t cpuFamily = 0;
    size_t len = sizeof(cpuFamily);
    if (sysctlbyname("hw.cpufamily", &cpuFamily, &len, NULL, 0) != 0) return NO;

    BOOL cpuOK = (cpuFamily == 0x07D34B9F /* A12 */ || cpuFamily == 0x462504D2 /* A13 */);
    if (!cpuOK) return NO;

    NSOperatingSystemVersion v = [NSProcessInfo processInfo].operatingSystemVersion;
    if (v.majorVersion != 16 && v.majorVersion != 17 && v.majorVersion != 18) return NO;
    if (v.majorVersion == 16 && v.minorVersion < 6) return NO;                    // <16.6
    if (v.majorVersion == 16 && v.minorVersion == 6 && v.patchVersion < 1) return NO; // 16.6.0
    if (v.majorVersion == 18 && v.minorVersion > 7) return NO;                   // >18.7
    if (v.majorVersion == 18 && v.minorVersion == 7 && v.patchVersion > 1) return NO; // >18.7.1
    return YES;
}



- (void)purgeRootfulPressed
{
    // 后端（jbctl purge 子命令）尚未落地（T15 规格超前）——保留方法体，按钮暂不挂出。
    // 待 B 落"卸载+销毁卷+清状态"后端后，在 Rootful 段恢复红色按钮+二次确认。
    [[EUUIManager sharedInstance] sendLog:@"rootful purge 后端未落地（按钮已按实际能力隐藏）" debug:YES];
}



@end
