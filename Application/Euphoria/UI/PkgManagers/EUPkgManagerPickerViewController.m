//
//  EUPkgManagerPickerViewController.m
//  Euphoria
//
//  Created by tomt000 on 11/02/2024.
//

#import "EUPkgManagerPickerViewController.h"
#import "EUPkgManagerPickerView.h"
#import "EUEnvironmentManager.h"
#import "EUUIManager.h"
#import <libjailbreak/libjailbreak.h>
#import <spawn.h>
#import <sys/stat.h> // R14 v2 固定源区：lstat st_flags & UF_IMMUTABLE 锁定态

// ═══════════════════════════════════════════════════════════════════════════
// EUPMPackagesViewController —— EPM（自研包管理器·T18 契约 v1）最小内嵌页
// 用户 2026-09-05 19:35:28 点名"每次选项都没有你们的自研包管理器"的入口落码。
//
// v1 范围（诚实边界）：已装包清单浏览（dpkg -l ii 行解析）+ 刷新。
// 搜索/安装/升级/源管理=下批（契约 07-EUPM包管理器接口契约_T18-0.md 的
// apt-cache/apt-get 全量面），本页不放占位假按钮。
// 通道：posix_spawn 管道捕获 stdout（exec_cmd 系无输出变体）+ runAsRoot
// 临时提权块（get_root→块→drop_root，同线程 uid 往返恢复）。
// 落码：并行搜索员C，2026-09-05。
//
// 固定源区 UI（ADR-R14 §6.3-b：用户"删不掉"的完整体验由 EPM 层兑现）——B 落码：
//   · 锁定态着色（🔒 青绿=chflags 防呆在位 / 琥珀=待补锁）+ 空态防呆占位（未越狱
//     /源未写入两分支指引，不留空白区）+ 段头暗色沉浸；
//   · 点击固定源→真态语义弹窗（SSOT/重放自愈/root 不可误删），删除交互恒不存在；
//   · 下拉刷新（UIRefreshControl，iOS 9 兜底 addSubview 路径）。
//   数据位增量：sources dict 增 isLocked(BOOL) 供着色，C 的读取/解析逻辑零改动。
//   2026-09-06，B。
// ═══════════════════════════════════════════════════════════════════════════

static NSString *EUPMCaptureCommandOutput(NSString *binary, NSArray<NSString *> *args)
{
    int outfd[2];
    if (pipe(outfd) != 0) return nil;

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, outfd[1], STDOUT_FILENO);
    posix_spawn_file_actions_addclose(&actions, outfd[0]);
    posix_spawn_file_actions_addclose(&actions, outfd[1]);

    // argv 组装（posix_spawn 语义：argv[0]=程序名惯例）
    const char **argv = calloc(args.count + 2, sizeof(char *));
    argv[0] = binary.fileSystemRepresentation;
    for (NSUInteger i = 0; i < args.count; i++) {
        argv[i + 1] = args[i].fileSystemRepresentation;
    }
    // argv 末位 NULL 由 calloc 零值保证

    pid_t pid = -1;
    extern char **environ;
    int r = posix_spawn(&pid, binary.fileSystemRepresentation, &actions, NULL,
                        (char *const *)argv, environ);
    close(outfd[1]);
    free(argv);
    if (r != 0) {
        posix_spawn_file_actions_destroy(&actions);
        close(outfd[0]);
        return nil;
    }

    NSMutableData *data = [NSMutableData data];
    char buf[4096];
    ssize_t n;
    while ((n = read(outfd[0], buf, sizeof(buf))) > 0) {
        [data appendBytes:buf length:(NSUInteger)n];
    }
    close(outfd[0]);
    waitpid(pid, NULL, 0);
    posix_spawn_file_actions_destroy(&actions);
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

@interface EUPMPackagesViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary<NSString *, NSString *> *> *entries;
@property (nonatomic, strong) NSArray<NSDictionary<NSString *, NSString *> *> *fixedSources; // R14 v2 文件层 SSOT
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic) BOOL loading;
@end

@implementation EUPMPackagesViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"EPM · 仙市（自研）";
    self.view.backgroundColor = [UIColor blackColor];
    // B 固定源区 UI（R14 v2 §6.3-b 兑现层）：强制暗色沉浸 + 下拉刷新
    if (@available(iOS 13.0, *)) self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                      target:self
                                                      action:@selector(reloadList)];

    _statusLabel = [[UILabel alloc] init];
    _statusLabel.textColor = [UIColor whiteColor];
    _statusLabel.font = [UIFont systemFontOfSize:14];
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.numberOfLines = 0;
    _statusLabel.text = @"EPM v1：已装清单浏览（自研通道）\n安装/升级/搜索=下批";
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_statusLabel];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.rowHeight = 52;
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_tableView];

    UIRefreshControl *refresh = [[UIRefreshControl alloc] init];
    [refresh addTarget:self action:@selector(refreshPulled:)
             forControlEvents:UIControlEventValueChanged];
    if (@available(iOS 10.0, *)) {
        _tableView.refreshControl = refresh;
    } else {
        [_tableView addSubview:refresh]; // iOS 9 兜底
    }

    [NSLayoutConstraint activateConstraints:@[
        [_statusLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [_tableView.topAnchor constraintEqualToAnchor:_statusLabel.bottomAnchor constant:8],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [self reloadList];
}

- (void)refreshPulled:(UIRefreshControl *)sender
{
    [sender endRefreshing];
    [self reloadList];
}

- (void)reloadList
{
    if (_loading) return;
    _loading = YES;
    _statusLabel.text = @"正在读取 dpkg 数据库…";

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // 越狱态判定（EPM 通道=bootstrap 的 dpkg；未越狱时诚实告知）
        if (![[EUEnvironmentManager sharedManager] isJailbroken]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_loading = NO;
                self->_statusLabel.text = @"EPM 需越狱后使用（dpkg 通道未就绪）";
                self->_entries = @[];
                [self->_tableView reloadData];
            });
            return;
        }

        __block NSString *output = nil;
        __block NSMutableArray<NSDictionary<NSString *, NSString *> *> *sources = [NSMutableArray array];
        [[EUEnvironmentManager sharedManager] runAsRoot:^{
            output = EUPMCaptureCommandOutput(@(JBROOT_PATH("/bin/dpkg"))
                                              ?: @"/var/jb/bin/dpkg",
                                              @[@("-l")]);

            // R14 v2（ADR §6.3-b）：文件层=SSOT——EPM 固定源区直读
            // /var/jb/etc/apt/sources.list.d/*.list（每次刷新即文件层真态；
            // Sileo db 层删除不影响这里显示——"删不掉"体验的兑现层）
            NSString *sourcesDir = @(JBROOT_PATH("/etc/apt/sources.list.d"))
                                    ?: @"/var/jb/etc/apt/sources.list.d";
            NSArray *files = [[NSFileManager defaultManager]
                contentsOfDirectoryAtPath:sourcesDir error:nil];
            for (NSString *f in [files sortedArrayUsingSelector:@selector(compare:)]) {
                if (![f hasSuffix:@".list"]) continue;
                NSString *p = [sourcesDir stringByAppendingPathComponent:f];
                NSString *content = [NSString stringWithContentsOfFile:p
                    encoding:NSUTF8StringEncoding error:nil];
                // 锁定态：lstat st_flags & UF_IMMUTABLE（chflags 层2 防呆是否在位）
                struct stat st;
                BOOL locked = (lstat(p.fileSystemRepresentation, &st) == 0)
                              && (st.st_flags & UF_IMMUTABLE);
                NSString *url = @"";
                for (NSString *line in [content componentsSeparatedByString:@"\n"]) {
                    NSString *t = [line stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceCharacterSet]];
                    if ([t hasPrefix:@"deb "]) { url = t; break; }
                }
                [sources addObject:@{
                    @"file":     f,
                    @"url":      url.length ? url : @"（空）",
                    @"locked":   locked ? @"🔒 已锁定" : @"（未锁：下次越狱补锁）",
                    @"isLocked": @(locked), // B 固定源区 UI：锁定态着色/详情交互数据位
                }];
            }
        }];

        // dpkg -l 输出解析：ii 行（包名/版本/描述）
        NSMutableArray<NSDictionary<NSString *, NSString *> *> *parsed = [NSMutableArray array];
        if (output.length > 0) {
            for (NSString *line in [output componentsSeparatedByString:@"\n"]) {
                if (![line hasPrefix:@"ii "]) continue;
                NSArray *cols = [line componentsSeparatedByString:@"  "]; // dpkg 定宽列以多空格分隔
                NSMutableArray *nonEmpty = [NSMutableArray array];
                for (NSString *c in cols) {
                    NSString *t = [c stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceCharacterSet]];
                    if (t.length > 0) [nonEmpty addObject:t];
                }
                if (nonEmpty.count < 3) continue;
                [parsed addObject:@{
                    @"name":    nonEmpty[1],
                    @"version": nonEmpty[2],
                    @"desc":    nonEmpty.count > 3 ? nonEmpty[3] : @"",
                }];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self->_loading = NO;
            self->_entries = parsed.copy;
            self->_fixedSources = sources.copy;
            self->_statusLabel.text = output
                ? [NSString stringWithFormat:@"已装 %tu 包 · 固定源 %tu 条（文件层 SSOT）",
                    parsed.count, sources.count]
                : @"dpkg 读取失败（通道异常，见日志）";
            [self->_tableView reloadData];
        });
    });
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2; // 0=固定源区（R14 v2 文件层 SSOT） 1=已装包清单
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) {
        // B 固定源区 UI：空态防呆占位（源未写入时给出路，不留空白区）
        return _fixedSources.count > 0 ? _fixedSources.count : 1;
    }
    return _entries.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return (section == 0)
        ? @"固定源（文件层 · 不可删 · 越狱重放自愈）"
        : @"已装包（dpkg）";
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forHeaderInSection:(NSInteger)section
{
    // B 固定源区 UI：暗色沉浸下的段头着色（正文语义不动）
    if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
        UITableViewHeaderFooterView *hv = (UITableViewHeaderFooterView *)view;
        hv.textLabel.textColor = [UIColor whiteColor];
        hv.contentView.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1.0];
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"epm-cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:@"epm-cell"];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor lightGrayColor];
    }
    if (indexPath.section == 0) {
        // B 固定源区 UI 空态：未越狱/源未预置时的防呆行（指引而非空白）
        if (_fixedSources.count == 0) {
            BOOL jb = [[EUEnvironmentManager sharedManager] isJailbroken];
            cell.textLabel.text = @"（仙籍未载）源文件层为空";
            cell.textLabel.textColor = [UIColor systemOrangeColor];
            cell.detailTextLabel.text = jb
                ? @"重跑一次越狱即写入预置源（chariz/havoc/bigboss 等 + EU 官方源）"
                : @"先完成越狱（EPM 的 dpkg 通道随 bootstrap 就绪）";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }
        // 固定源区：锁定态着色（🔒 青绿=防呆锁在位 / 琥珀=待补锁）+ URL 副文本
        NSDictionary *s = _fixedSources[indexPath.row];
        BOOL isLocked = [s[@"isLocked"] boolValue];
        cell.textLabel.text = [NSString stringWithFormat:@"%@ %@", s[@"locked"], s[@"file"]];
        cell.textLabel.textColor = isLocked
            ? [UIColor systemGreenColor] : [UIColor systemOrangeColor];
        cell.detailTextLabel.text = s[@"url"];
        // 点击=固定源语义说明（"删不掉"完整体验的兑现入口）；删除交互恒不存在
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else {
        NSDictionary *e = _entries[indexPath.row];
        cell.textLabel.text = e[@"name"];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  %@",
            e[@"version"], e[@"desc"] ?: @""];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    return cell;
}

// B 固定源区 UI（ADR-R14 §6.3-b：用户"删不掉"的完整体验由 EPM 层兑现）：
// 点击固定源→真态语义弹窗。工程事实口径，不做删除入口。
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 0 || indexPath.row >= _fixedSources.count) return;
    NSDictionary *s = _fixedSources[indexPath.row];
    BOOL isLocked = [s[@"isLocked"] boolValue];
    NSString *msg = isLocked
        ? @"此源为固定预置（文件层真态）：\n· Sileo/Zebra 里删除只删它自己的视图，本页显示永远恢复\n· chflags 防呆锁在位——root 亦无法误删\n· 每次越狱幂等重放，文件层自愈"
        : @"此源为固定预置（文件层真态）：\n· 暂未上锁（下次越狱重放自动补锁）\n· Sileo/Zebra 里删除不影响文件层，越狱后即恢复";
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"固定源 · %@", s[@"file"]]
                         message:msg
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知晓" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

// ═══════════════════════════════ 原有 Picker VC ═══════════════════════════════

@interface EUPkgManagerPickerViewController ()

@end

@implementation EUPkgManagerPickerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    EUPkgManagerPickerView *picker = [[EUPkgManagerPickerView alloc] initWithCallback:^(BOOL success) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [[EUEnvironmentManager sharedManager] reinstallPackageManagers];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.navigationController popViewControllerAnimated:YES];
            });
        });
    }];
    picker.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:picker];
    [NSLayoutConstraint activateConstraints:@[
        [picker.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [picker.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [picker.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [picker.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}


@end
