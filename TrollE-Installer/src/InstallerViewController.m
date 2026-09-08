//
//  InstallerViewController.m
//  TrollE-Installer
//
//  独立安装器最小 UI 实现（免越狱侧载运行）：
//   - 文件选择（UIDocumentPicker，iOS 14+ UTType API，ipa/tipa 双后缀）
//   - 双引擎按钮：CT 域永久安装（引擎B【实验性】）/ 容器模式（引擎C，全版本）
//   - 安装一律后台串行队列执行（漏洞链耗时数秒，禁阻塞主线程——B 线修正）
//   - 已装清单（镜像表）+ 容器条目卸载
//   - 日志窗（EUStandaloneLogger 主线程回调渲染，容量截断）
//   - 签名健康度提示（B26 §3.1：L1 容器非"真永久"）
//   - 域+越狱态检测横幅（CT 域判定+域外降级提示+已越狱指路主 App）
//  抽离：并行搜索员C，2026-09-03。线程模型/装载清单/致谢：B 线修正，2026-09-03。
//  引擎门控（CT 域×越狱态双因子）+viewDidAppear 兜底：C，2026-09-04（用户实测 UI 时序批评对症）。
//  仙境风改版（08 规范 §6-2）：深空底+星尘+极光按钮+毛玻璃日志卡+状态徽标行+成功涟漪。
//  B 线 2026-09-05。
//

#import "InstallerViewController.h"
#import "EUStandaloneInstaller.h"
#import "EUStandaloneLogger.h"
#import "EUStandaloneConfig.h"
#import "EUStandaloneEnvironment.h"
#import "EUFairyStyle.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static dispatch_queue_t EUInstallerQueue(void)
{
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("dev.euphoria.trolle-installer.install", DISPATCH_QUEUE_SERIAL); });
    return q;
}

@interface InstallerViewController () <UIDocumentPickerDelegate, UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UIButton *pickButton;
@property (nonatomic, strong) UIButton *builtinButton;   // 内置巨魔E 本体（用户 14:48 指令）
@property (nonatomic, strong) UIButton *permasignButton;
@property (nonatomic, strong) UIButton *containerButton;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UILabel *domainBanner;
@property (nonatomic, strong) UIView *statusDot;           // §5 状态徽标点（呼吸光晕）
@property (nonatomic, strong) UIView *bannerRow;           // 徽标行容器（点+文案）
@property (nonatomic, strong) UILabel *pickedLabel;
@property (nonatomic, strong) UITableView *installedTable;
@property (nonatomic, strong) NSArray<NSDictionary<NSString *, id> *> *installedEntries;
@property (nonatomic, strong) NSURL *pickedIPA;
@property (nonatomic) BOOL installing;
// 仙境风元素（§4 验收：dealloc/清理面）
@property (nonatomic, strong) CAGradientLayer *deepSpaceLayer;
@property (nonatomic, strong) CAEmitterLayer *stardustLayer;
@property (nonatomic, strong) UIView *logGlassCard;
@property (nonatomic, strong) CAShapeLayer *logGlassBorder;
@end

@implementation InstallerViewController

+ (BOOL)handleOpenURL:(NSURL *)url
{
    // euphoria-trolle://launch?id=<uuid>：引擎 C 容器启动接引（仅提示；
    // 进程内 dlopen 引导运行时=主树 Engine C 待办件，独立版 UI 层留口）
    if ([[url scheme] isEqualToString:EUStandaloneURLScheme] &&
        [[url host] isEqualToString:@"launch"]) {
        [[EUStandaloneLogger sharedLogger] log:@"容器启动请求：%@（运行时引导=主树 Engine C 待办件）",
            [url query]];
    }
    return YES;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"巨魔E 安装器";
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                      target:self
                                                      action:@selector(showCredits:)];
    // 仙境风基调（08 规范 §2）：强制 dark 沉浸
    if (@available(iOS 13.0, *)) self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    // §1 深空三段渐变底（克制律：粒子仅此一层）
    _deepSpaceLayer = [EUFairyStyle deepSpaceBackgroundInView:self.view];
    _stardustLayer = [EUFairyStyle stardustLayerInView:self.view];
    if (_stardustLayer) [self.view.layer insertSublayer:_stardustLayer above:_deepSpaceLayer];

    // §6-2 横幅 → 状态徽标行（§5 四态：dot 呼吸光晕 + 文案；工厂法自带 8pt 约束+光晕）
    _statusDot = [EUFairyStyle statusDotWithColor:[EUFairyStyle colorWarning]];

    _domainBanner = [[UILabel alloc] init];
    _domainBanner.numberOfLines = 0;
    _domainBanner.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _domainBanner.textColor = [EUFairyStyle colorMoonWhite];
    _domainBanner.textAlignment = NSTextAlignmentNatural;
    [_domainBanner setTranslatesAutoresizingMaskIntoConstraints:NO];

    _bannerRow = [[UIView alloc] init];
    [_bannerRow setTranslatesAutoresizingMaskIntoConstraints:NO];
    _bannerRow.backgroundColor = [UIColor colorWithWhite:0.02 alpha:0.45];
    _bannerRow.layer.cornerRadius = 12;
    _bannerRow.layer.borderWidth = 1;
    _bannerRow.layer.borderColor = [[UIColor colorWithWhite:0.92 alpha:0.10] CGColor];
    [_bannerRow addSubview:_statusDot];
    [_bannerRow addSubview:_domainBanner];

    _pickButton = [self buttonWithTitle:@"拾取仙露 · 选择 IPA"
                                  action:@selector(pickIPA:)];
    // 内置巨魔E 本体按钮（bundle 内 Euphoria.tipa 在位时可用；未随包=禁用+说明）
    _builtinButton = [self buttonWithTitle:@"内置巨魔E · 免选直用"
                                     action:@selector(useBuiltinTrollE:)];
    BOOL hasBuiltin = ([[NSBundle mainBundle] pathForResource:@"Euphoria" ofType:@"tipa"] != nil);
    _builtinButton.enabled = hasBuiltin && !_installing;
    if (!hasBuiltin) {
        [_builtinButton setTitle:@"内置巨魔E（未随包——见日志窗指引）" forState:UIControlStateNormal];
    }
    _permasignButton = [self buttonWithTitle:@"登仙 · 永久签印（引擎B·实验性）"
                                       action:@selector(installPermasigned:)];
    _containerButton = [self buttonWithTitle:@"结界 · 容器庇护（引擎C·全版本）"
                                       action:@selector(installContainerized:)];
    // §3-2 极光主按钮 / 次级玻璃按钮
    [EUFairyStyle styleSecondaryButton:_pickButton installing:NO];
    [EUFairyStyle styleSecondaryButton:_builtinButton installing:NO];
    [EUFairyStyle styleAuroraButton:_permasignButton installing:NO];
    [EUFairyStyle styleAuroraButton:_containerButton installing:NO];
    [self refreshEngineAvailability]; // 初始门控：CT 域 × 越狱态（见下方实现注记）

    _pickedLabel = [[UILabel alloc] init];
    _pickedLabel.font = [UIFont systemFontOfSize:12];
    _pickedLabel.textColor = [EUFairyStyle colorMoonWhiteDim];
    _pickedLabel.numberOfLines = 1;
    _pickedLabel.text = @"仙露未拾（未选择载荷）";
    [_pickedLabel setTranslatesAutoresizingMaskIntoConstraints:NO];

    _installedTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _installedTable.dataSource = self;
    _installedTable.delegate = self;
    _installedTable.layer.cornerRadius = 16;
    _installedTable.backgroundColor = [UIColor colorWithWhite:0.02 alpha:0.55];
    _installedTable.separatorColor = [UIColor colorWithWhite:0.92 alpha:0.10]; // 修复：UIColor 属性误赋 CGColorRef（#3/16）
    [_installedTable setTranslatesAutoresizingMaskIntoConstraints:NO];

    // §6-2 日志窗=毛玻璃卡片 + 等宽字体（SF Mono 优先 Menlo 兜底，月白 80%）
    _logGlassCard = [EUFairyStyle glassCard];
    _logView = [[UITextView alloc] init];
    _logView.editable = NO;
    _logView.font = [EUFairyStyle monospaceFontOfSize:13];
    _logView.textColor = [[EUFairyStyle colorMoonWhite] colorWithAlphaComponent:0.8];
    _logView.backgroundColor = [UIColor clearColor];
    [_logView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [_logGlassCard addSubview:_logView];

    [self.view addSubview:_bannerRow];
    for (UIView *v in @[_pickButton, _builtinButton, _pickedLabel, _permasignButton, _containerButton,
                        _installedTable, _logGlassCard]) {
        [self.view addSubview:v];
    }
    [NSLayoutConstraint activateConstraints:@[
        [_bannerRow.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [_bannerRow.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [_bannerRow.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],

        [_statusDot.centerYAnchor constraintEqualToAnchor:_bannerRow.topAnchor constant:14],
        [_statusDot.leadingAnchor constraintEqualToAnchor:_bannerRow.leadingAnchor constant:14],
        [_domainBanner.topAnchor constraintEqualToAnchor:_bannerRow.topAnchor constant:8],
        [_domainBanner.leadingAnchor constraintEqualToAnchor:_statusDot.trailingAnchor constant:10],
        [_domainBanner.trailingAnchor constraintEqualToAnchor:_bannerRow.trailingAnchor constant:-14],
        [_domainBanner.bottomAnchor constraintEqualToAnchor:_bannerRow.bottomAnchor constant:-8],

        [_pickButton.topAnchor constraintEqualToAnchor:_bannerRow.bottomAnchor constant:12],
        [_pickButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [_pickButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],

        [_builtinButton.topAnchor constraintEqualToAnchor:_pickButton.bottomAnchor constant:8],
        [_builtinButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [_builtinButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],

        [_pickedLabel.topAnchor constraintEqualToAnchor:_builtinButton.bottomAnchor constant:6],
        [_pickedLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [_pickedLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],

        [_permasignButton.topAnchor constraintEqualToAnchor:_pickedLabel.bottomAnchor constant:10],
        [_permasignButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [_permasignButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],

        [_containerButton.topAnchor constraintEqualToAnchor:_permasignButton.bottomAnchor constant:12],
        [_containerButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [_containerButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],

        [_installedTable.topAnchor constraintEqualToAnchor:_containerButton.bottomAnchor constant:16],
        [_installedTable.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [_installedTable.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [_installedTable.heightAnchor constraintEqualToConstant:132],

        [_logGlassCard.topAnchor constraintEqualToAnchor:_installedTable.bottomAnchor constant:16],
        [_logGlassCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [_logGlassCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [_logGlassCard.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12],

        [_logView.topAnchor constraintEqualToAnchor:_logGlassCard.topAnchor constant:10],
        [_logView.leadingAnchor constraintEqualToAnchor:_logGlassCard.leadingAnchor constant:12],
        [_logView.trailingAnchor constraintEqualToAnchor:_logGlassCard.trailingAnchor constant:-12],
        [_logView.bottomAnchor constraintEqualToAnchor:_logGlassCard.bottomAnchor constant:-10],
    ]];
    // 卡片描边（需在卡片入树后取 frame——布局在下一 runloop 稳定，viewDidLayoutSubviews 同步）
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_logGlassBorder = [EUFairyStyle attachBorderToView:self->_logGlassCard];
    });

    // 日志接引（解耦点 #1 的 UI 侧渲染；logger 已保证主线程回调）
    __weak __typeof(self) weakSelf = self;
    [EUStandaloneLogger sharedLogger].onLog = ^(NSString *line) {
        __strong __typeof(weakSelf) self = weakSelf; // 修复#16：补 __strong（原推导为 weak，ARC 重声明错+竞态）
        if (!self) return;
        NSString *text = [self->_logView.text stringByAppendingFormat:@"%@\n", line];
        // 容量截断（保留尾部 8000 字符，防长会话 UI 膨胀）
        if (text.length > 8000) text = [text substringFromIndex:text.length - 8000];
        self->_logView.text = text;
        [self->_logView scrollRangeToVisible:NSMakeRange(self->_logView.text.length, 0)];
    };

    [self refreshInstalledList];
    [[EUStandaloneLogger sharedLogger] log:@"TrollE-Installer 独立安装器就绪（仙境风）"];
    if ([[NSBundle mainBundle] pathForResource:@"Euphoria" ofType:@"tipa"]) {
        [[EUStandaloneLogger sharedLogger] log:@"✅ 检测到内置巨魔E 本体（Euphoria.tipa 已随包）——点\"内置巨魔E\"免选直用"];
    } else {
        [[EUStandaloneLogger sharedLogger] log:@"ℹ️ 本包未内嵌巨魔E 本体（Mac 构建时主树 make trolle-payload 后再 make 安装器即自动内嵌；当前请用\"选择 IPA\""];
    }
    [[EUStandaloneLogger sharedLogger] log:@"⚠️ 引擎B 路线=实验性（entitlement 门禁 spike 未实机裁决）"];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    // 深空/星尘/描边随布局同步（§4 验收：图层 frame 不漂移）
    _deepSpaceLayer.frame = self.view.bounds;
    if (_stardustLayer) _stardustLayer.frame = self.view.bounds;
    if (_logGlassBorder) {
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:_logGlassCard.bounds
                                                        cornerRadius:24];
        _logGlassBorder.frame = _logGlassCard.bounds;
        _logGlassBorder.path = path.CGPath;
    }
}

- (void)dealloc
{
    // §4 验收：CALayer 无泄漏（emitter 主动熄灭兜底；渐变/卡片层随 view 树释放，
    // onLog block 持 weak self 无环——logger 单例生命周期=进程级，无回收需求）
    [_stardustLayer removeFromSuperlayer];
}

- (UIButton *)buttonWithTitle:(NSString *)title action:(SEL)action
{
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    [b.titleLabel setFont:[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]];
    [b.layer setCornerRadius:8];
    [b setBackgroundColor:[UIColor tertiarySystemBackgroundColor]];
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [b setTranslatesAutoresizingMaskIntoConstraints:NO];
    [b.heightAnchor constraintEqualToConstant:44].active = YES;
    return b;
}

- (void)setInstalling:(BOOL)installing
{
    _installing = installing;
    [self refreshEngineAvailability]; // 复用同一门控（含 installing 态；§5 dot 转紫光脉冲）
    _containerButton.enabled = !installing;
    _pickButton.enabled = !installing;
    _builtinButton.enabled = !installing && ([[NSBundle mainBundle] pathForResource:@"Euphoria" ofType:@"tipa"] != nil);
    _installedTable.allowsSelection = !installing;
    // §6-2 安装中：按钮进度流光（styleAuroraButton 幂等，重入安全）
    [EUFairyStyle styleAuroraButton:_permasignButton installing:installing];
    [EUFairyStyle styleAuroraButton:_containerButton installing:installing];
}

#pragma mark - 引擎门控（CT 域 × 越狱态——UI 时序修复，2026-09-04 C）

/// 用户实测批评"该越狱前出现的按钮被藏到越狱后"的对症设计：
///   - 引擎B = 免越狱专用（漏洞会话+CT custom 法）。已越狱即禁用+指路主 App（引擎A 秒装），
///     避免在越狱机上误导用户跑无意义的漏洞链。
///   - 引擎C = 全场景兜底，恒可用（容器模式对越狱机也是合法降级形态）。
///   - viewDidAppear 兜底刷新：respring/前台回切后越狱态可能已翻转。
- (void)refreshEngineAvailability
{
    BOOL inCT = [[EUStandaloneInstaller sharedInstaller] deviceInCoreTrustDomain];
    BOOL jailbroken = [[EUStandaloneEnvironment sharedEnvironment] isJailbroken];
    _permasignButton.enabled = !_installing && inCT && !jailbroken;

    // §5 四态徽标（视觉服务状态语义：dot 颜色/光晕/文案同源翻转）
    // 文案=登仙之途叙事（用户 00:33:21），状态语义硬约束：档位/引擎/降级信息一字不失
    UIColor *dotColor = nil;
    NSString *banner = nil;
    if (_installing) {
        dotColor = [EUFairyStyle colorPulse];
        banner = @"● 渡劫中：借漏洞之力 → 化 root 之身 → 落凡尘之盘（进度见日志窗）";
    } else if (jailbroken) {
        dotColor = [EUFairyStyle colorAurora];
        banner = @"🔧 已御剑而行：越狱态信任缓存秒装（引擎A）走 Euphoria 主 App——此处面向免越狱渡劫，引擎B 已封";
    } else if (inCT) {
        dotColor = [EUFairyStyle colorSuccess];
        banner = @"✅ 仙门大开：CT 永久域，登仙签印可达（引擎B·实验性）";
    } else {
        dotColor = [EUFairyStyle colorWarning];
        banner = @"⚠️ 仙门已闭：此域 CT 已修复，永久签不可得——结界庇护仍可（容器模式·全版本；16.7b/RC/17.0 → PC 渡引档）";
    }
    _domainBanner.text = banner;
    _domainBanner.textColor = _installing ? [EUFairyStyle colorPulse] : dotColor;
    _statusDot.backgroundColor = dotColor;
    _statusDot.layer.shadowColor = dotColor.CGColor;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self refreshEngineAvailability]; // 越狱态兜底刷新（respring 后冷启为常态，此处覆盖前台回切）
}

#pragma mark - 已装清单（镜像表）

- (void)refreshInstalledList
{
    _installedEntries = [[EUStandaloneInstaller sharedInstaller] installedApplications];
    [_installedTable reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _installedEntries.count ?: 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cellID = @"trolle.entry";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
    // 仙境暗色单元（§2：月白主文/辅文 60%；引擎 B/C 徽标色）→ tblView 背景为深色透卡
    cell.backgroundColor = [UIColor clearColor];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.textColor = [EUFairyStyle colorMoonWhite];
    cell.detailTextLabel.textColor = [EUFairyStyle colorMoonWhiteDim];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:11];
    if (_installedEntries.count == 0) {
        cell.textLabel.attributedText = nil; // 修复#15：清复用残留的 attributedText（否则覆盖 text 显示旧条目）
        cell.textLabel.text = @"（仙籍为空）";
        cell.detailTextLabel.text = @"安装后条目登册于此；越狱时主树渡劫合并升级";
        return cell;
    }
    NSDictionary *entry = _installedEntries[indexPath.row];
    NSString *engine = entry[@"engine"];
    cell.textLabel.text = [NSString stringWithFormat:@"%@  [%@]",
                            entry[@"bundleID"], engine];
    // §5 引擎徽标语义色：B=青绿（永久·实验性）/ C=琥珀（容器）/ A=极光
    UIColor *engineColor = [engine isEqualToString:@"B"] ? [EUFairyStyle colorSuccess]
                          : [engine isEqualToString:@"C"] ? [EUFairyStyle colorWarning]
                                                          : [EUFairyStyle colorAurora];
    NSAttributedString *title = [[NSAttributedString alloc]
        initWithString:cell.textLabel.text
            attributes:@{NSForegroundColorAttributeName : engineColor}];
    cell.textLabel.attributedText = title;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  %@",
                                entry[@"role"] ?: @"-", entry[@"path"]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= _installedEntries.count) return;
    NSDictionary *entry = _installedEntries[indexPath.row];
    NSString *engine = entry[@"engine"];
    NSString *bundleID = entry[@"bundleID"];
    if ([engine isEqualToString:@"C"]) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"卸载容器条目？"
                             message:bundleID
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"卸载" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            NSError *err = nil;
            BOOL ok = [[EUStandaloneInstaller sharedInstaller] uninstallContainerizedWithBundleID:bundleID error:&err];
            [[EUStandaloneLogger sharedLogger] log:@"%@容器卸载（%@）",
                ok ? @"✅ " : @"❌ ", err.localizedDescription ?: @"无错误详情"];
            [self refreshInstalledList];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } else {
        [[EUStandaloneLogger sharedLogger] log:@"引擎B/本体条目：桌面长按删除即可（无需本口）"];
    }
}

#pragma mark - 致谢（命名契约：mg13-14 与所用大模型）
// 2026-09-08 用户指令：致谢更新为当前主力大模型（GLM-5.3，盟友 kimik3 同源）
// ——原 GLM-5.3 为 2026-08 前期主力，已退役。

- (void)showCredits:(id)sender
{
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Euphoria / TrollE (巨魔E)"
                         message:@"Special Thanks:\n  mg13-14\n\nAI Assistance:\n  清言 AgentMore（并行搜索员A/B/C、搜索规划师、报告汇总员）\n  GLM-5.3 大模型（Z.ai·当前主力）"
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 文件选择（iOS 14+ UTType API，ipa/tipa 双后缀）

- (void)pickIPA:(id)sender
{
    NSMutableArray<UTType *> *types = [NSMutableArray new];
    for (NSString *ext in @[@"ipa", @"tipa"]) {
        UTType *t = [UTType typeWithFilenameExtension:ext];
        if (t) [types addObject:t];
    }
    if (@available(iOS 14.0, *)) {
        UIDocumentPickerViewController *picker =
            [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    }
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    if (!urls.count) return;
    _pickedIPA = urls.firstObject;
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_pickedLabel.text = [NSString stringWithFormat:@"载荷：%@",
                                   self->_pickedIPA.lastPathComponent];
    });
    [[EUStandaloneLogger sharedLogger] log:@"已选载荷：%@", _pickedIPA.lastPathComponent];
}

#pragma mark - 内置巨魔E 本体（用户 2026-09-06 14:48 指令"安装器里要内置巨魔E"）

- (void)useBuiltinTrollE:(id)sender
{
    NSString *path = [[NSBundle mainBundle] pathForResource:@"Euphoria" ofType:@"tipa"];
    if (!path) {
        [[EUStandaloneLogger sharedLogger] log:@"⚠️ 无内置巨魔E 本体（payload 未随包）——请用上方按钮选择文件"];
        return;
    }
    _pickedIPA = [NSURL fileURLWithPath:path];
    _pickedLabel.text = @"载荷：内置巨魔E 本体（已就位，免选文件）";
    [[EUStandaloneLogger sharedLogger] log:@"已挂内置巨魔E 本体（bundle 内 Euphoria.tipa，免选文件）"];
}

#pragma mark - 引擎触发（后台串行队列，绝不阻塞主线程——B 线修正）

- (void)installPermasigned:(id)sender
{
    [self runInstall:^(NSError **err) {
        return [[EUStandaloneInstaller sharedInstaller] installPermasignedAppAtURL:self->_pickedIPA error:err];
    }];
}

- (void)installContainerized:(id)sender
{
    [self runInstall:^(NSError **err) {
        return [[EUStandaloneInstaller sharedInstaller] installApplicationContainerizedAtURL:self->_pickedIPA error:err];
    }];
}

- (void)runInstall:(BOOL (^)(NSError **))block
{
    if (_installing) {
        [[EUStandaloneLogger sharedLogger] log:@"⚠️ 已有安装任务在跑（串行队列）"];
        return;
    }
    if (!_pickedIPA) {
        [[EUStandaloneLogger sharedLogger] log:@"⚠️ 请先选择 IPA"];
        return;
    }
    self.installing = YES;
    __weak __typeof(self) weakSelf = self;
    dispatch_async(EUInstallerQueue(), ^{
        __strong __typeof(weakSelf) self = weakSelf; // 修复#16：补 __strong（原推导为 weak，ARC 重声明错+竞态）
        if (!self) return;
        NSError *err = nil;
        BOOL ok = block(&err);
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong __typeof(weakSelf) self = weakSelf; // 修复#16：补 __strong（原推导为 weak，ARC 重声明错+竞态）
            if (!self) return;
            self.installing = NO;
            [self refreshInstalledList];
            [[EUStandaloneLogger sharedLogger] log:@"%@（%@）",
                ok ? @"✅ 安装流程完成" : @"❌ 安装流程失败",
                err.localizedDescription ?: @"无错误详情"];
            // §4-3 成功涟漪（视觉确认：月白圆环从徽标行扩散淡出）
            if (ok) [EUFairyStyle rippleFromView:self->_bannerRow];
        });
    });
}

@end
