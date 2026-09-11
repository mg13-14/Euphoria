//
//  EUMainViewController.m
//  Euphoria
//
//  Created by tomt000 on 08/01/2024.
//

#import "EUMainViewController.h"
#import "EUUIManager.h"
#import "EUEnvironmentManager.h"
#import "EUJailbreaker.h"
#import "EUGlobalAppearance.h"
#import "EUActionMenuButton.h"
#import "EUUpdateViewController.h"
#import "EULogCrashViewController.h"
#import "EUTrollE.h"
#import "EUPkgManagerPickerViewController.h"
#import "EUTrollEMainViewController.h" // 巨魔E 主页（2026-09-07 20:55 用户指令：TrollStore 式+底栏三 tab）
#import <pthread.h>
#import <sys/sysctl.h>
#import <libjailbreak/libjailbreak.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// 巨魔E 入口（B ③ spec / 08 规范 / R35 域契约）——CT 永久子域判定（C24 矩阵 UI 面）：
//   ① 14.0b2~16.6.1 全系 ② 16.7 b/RC(20H18) ③ 17.0 各 build。
//   build 级精确（kern.osversion sysctl）：16.7 用 20H18/20H19 分界；粗版本先行短路。
//   域内未越狱=引擎B（CT 永久签印）；域外（16.7GA/17.0.1+/18.x/26.x）=引擎C 结界庇护。
//   2026-09-06 C 修复（kimik3 清单⑬）：17.0.1+（patch≥1，如 17.0.1~17.0.3）
//   原判定 `minorVersion == 0` 误判域内——补 patchVersion 判定；16.7 分界与主树
//   EUTrollE.m 统一为精确 20H18（原 <= 字典序偏宽）。
//   落码：并行搜索员C，2026-09-05（主 App 入口半场）。
BOOL EUTrollECTPermanentDomain(void) // v1.0.5 链接修复：去 static——EUTrollEMainViewController.m:34 extern 引用需要外部链接
{
    NSOperatingSystemVersion v = [NSProcessInfo processInfo].operatingSystemVersion;
    if (v.majorVersion == 17) return (v.minorVersion == 0 && v.patchVersion == 0);
    if (v.majorVersion == 16) {
        if (v.minorVersion < 7) return YES;
        if (v.minorVersion > 7) return NO;
        // 16.7：b/RC(20H18) 在域内，GA(20H19+) 域外——build 精确判定
        char build[64] = {0};
        size_t len = sizeof(build) - 1;
        if (sysctlbyname("kern.osversion", build, &len, NULL, 0) != 0) return NO;
        return (strcmp(build, "20H18") == 0); // 与主树 EUTrollE.m 同口径
    }
    if (v.majorVersion == 15) return YES;
    if (v.majorVersion == 14) return YES; // 代码超集（R35 承诺域从 15.0 起，14.x 不对外承诺）
    return NO; // 18.x / 26.x / 其它
}

@interface EUMainViewController () <UIDocumentPickerDelegate>

@property EUJailbreakButton *jailbreakBtn;
@property NSArray<NSLayoutConstraint *> *jailbreakButtonConstraints;
@property EUActionMenuButton *updateButton;
@property(nonatomic) BOOL hideStatusBar;
@property(nonatomic) BOOL hideHomeIndicator;

@end

@implementation EUMainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupStack];
}

-(void)setupStack
{
    UIStackView *stackView = [[UIStackView alloc] init];
    [stackView setAxis:UILayoutConstraintAxisVertical];
    [stackView setAlignment:UIStackViewAlignmentTrailing];
    [stackView setDistribution:UIStackViewDistributionEqualSpacing];
    [stackView setTranslatesAutoresizingMaskIntoConstraints:NO];

    [self.view addSubview:stackView];


    int statusBarHeight = fmax(15, [[UIApplication sharedApplication] keyWindow].safeAreaInsets.top - 20);

    [NSLayoutConstraint activateConstraints:@[
        [stackView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:statusBarHeight],//-35
        [stackView.heightAnchor constraintEqualToAnchor:self.view.heightAnchor multiplier:[EUGlobalAppearance isHomeButtonDevice] ? 0.78 : 0.73]
    ]];

    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    {
        NSLayoutConstraint *relativeWidthConstraint = [stackView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:0.8];
        relativeWidthConstraint.priority = UILayoutPriorityDefaultHigh;
        NSLayoutConstraint *maxWidthConstraint = [stackView.widthAnchor constraintLessThanOrEqualToConstant:UI_IPAD_MAX_WIDTH];
        maxWidthConstraint.priority = UILayoutPriorityRequired;

        [NSLayoutConstraint activateConstraints:@[
            relativeWidthConstraint,
            maxWidthConstraint,
            [stackView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor]
        ]];
    }
    else
    {
        [NSLayoutConstraint activateConstraints:@[
            [stackView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:UI_PADDING],
            [stackView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-UI_PADDING],
        ]];
    }

    //Header
    EUHeaderView *headerView = [[EUHeaderView alloc] initWithImage: [UIImage imageNamed:@"Euphoria"] subtitles: @[
        [EUGlobalAppearance mainSubtitleString:[[EUEnvironmentManager sharedManager] versionSupportString]],
        [EUGlobalAppearance secondarySubtitleString:EULocalizedString(@"Credits_Made_By")],
    ]];
    
    [stackView addArrangedSubview:headerView];

    [NSLayoutConstraint activateConstraints:@[
        [headerView.leadingAnchor constraintEqualToAnchor:stackView.leadingAnchor constant:5],
        [headerView.trailingAnchor constraintEqualToAnchor:stackView.trailingAnchor]
    ]];
    
    //Action Menu
    EUActionMenuView *actionView = [[EUActionMenuView alloc] initWithActions:@[
        // 巨魔E 入口（B ③ spec：双态可见；三态徽标语义先于仙气——08 规范 §五/§九.3，
        // 文案用 B 线已集成方言保持两 App 一致）
        // 2026-09-07 20:55 用户指令升级：入口改为进巨魔E 主页（TrollStore 式列表
        // +底部小横板三 tab：应用/插件注入/设置，参考巨魔R）——C 线 ③ 数据层+页骨架
        [UIAction actionWithTitle:[self trolleMenuTitle] image:[UIImage systemImageNamed:@"sparkles" withConfiguration:[EUGlobalAppearance smallIconImageConfiguration]] identifier:@"trolle-install" handler:^(__kindof UIAction * _Nonnull action) {
            [self.navigationController pushViewController:[[EUTrollEMainViewController alloc] init] animated:YES];
        }],
        // EPM 入口（T18 契约 v1 内嵌页：已装清单+刷新；用户 19:35:28 点名补位）
        [UIAction actionWithTitle:@"EPM · 仙市（自研包管理器）" image:[UIImage systemImageNamed:@"shippingbox.fill" withConfiguration:[EUGlobalAppearance smallIconImageConfiguration]] identifier:@"epm-packages" handler:^(__kindof UIAction * _Nonnull action) {
            [self.navigationController pushViewController:[[EUPMPackagesViewController alloc] init] animated:YES];
        }],
        [UIAction actionWithTitle:EULocalizedString(@"Menu_Settings_Title") image:[UIImage systemImageNamed:@"gearshape" withConfiguration:[EUGlobalAppearance smallIconImageConfiguration]] identifier:@"settings" handler:^(__kindof UIAction * _Nonnull action) {
            [self.navigationController pushViewController:[[EUSettingsController alloc] init] animated:YES];
        }],
        [UIAction actionWithTitle:EULocalizedString(@"Menu_Restart_SpringBoard_Title") image:[UIImage systemImageNamed:@"arrow.clockwise" withConfiguration:[EUGlobalAppearance smallIconImageConfiguration]] identifier:@"respring" handler:^(__kindof UIAction * _Nonnull action) {
            [self fadeToBlack:^{
                [[EUEnvironmentManager sharedManager] respring];
            }];
        }],
        [UIAction actionWithTitle:EULocalizedString(@"Menu_Reboot_Userspace_Title") image:[UIImage systemImageNamed:@"arrow.clockwise.circle" withConfiguration:[EUGlobalAppearance smallIconImageConfiguration]] identifier:@"reboot-userspace" handler:^(__kindof UIAction * _Nonnull action) {
            [self fadeToBlack:^{
                [[EUEnvironmentManager sharedManager] rebootUserspace];
            }];
        }],
        [UIAction actionWithTitle:EULocalizedString(@"Menu_Credits_Title") image:[UIImage systemImageNamed:@"info.circle" withConfiguration:[EUGlobalAppearance smallIconImageConfiguration]] identifier:@"credits" handler:^(__kindof UIAction * _Nonnull action) {
            [self.navigationController pushViewController:[[EUCreditsViewController alloc] init] animated:YES];
        }]
    ] delegate:self];
    
    [stackView addArrangedSubview: actionView];

    [NSLayoutConstraint activateConstraints:@[
        [actionView.leadingAnchor constraintEqualToAnchor:stackView.leadingAnchor],
        [actionView.trailingAnchor constraintEqualToAnchor:stackView.trailingAnchor],
    ]];
    
    
    UIView *buttonPlaceHolder = [[UIView alloc] init];
    [buttonPlaceHolder setTranslatesAutoresizingMaskIntoConstraints:NO];
    [stackView addArrangedSubview:buttonPlaceHolder];
    [NSLayoutConstraint activateConstraints:@[
        [buttonPlaceHolder.heightAnchor constraintEqualToConstant:60]
    ]];
    
    //Jailbreak Button
    BOOL isJailbroken = [[EUEnvironmentManager sharedManager] isJailbroken] || [[EUEnvironmentManager sharedManager] isJailbrokenWithOtherJailbreak];
    BOOL isSupported = [[EUEnvironmentManager sharedManager] isSupported];

    NSString *jailbreakButtonTitle = [self jailbreakButtonTitle];
        
    UIImage *jailbreakButtonImage;
    if (isSupported)
        jailbreakButtonImage = [UIImage systemImageNamed:@"lock.open" withConfiguration:[EUGlobalAppearance smallIconImageConfiguration]];
    else
        jailbreakButtonImage = [UIImage systemImageNamed:@"lock.slash" withConfiguration:[EUGlobalAppearance smallIconImageConfiguration]];
    
    self.jailbreakBtn = [[EUJailbreakButton alloc] initWithAction: [UIAction actionWithTitle:jailbreakButtonTitle image:jailbreakButtonImage identifier:@"jailbreak" handler:^(__kindof UIAction * _Nonnull action) {
        [actionView hide];
        [self.jailbreakBtn expandButton: self.jailbreakButtonConstraints];

        self.updateButton.userInteractionEnabled = NO;
        [UIView animateWithDuration:0.75 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:2.0  options: UIViewAnimationOptionCurveEaseInOut animations:^{
            [headerView setTransform:CGAffineTransformMakeTranslation(0, -25)];
            self.updateButton.alpha = 0;
        } completion:nil];
        
        [self startJailbreak];
        
    }]];
    self.jailbreakBtn.enabled = !isJailbroken && isSupported;

    [self.view addSubview:self.jailbreakBtn];

    [NSLayoutConstraint activateConstraints:(self.jailbreakButtonConstraints = @[
        [self.jailbreakBtn.leadingAnchor constraintEqualToAnchor:stackView.leadingAnchor],
        [self.jailbreakBtn.trailingAnchor constraintEqualToAnchor:stackView.trailingAnchor],
        [self.jailbreakBtn.heightAnchor constraintEqualToAnchor:buttonPlaceHolder.heightAnchor],
        [self.jailbreakBtn.centerYAnchor constraintEqualToAnchor:buttonPlaceHolder.centerYAnchor]
    ])];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        if ([[EUUIManager sharedInstance] environmentUpdateAvailable])
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setupUpdateAvailable:YES];
            });
        }
        else if ([[EUUIManager sharedInstance] isUpdateAvailable])
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setupUpdateAvailable:NO];
            });
        }
    });
}

- (NSString *)jailbreakButtonTitle
{
    BOOL isJailbroken = [[EUEnvironmentManager sharedManager] isJailbroken];
    BOOL isSupported = [[EUEnvironmentManager sharedManager] isSupported];
    BOOL removeJailbreakEnabled = [[EUPreferenceManager sharedManager] boolPreferenceValueForKey:@"removeJailbreakEnabled" fallback:NO];

    NSString *jailbreakButtonTitle = EULocalizedString(@"Button_Jailbreak_Title");
    if (!isSupported)
        jailbreakButtonTitle = EULocalizedString(@"Unsupported");
    else if (isJailbroken)
        jailbreakButtonTitle = EULocalizedString(@"Status_Title_Jailbroken");
    else if (removeJailbreakEnabled)
        jailbreakButtonTitle = EULocalizedString(@"Button_Remove_Jailbreak");
    
    return jailbreakButtonTitle;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.jailbreakBtn.button setTitle:[self jailbreakButtonTitle] forState:UIControlStateNormal];
}

- (void)startJailbreak
{
    EUJailbreaker *jailbreaker = [[EUJailbreaker alloc] init];

    [[EUUIManager sharedInstance] startLogCapture];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        if ([jailbreaker contiguousMappingWorkaroundNeeded]) {
            
            cpu_subtype_t cpuFamily = 0;
            size_t cpuFamilySize = sizeof(cpuFamily);
            sysctlbyname("hw.cpufamily", &cpuFamily, &cpuFamilySize, NULL, 0);
            NSString *workaroundMessage = EULocalizedString(@"Respring_Required_Message");
            if (cpuFamily == CPUFAMILY_ARM_TYPHOON) {
                workaroundMessage = [workaroundMessage stringByAppendingString:[NSString stringWithFormat:@"\n\n%@", EULocalizedString(@"Respring_Required_Notice_A8")]];
            }

            UIAlertController *contiguousMappingWorkaroundAlertController = [UIAlertController alertControllerWithTitle:EULocalizedString(@"Respring_Required") message:workaroundMessage preferredStyle:UIAlertControllerStyleAlert];
            
            UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:EULocalizedString(@"Respring_Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                exit(0);
            }];
            
            UIAlertAction *workaroundAction = [UIAlertAction actionWithTitle:EULocalizedString(@"Apply_Workaround") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [jailbreaker applyContiguousMappingWorkaround];
            }];
            
            [contiguousMappingWorkaroundAlertController addAction:cancelAction];
            [contiguousMappingWorkaroundAlertController addAction:workaroundAction];
            contiguousMappingWorkaroundAlertController.preferredAction = workaroundAction;

            dispatch_async(dispatch_get_main_queue(), ^{
                [self presentViewController:contiguousMappingWorkaroundAlertController animated:YES completion:nil];
            });
            return;
        }

        //We need to get the preconfig mutex to start the jailbreak (self.jailbreakBtn.canStartJailbreak)
        [self.jailbreakBtn lockMutex];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.hideHomeIndicator = YES;
        });

        NSError *error;
        BOOL didRemove = NO;
        BOOL showLogs = YES;
        [jailbreaker runWithError:&error didRemoveJailbreak:&didRemove showLogs:&showLogs];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error && showLogs) {
                [[EUUIManager sharedInstance] sendLog:[NSString stringWithFormat:@"Jailbreak failed with error: %@", error] debug:NO];
                [self.navigationController pushViewController:[[EULogCrashViewController alloc] initWithTitle:[error localizedDescription]] animated:YES];
            }
            else if (error && !showLogs) {
                // Used when there is an error that is explainable in such detail that additional logs are not needed
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:EULocalizedString(@"Log_Error") message:[error localizedDescription] preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *rebootAction = [UIAlertAction actionWithTitle:EULocalizedString(@"Button_Reboot") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    exec_cmd_trusted(JBROOT_PATH("/sbin/reboot"), NULL);
                }];
                [alertController addAction:rebootAction];
                [self presentViewController:alertController animated:YES completion:nil];
            }
            else if (didRemove) {
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:EULocalizedString(@"Removed_Jailbreak_Alert_Title") message:EULocalizedString(@"Removed_Jailbreak_Alert_Message") preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *rebootAction = [UIAlertAction actionWithTitle:EULocalizedString(@"Button_Close") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    exit(0);
                }];
                [alertController addAction:rebootAction];
                [self presentViewController:alertController animated:YES completion:nil];
            }
            else {
                // No errors
                [[EUUIManager sharedInstance] completeJailbreak];
                [self fadeToBlack: ^{
                    [jailbreaker finalize];
                }];
            }
        });
        [self.jailbreakBtn unlockMutex];
    });
}

-(void)setupUpdateAvailable:(BOOL)environmentUpdate
{
    if (self.jailbreakBtn.didExpand)
        return;

    NSString *title = environmentUpdate ? EULocalizedString(@"Button_Update_Environment") : EULocalizedString(@"Button_Update_Available");
    
    NSString *releaseFrom = [[EUUIManager sharedInstance] getLaunchedReleaseTag];
    NSString *releaseTo = [[EUUIManager sharedInstance] getLatestReleaseTag];

    if (environmentUpdate)
    {
        releaseFrom = [[EUEnvironmentManager sharedManager] jailbrokenVersion];
        releaseTo = [[EUUIManager sharedInstance] getLaunchedReleaseTag];
    }

    self.updateButton = [EUActionMenuButton buttonWithAction:[UIAction actionWithTitle:title image:[UIImage systemImageNamed:@"arrow.down.circle" withConfiguration:[EUGlobalAppearance smallIconImageConfiguration]] identifier:@"update-available" handler:^(__kindof UIAction * _Nonnull action) {
        [self.navigationController pushViewController:[[EUUpdateViewController alloc] initFromTag:releaseFrom toTag:releaseTo] animated:YES];
    }] chevron:NO];

    self.updateButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.updateButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.updateButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.updateButton.heightAnchor constraintEqualToConstant:30],
        [self.updateButton.bottomAnchor constraintEqualToAnchor:self.jailbreakBtn.topAnchor constant:[EUGlobalAppearance isHomeButtonDevice] ? -10 : -20]
    ]];

    [self.updateButton setTransform:CGAffineTransformMakeTranslation(0, 25)];
    [self.updateButton setAlpha:0];
    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:2.0  options: UIViewAnimationOptionCurveEaseInOut animations:^{
        [self.updateButton setTransform:CGAffineTransformIdentity];
        [self.updateButton setAlpha:1];
    } completion:nil];
}

-(void)simulateJailbreak
{
    // Let's simulate a "jailbreak" using grand central dispatch

    EUUIManager *uiManager = [EUUIManager sharedInstance];

    static BOOL didFinish = NO; //not thread safe lol
    

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [uiManager completeJailbreak];
        [uiManager sendLog:@"Rebooting Userspace" debug: NO];
        didFinish = YES;
        [self fadeToBlack: ^{

        }];
    });

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [NSThread sleepForTimeInterval:0.2];
        [uiManager sendLog:@"Launching kexploitd" debug: NO];
        [NSThread sleepForTimeInterval:0.5];
        [uiManager sendLog:@"Launching oobPCI" debug: NO];
        [NSThread sleepForTimeInterval:0.15];
        [uiManager sendLog:@"Gaining r/w" debug: NO];
        [NSThread sleepForTimeInterval:0.8];
        [uiManager sendLog:@"Patchfinding" debug: NO];
        NSArray *types = @[@"AMFI", @"PAC", @"KTRR", @"KPP", @"PPL", @"KPF", @"APRR", @"AMCC", @"PAN", @"PXN", @"ASLR", @"OPA"]; //Ever heard of the legendary opa bypass
        while (true)
        {
            [NSThread sleepForTimeInterval:0.6 * rand() / RAND_MAX];
            if (didFinish) break;
            NSString *type = types[arc4random_uniform((uint32_t)types.count)];
            [uiManager sendLog:[NSString stringWithFormat:@"Bypassing %@", type] debug: NO];
        }
    });
}

- (void)fadeToBlack:(void (^)(void))completion
{
    static bool didFade = false;
    if (didFade)
        return;
    didFade = true;
    UIView *mainView = self.parentViewController.view;
    float deviceCornerRadius = [[[UIScreen mainScreen] valueForKey:@"_displayCornerRadius"] floatValue];

    mainView.layer.cornerRadius = deviceCornerRadius;
    mainView.layer.cornerCurve = kCACornerCurveContinuous;
    mainView.layer.masksToBounds = YES;
    
    self.hideStatusBar = YES;

    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:2.0 options: UIViewAnimationOptionCurveEaseInOut animations:^{
        mainView.transform = CGAffineTransformMakeScale(0.9, 0.9);
        mainView.alpha = 0.0;
    } completion:^(BOOL success) {
        completion();
    }];
}

#pragma mark - Action Menu Delegate

- (BOOL)actionMenuShowsChevronForAction:(UIAction *)action
{
    if ([action.identifier isEqualToString:@"settings"] || [action.identifier isEqualToString:@"credits"]) return YES;
    return NO;
}

- (BOOL)actionMenuActionIsEnabled:(UIAction *)action
{
    if ([action.identifier isEqualToString:@"respring"] || [action.identifier isEqualToString:@"reboot-userspace"]) {
        return [[EUEnvironmentManager sharedManager] isJailbroken];
    }
    return YES;
}

#pragma mark - 巨魔E 仙器阁（入口 · 引擎门面路由 · 08 规范仙境文案）

- (NSString *)trolleMenuTitle
{
    BOOL jailbroken = [[EUEnvironmentManager sharedManager] isJailbroken];
    if (jailbroken) return @"巨魔E · 仙器阁 — 御剑秒装";
    if (EUTrollECTPermanentDomain()) return @"巨魔E · 仙器阁 — 仙门大开（永久签印）";
    return @"巨魔E · 仙器阁 — 结界庇护（容器）";
}

// 路由（R32/R35 契约：越狱态零辅助直装；未越狱 CT 域走引擎B；域外显式引擎C，
// 不走 Auto——Auto 在未越狱域外会把引擎B 顶到 DomainUnsupported 硬壁上）
- (EUTrollEInstallMode)trolleRouteMode
{
    if ([[EUEnvironmentManager sharedManager] isJailbroken]) return EUTrollEInstallModeAuto;
    if (EUTrollECTPermanentDomain()) return EUTrollEInstallModeAuto;
    return EUTrollEInstallModeContainerized;
}

- (void)presentTrollEDocumentPicker
{
    NSMutableArray<UTType *> *types = [NSMutableArray new];
    for (NSString *ext in @[@"ipa", @"tipa"]) {
        UTType *t = [UTType typeWithFilenameExtension:ext];
        if (t) [types addObject:t];
    }
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initWithDocumentTypes:types.copy
                                                            inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    if (urls.count == 0) return;
    NSURL *appURL = urls.firstObject;
    BOOL scoped = [appURL startAccessingSecurityScopedResource];

    [[EUUIManager sharedInstance] sendLog:[NSString stringWithFormat:@"巨魔E · 渡劫启程（%@）", appURL.lastPathComponent]
        debug:NO]; // 主标题走 UI 日志窗；工程细节日志由引擎层打印（保持原样）
    EUTrollEInstallMode mode = [self trolleRouteMode];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *err = nil;
        BOOL ok = [[EUTrollE sharedInstance] installApplicationAtURL:appURL
                                                                mode:mode
                                                               error:&err];
        if (scoped) [appURL stopAccessingSecurityScopedResource];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *result = ok
                ? @"✅ 登仙功成（安装完成）"
                : [NSString stringWithFormat:@"❌ 渡劫未成（%ld：%@）",
                    (long)err.code, err.localizedDescription ?: @"无错误详情"];
            UIAlertController *alert = [UIAlertController
                alertControllerWithTitle:@"巨魔E · 仙器阁"
                                 message:result
                          preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"归位"
                                                      style:UIAlertActionStyleDefault
                                                    handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            [[EUUIManager sharedInstance] sendLog:result debug:NO];
        });
    });
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller
{
    [[EUUIManager sharedInstance] sendLog:@"巨魔E · 渡劫暂缓（未选择 IPA）" debug:YES];
}

#pragma mark - Status Bar

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}

- (BOOL)prefersStatusBarHidden
{
    return self.hideStatusBar;
}

- (BOOL)prefersHomeIndicatorAutoHidden
{
    return self.hideHomeIndicator;
}

- (void)setHideStatusBar:(BOOL)hideStatusBar
{
    _hideStatusBar = hideStatusBar;
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)setHideHomeIndicator:(BOOL)hideHomeIndicator
{
    _hideHomeIndicator = hideHomeIndicator;
    [self setNeedsUpdateOfHomeIndicatorAutoHidden];
}

@end
