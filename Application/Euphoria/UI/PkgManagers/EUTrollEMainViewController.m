//
//  EUTrollEMainViewController.m
//  Euphoria
//
//  巨魔E 主页——TrollStore 原版骨架 + 底部悬浮小横板（巨魔R 式三 tab）+ 仙境皮肤
//
//  结构：
//    · 内容区（三页切换）：
//        ① 应用页：已装应用列表（重放表：名称/bundleID/引擎档/路径）+ 右上"+"选
//           IPA 安装（EUTrollE installApplicationAtURL Auto 模式=越狱态秒装/
//           免越狱 CT 域引擎B）+ 条目左滑卸载
//        ② 插件注入页：目标 App 选择（重放表条目）+ dylib 导入池（文档选择器
//           多选 .dylib）+ 注入动作（EUTrollE injectDylibAtURL——引擎由
//           A/B 线 ChOma 链落地，本页先行完整交互流）
//        ③ 设置页：CT 域状态（C24 矩阵实时显示）+ respring/uicache 持久化工具
//           + 巨魔E 版本/引擎矩阵说明
//    · 底部小横板（悬浮圆角胶囊 dock，EUFairyStyle 皮肤）：三段 tab 切换
//
//  域口径（B 线情报包 §四，如实）：
//    · 应用页全域可用（引擎 A/B/C 自动分档）
//    · 注入页：14.0~17.0 原版域免越狱可用；17.0.1+ 越狱态（引擎A 会话内）——
//      页顶域状态徽标如实标注
//  落码：并行搜索员C，2026-09-07。
//

#import "EUTrollEMainViewController.h"
#import "EUTrollE.h"
#import "EUEnvironmentManager.h"
#import "EUUIManager.h"
#import "EUGlobalAppearance.h"
#import <MobileCoreServices/MobileCoreServices.h> // kUTTypeData（dylib 导入 picker）

extern BOOL EUTrollECTPermanentDomain(void); // EUMainViewController.m（C24 矩阵 UI 面，⑬修复版）

@interface EUTrollEMainViewController () <UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate>
@property (nonatomic, strong) NSArray<NSDictionary<NSString *, id> *> *entries;   // 重放表
@property (nonatomic, strong) UITableView *tableView;                             // ①/② 共用列表（按 tab 重载）
@property (nonatomic, strong) UIView *dock;                                       // 底部小横板（巨魔R 式）
@property (nonatomic, strong) UIButton *appsTabButton;
@property (nonatomic, strong) UIButton *injectTabButton;
@property (nonatomic, strong) UIButton *settingsTabButton;
@property (nonatomic, strong) UILabel *domainBadge;                               // 页顶域状态徽标（⑬：17.0.1+ 域外如实）
@property (nonatomic, strong) UILabel *emptyHintLabel;
@property (nonatomic) NSInteger currentTab;                                       // 0=应用 1=插件注入 2=设置
@property (nonatomic, strong) NSMutableArray<NSString *> *dylibPool;              // 注入页：导入的 .dylib 池
@property (nonatomic, strong) NSString *injectTargetBundleID;                     // 注入页：目标 App
@end

@implementation EUTrollEMainViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [EUFairyStyle backgroundGradientInView:self.view] ?: [UIColor colorWithRed:0.07 green:0.09 blue:0.16 alpha:1.0];
    self.dylibPool = [NSMutableArray array];
    [self buildTableView];
    [self buildDock];
    [self buildDomainBadge];
    [self reloadEntries];
}

#pragma mark - 布局

- (void)buildTableView
{
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.rowHeight = 68;
    _tableView.contentInset = UIEdgeInsetsMake(52, 0, 120, 0);
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_tableView];

    _emptyHintLabel = [[UILabel alloc] init];
    _emptyHintLabel.textColor = [EUFairyStyle colorAurora];
    _emptyHintLabel.textAlignment = NSTextAlignmentCenter;
    _emptyHintLabel.numberOfLines = 0;
    _emptyHintLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    _emptyHintLabel.text = @"仙籍为空——右上 \"+\" 选择 IPA 开始渡劫\n（越狱态=信任缓存秒装；CT 域免越狱=永久签印；域外=结界庇护容器）";
    _emptyHintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_emptyHintLabel];

    UIBarButtonItem *addBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(presentInstallPicker)];
    self.navigationItem.rightBarButtonItem = addBtn;

    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_emptyHintLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_emptyHintLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
}

- (void)buildDomainBadge
{
    _domainBadge = [[UILabel alloc] init];
    _domainBadge.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];
    _domainBadge.textAlignment = NSTextAlignmentCenter;
    _domainBadge.layer.cornerRadius = 10;
    _domainBadge.layer.masksToBounds = YES;
    _domainBadge.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_domainBadge];
    [NSLayoutConstraint activateConstraints:@[
        [_domainBadge.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [_domainBadge.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_domainBadge.heightAnchor constraintEqualToConstant:22],
    ]];
    [self refreshDomainBadge];
}

- (void)refreshDomainBadge
{
    NSOperatingSystemVersion v = [NSProcessInfo processInfo].operatingSystemVersion;
    BOOL jb = [[EUEnvironmentManager sharedManager] isJailbroken];
    BOOL ctDomain = EUTrollECTPermanentDomain();
    NSString *text = [NSString stringWithFormat:@"iOS %ld.%ld.%ld  %@  CT 域：%@",
        (long)v.majorVersion, (long)v.minorVersion, (long)v.patchVersion,
        jb ? @"已越狱" : @"未越狱", ctDomain ? @"内（永久签印）" : @"外（会话/容器档）"];
    _domainBadge.text = [NSString stringWithFormat:@" %@ ", text];
    UIColor *bg = ctDomain ? [EUFairyStyle colorSuccess] : [EUFairyStyle colorWarning];
    _domainBadge.textColor = [UIColor blackColor];
    _domainBadge.backgroundColor = [bg colorWithAlphaComponent:0.85];
}

#pragma mark - 底部小横板（巨魔R 式悬浮胶囊 dock）

- (void)buildDock
{
    _dock = [[UIView alloc] init];
    _dock.layer.cornerRadius = 24;
    _dock.layer.masksToBounds = YES;
    _dock.backgroundColor = [[UIColor colorWithWhite:1.0 alpha:0.12] colorWithAlphaComponent:0.9];
    _dock.layer.borderColor = [EUFairyStyle colorAurora].CGColor;
    _dock.layer.borderWidth = 1.0;
    _dock.layer.shadowColor = [EUFairyStyle colorAurora].CGColor;
    _dock.layer.shadowOpacity = 0.35;
    _dock.layer.shadowRadius = 12;
    _dock.layer.shadowOffset = CGSizeMake(0, 4);
    _dock.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_dock];

    _appsTabButton = [self dockButtonWithTitle:@"应用" icon:@"sparkles" tag:0];
    _injectTabButton = [self dockButtonWithTitle:@"插件注入" icon:@"syringe" tag:1];
    _settingsTabButton = [self dockButtonWithTitle:@"设置" icon:@"gearshape" tag:2];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[_appsTabButton, _injectTabButton, _settingsTabButton]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.spacing = 4;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [_dock addSubview:row];

    [NSLayoutConstraint activateConstraints:@[
        [_dock.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [_dock.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [_dock.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10],
        [_dock.heightAnchor constraintEqualToConstant:52],
        [row.topAnchor constraintEqualToAnchor:_dock.topAnchor constant:6],
        [row.bottomAnchor constraintEqualToAnchor:_dock.bottomAnchor constant:-6],
        [row.leadingAnchor constraintEqualToAnchor:_dock.leadingAnchor constant:8],
        [row.trailingAnchor constraintEqualToAnchor:_dock.trailingAnchor constant:-8],
    ]];
    [self refreshDockHighlight];
}

- (UIButton *)dockButtonWithTitle:(NSString *)title icon:(NSString *)icon tag:(NSInteger)tag
{
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.tag = tag;
    b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    UIImage *img = [UIImage systemImageNamed:icon];
    if (img) [b setImage:img forState:UIControlStateNormal];
    [b setTitle:title forState:UIControlStateNormal];
    [b addTarget:self action:@selector(switchTab:) forControlEvents:UIControlEventTouchUpInside];
    b.layer.cornerRadius = 18;
    return b;
}

- (void)refreshDockHighlight
{
    NSArray *buttons = @[_appsTabButton, _injectTabButton, _settingsTabButton];
    [buttons enumerateObjectsUsingBlock:^(UIButton *b, NSUInteger i, BOOL *stop) {
        BOOL on = (i == (NSUInteger)_currentTab);
        b.backgroundColor = on ? [[EUFairyStyle colorAurora] colorWithAlphaComponent:0.9] : [UIColor clearColor];
        b.tintColor = on ? [UIColor blackColor] : [EUFairyStyle colorAurora];
        [b setTitleColor:(on ? [UIColor blackColor] : [EUFairyStyle colorAurora]) forState:UIControlStateNormal];
    }];
}

- (void)switchTab:(UIButton *)sender
{
    _currentTab = sender.tag;
    [self refreshDockHighlight];
    [self reloadEntries];
    // "+"分态：应用页=选 IPA 安装；注入页=导入 .dylib（多选）；设置页无
    if (_currentTab == 0) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(presentInstallPicker)];
    } else if (_currentTab == 1) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(presentDylibPicker)];
    } else {
        self.navigationItem.rightBarButtonItem = nil;
    }
}

- (void)presentDylibPicker
{
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initWithDocumentTypes:@[(NSString *)kUTTypeData] inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    picker.allowsMultipleSelection = YES; // 插件池批量导入
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - 数据层（重放表 = 唯一事实源）

- (void)reloadEntries
{
    _entries = [[EUTrollE sharedInstance] installedApplications] ?: @[];
    [self refreshDomainBadge];
    [_tableView reloadData];

    // 空态与导航项按 tab 分态
    if (_currentTab == 0) {
        _emptyHintLabel.text = @"仙籍为空——右上 \"+\" 选择 IPA 开始渡劫\n（越狱态=信任缓存秒装；CT 域免越狱=永久签印；域外=结界庇护容器）";
        _emptyHintLabel.hidden = _entries.count > 0;
    } else if (_currentTab == 1) {
        _emptyHintLabel.text = @"插件注入：先在「应用」页装好目标 App\n再回到此页选目标→导入 .dylib→点注入";
        _emptyHintLabel.hidden = _entries.count > 0 || _dylibPool.count > 0;
    } else {
        _emptyHintLabel.hidden = YES;
    }
}

#pragma mark - ① 应用页：安装/卸载

- (void)presentInstallPicker
{
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initWithDocumentTypes:@[@"com.apple.itunes-ipa", @"public.zip-archive"]
                       inMode:UIDocumentPickerModeImport]; // deprecated 类型常量经 Entitlements 兼容
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    if (_currentTab == 1) {
        // 插件注入页的 dylib 导入池
        for (NSURL *u in urls) {
            if ([u.pathExtension.lowercaseString isEqualToString:@"dylib"]) {
                [_dylibPool addObject:u.lastPathComponent];
                [[EUUIManager sharedInstance] sendLog:[NSString stringWithFormat:@"巨魔E · 插件池新增（%@）", u.lastPathComponent] debug:NO];
            }
        }
        [self reloadEntries];
        return;
    }
    // 应用页：安装流（Auto 模式：越狱→引擎A 秒装；未越狱 CT 域→引擎B；域外→引擎C）
    NSURL *appURL = urls.firstObject;
    BOOL scoped = [appURL startAccessingSecurityScopedResource];
    [[EUUIManager sharedInstance] sendLog:[NSString stringWithFormat:@"巨魔E · 渡劫启程（%@）", appURL.lastPathComponent] debug:NO];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *err = nil;
        BOOL ok = [[EUTrollE sharedInstance] installApplicationAtURL:appURL error:&err];
        if (scoped) [appURL stopAccessingSecurityScopedResource];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[EUUIManager sharedInstance] sendLog:ok
                ? @"巨魔E · 登仙功成（重放表已登记）"
                : [NSString stringWithFormat:@"巨魔E · 渡劫未成（%@）", err.localizedDescription]
                debug:NO];
            [self reloadEntries];
        });
    });
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller
{
    [[EUUIManager sharedInstance] sendLog:@"巨魔E · 渡劫暂缓（未选择文件）" debug:YES];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle != UITableViewCellEditingStyleDelete || _currentTab != 0) return;
    NSDictionary *e = _entries[indexPath.row];
    NSString *bid = e[@"bundleID"] ?: e[@"path"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *err = nil;
        BOOL ok = [[EUTrollE sharedInstance] uninstallApplicationWithBundleID:bid error:&err];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[EUUIManager sharedInstance] sendLog:ok
                ? @"巨魔E · 归位（.app 与重放表条目已清）"
                : [NSString stringWithFormat:@"巨魔E · 归位未成（%@）", err.localizedDescription]
                debug:NO];
            [self reloadEntries];
        });
    });
}

#pragma mark - UITableView（①/② 两态）

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (_currentTab == 2) return 4; // 设置页固定行
    if (_currentTab == 1) return _dylibPool.count + 2; // 统一模型：行0=目标行+插件 count 行+尾行（执行注入）
    return _entries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"trolle-cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"trolle-cell"];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [EUFairyStyle colorAurora];
        cell.detailTextLabel.textColor = [EUFairyStyle colorWarning];
        cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        cell.detailTextLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
        cell.textLabel.attributedText = nil; // 清复用残留（#15 同病预防）
    }

    if (_currentTab == 0) {
        NSDictionary *e = _entries[indexPath.row];
        NSString *engine = e[@"engine"] ?: @"A";
        NSString *engineName = [engine isEqualToString:@"B"] ? @"永久签印"
            : [engine isEqualToString:@"C"] ? @"结界庇护" : @"信任缓存";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.textLabel.text = [NSString stringWithFormat:@"%@", e[@"bundleID"] ?: e[@"path"] ?: @"—"];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@  %@",
            engineName, e[@"installedAt"] ? [NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSince1970:[e[@"installedAt"] doubleValue]]
                dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle] : @"—",
            e[@"path"] ?: @""];
    } else if (_currentTab == 1) {
        cell.accessoryType = UITableViewCellAccessoryNone;
        if (indexPath.row == 0) {
            // 行 0 = 目标行（无目标=引导选择；有目标=显示+可换）
            cell.textLabel.text = _injectTargetBundleID
                ? [NSString stringWithFormat:@"目标：%@（点换）", _injectTargetBundleID]
                : @"选择目标 App（点我）";
            cell.detailTextLabel.text = @"从重放表（巨魔E 已装应用）中选注入目标";
        } else if (indexPath.row == _dylibPool.count + 1) {
            // 尾行 = 执行注入
            cell.textLabel.text = [NSString stringWithFormat:@"⚡ 执行注入（目标 %@ · %tu 个插件）", _injectTargetBundleID ?: @"未选", _dylibPool.count];
            cell.detailTextLabel.text = @"ChOma LC_LOAD_DYLIB 引擎接线中（A/B 线落地即激活）——UI 与选择流已完整";
        } else {
            // 中段 = 插件池（行 1..count）
            NSInteger di = indexPath.row - 1;
            cell.textLabel.text = [NSString stringWithFormat:@"🧩 %@", _dylibPool[di]];
            cell.detailTextLabel.text = @"已入插件池（点右上 \"+\" 继续导入 .dylib）";
        }
    } else {
        // ③ 设置页（固定 4 行）
        NSArray *titles = @[
            @"Respring（重启 SpringBoard）",
            @"uicache（刷新应用图标缓存）",
            @"巨魔E 引擎矩阵说明",
            @"关于巨魔E",
        ];
        NSArray *details = @[
            @"持久化工具（注入/装 App 后桌面刷新）",
            @"图标缓存重建（安装后图标不显示时用）",
            @"A=信任缓存秒装（越狱态）· B=永久签印（CT 域免越狱）· C=结界庇护（容器）",
            [NSString stringWithFormat:@"Euphoria 巨魔E · 0.9.2 · 重放表：%@",
                [EUTrollE registryPath]],
        ];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.textLabel.text = titles[indexPath.row];
        cell.detailTextLabel.text = details[indexPath.row];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (_currentTab == 1) {
        // 注入页交互：行0=选/换目标（弹出重放表选择）；尾行=执行注入（引擎桩如实提示）
        if (indexPath.row == 0) {
            [self presentTargetPicker];
            return;
        }
        if (indexPath.row == _dylibPool.count + 1) {
            if (_dylibPool.count == 0 || _injectTargetBundleID == nil) {
                [[EUUIManager sharedInstance] sendLog:@"巨魔E · 注入前请先选目标 App 并导入 .dylib" debug:NO];
                return;
            }
            [[EUUIManager sharedInstance] sendLog:@"巨魔E · 注入引擎接线中（ChOma LC_LOAD_DYLIB 链，A/B 线落地即激活）——选择流已锁定，届时一键生效" debug:NO];
        }
    } else if (_currentTab == 2) {
        if (indexPath.row == 0) {
            [[EUUIManager sharedInstance] sendLog:@"巨魔E · Respring（重启 SpringBoard）" debug:NO];
            [[EUEnvironmentManager sharedManager] rebootUserspace];
        } else if (indexPath.row == 1) {
            [[EUUIManager sharedInstance] sendLog:@"巨魔E · uicache 刷新图标缓存" debug:NO];
            // uicache 经 EUEnvironmentManager 的 spawn 通道（引擎侧已有）
            [[EUEnvironmentManager sharedManager] runAsRoot:^{
                system("/var/jb/usr/bin/uicache -p /var/jb/Applications 2>/dev/null");
            }];
        }
    }
}

- (void)presentTargetPicker
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选择注入目标"
        message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *e in _entries) {
        NSString *bid = e[@"bundleID"] ?: [e[@"path"] lastPathComponent];
        [alert addAction:[UIAlertAction actionWithTitle:bid style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *a) { self->_injectTargetBundleID = bid; [self reloadEntries]; }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
