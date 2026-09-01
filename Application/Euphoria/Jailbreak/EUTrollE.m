//
//  EUTrollE.m
//  Euphoria
//
//  Created by 并行搜索员B on 27.08.2026.
//

#import "EUTrollE.h"
#import "EUEnvironmentManager.h"
#import "EUUIManager.h"
#import "EUBootstrapper.h"
#import "EUExploitManager.h"
#import <libjailbreak/util.h>
#import <libjailbreak/kernel.h>      // proc_ucred（B25-1 ② 17+ 直接内核写入）
#import <libjailbreak/primitives.h>  // kread32/kwrite32/kread_ptr
#import <libjailbreak/trustcache.h>
#import <libjailbreak/info.h>
#import <choma/Fat.h>
#import <choma/MachO.h>
#import <choma/CSBlob.h>
#import <dlfcn.h>
#import <sys/sysctl.h>
#import <string.h>
#import <unistd.h>
#import <limits.h>                   // NGROUPS_MAX（rootify groups 缓冲）
#import <objc/message.h>             // objc_msgSend（B25-1 ③ 私有类运行时调用）
#import <objc/runtime.h>             // NSClassFromString/sel_registerName
#import <mach-o/loader.h>            // MH_MAGIC_64（MachO 探测，custom 法权限修正）
#import <mach-o/fat.h>               // FAT_MAGIC（FAT 探测）

NSString *const EUTrollEErrorDomain = @"EUTrollEErrorDomain";

#define EUTrolleLog(fmt, ...) [[EUUIManager sharedInstance] sendLog:[NSString stringWithFormat:fmt, ##__VA_ARGS__] debug:NO]

#pragma mark - ChOma C 桥接（CDHash 计算）

static BOOL EUTrollEComputeCDHash(NSString *binaryPath, uint8_t cdhash[CS_CDHASH_LEN])
{
    Fat *fat = fat_init_from_path(binaryPath.fileSystemRepresentation);
    if (!fat) return NO;

    MachO *slice = fat_find_slice(fat, CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64E);
    if (!slice) {
        for (uint32_t i = 0; i < fat->slicesCount; i++) {
            if (fat->slices[i]->machHeader.cputype == CPU_TYPE_ARM64) { slice = fat->slices[i]; break; }
        }
    }
    if (!slice) { fat_free(fat); return NO; }

    CS_SuperBlob *superblob = macho_read_code_signature(slice);
    if (!superblob) { fat_free(fat); return NO; } // 未签名（需 adhoc/fakesigned）

    CS_DecodedSuperBlob *decoded = csd_superblob_decode(superblob);
    if (!decoded) { fat_free(fat); return NO; }

    int cdhashType = 0;
    int r = csd_superblob_calculate_best_cdhash(decoded, cdhash, &cdhashType);
    csd_superblob_free(decoded);
    fat_free(fat);
    return (r == 0);
}

#pragma mark - 实现

@implementation EUTrollE

+ (NSString *)registryPath
{
    // 双模（B25 契约修订）：越狱态=主表（/var/jb/var/db/euphoria/trolle.plist）；
    // 免越狱态（引擎B 首装/引擎C 全程）=沙盒镜像表（Documents/EUTrollE/registry.plist）。
    // 两条路径条目结构一致；下次越狱时 migrateSandboxRegistryIfNeeded 搬运合并（幂等）。
    if ([[EUEnvironmentManager sharedManager] isJailbroken] ||
        [[NSFileManager defaultManager] fileExistsAtPath:JBROOT_PATH(@"/var/db/euphoria")]) {
        return JBROOT_PATH(@"/var/db/euphoria/trolle.plist");
    }
    return [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/EUTrollE"]
            stringByAppendingPathComponent:@"registry.plist"];
}

+ (NSString *)sandboxRegistryPath
{
    return [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/EUTrollE"]
            stringByAppendingPathComponent:@"registry.plist"];
}

+ (instancetype)sharedInstance
{
    static EUTrollE *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[EUTrollE alloc] init]; });
    return shared;
}

- (NSArray<NSDictionary<NSString *, id> *> *)installedApplications
{
    NSString *path = [EUTrollE registryPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return @[];
    NSArray *entries = [NSDictionary dictionaryWithContentsOfFile:path][@"entries"];
    return [entries isKindOfClass:[NSArray class]] ? entries : @[];
}

- (void)saveEntries:(NSArray<NSDictionary<NSString *, id> *> *)entries
{
    // 双模写入（B25 契约修订）：引擎B 会话期间进程已是 root（ucred 已改）→ 直接落盘
    // 免越狱非 root（引擎C）→ 沙盒路径本就可写，直接落盘；越狱态 → 传统 runAsRoot 通道。
    void (^write)(void) = ^{
        NSString *dir = [[EUTrollE registryPath] stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        [@{@"entries" : entries ?: @[]} writeToFile:[EUTrollE registryPath] atomically:YES];
    };
    if (getuid() == 0 || ![[EUEnvironmentManager sharedManager] isJailbroken]) {
        write();
    } else {
        [[EUEnvironmentManager sharedManager] runAsRoot:write];
    }
}

#pragma mark 安装（双模式门面，C23）

- (BOOL)installApplicationAtURL:(NSURL *)appURL error:(NSError **)error
{
    return [self installApplicationAtURL:appURL mode:EUTrollEInstallModeAuto error:error];
}

- (BOOL)installApplicationAtURL:(NSURL *)appURL mode:(EUTrollEInstallMode)mode error:(NSError **)error
{
    NSError * (^fail)(EUTrollEErrorCode, NSString *) = ^NSError *(EUTrollEErrorCode code, NSString *msg) {
        return [NSError errorWithDomain:EUTrollEErrorDomain code:code
                               userInfo:@{NSLocalizedDescriptionKey : msg}];
    };

    BOOL jailbroken = [[EUEnvironmentManager sharedManager] isJailbroken];

    // 模式路由（C23 双引擎）
    EUTrollEInstallMode effective = mode;
    if (effective == EUTrollEInstallModeAuto) {
        effective = jailbroken ? EUTrollEInstallModeJailbroken : EUTrollEInstallModeJailbreakFree;
    }

    if (effective == EUTrollEInstallModeJailbreakFree) {
        // 引擎B（免越狱一次性会话：kfd+dmaFail 装本体+Persistence Helper）：
        // 契约见 EUTrollE.h / research/B25，语义=C23/C24；实现体如下（C 侧接入）。
        return [self installApplicationJailbreakFreeAtURL:appURL error:error];
    }

    if (effective == EUTrollEInstallModeContainerized) {
        // 引擎C（容器模式 L1 基线，B26）：无漏洞全版本域，宿主证书代签+JIT-Less。
        // C 已实现安装侧（暂存+登记，见下）；进程内启动器（LC 式 dlopen 引导）与
        // 主屏图标（快捷指令+URL scheme，LiveContainer 实证机制、无 GPL 传染）
        // 属 UI/运行时层，由 B 侧接入；登记重放表保留 L1→L3 升级路径。
        return [self installApplicationContainerizedAtURL:appURL error:error];
    }

    // ===== 引擎A：越狱态信任缓存秒装（已实现） =====

    // 前置：越狱态（信任缓存 XPC 通道）
    if (!jailbroken) {
        if (error) *error = fail(EUTrollEErrorCodeNotJailbroken, @"巨魔E 该模式需要越狱状态（免越狱安装为 Engine B，V0.9.2 目标）");
        return NO;
    }

    if (!appURL || ![[NSFileManager defaultManager] fileExistsAtPath:appURL.path]) {
        if (error) *error = fail(EUTrollEErrorCodeInvalidInput, @"路径不存在");
        return NO;
    }

    NSString *stagingDir = nil;
    NSString *appBundlePath = nil;

    // ① 解包（.ipa → 暂存目录；.app 直接用）
    if ([appURL.pathExtension.caseInsensitiveCompare:@"ipa"] == NSOrderedSame) {
        NSString *unzipPath = JBROOT_PATH(@"/usr/bin/unzip");
        if (![[NSFileManager defaultManager] isExecutableFileAtPath:unzipPath]) {
            if (error) *error = fail(EUTrollEErrorCodeUnzipMissing, @"缺少 unzip（请先在包管理器中安装 unzip 包，Procursus 源提供）");
            return NO;
        }
        stagingDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"trolle_%@",
                       [[NSUUID UUID] UUIDString]]];
        [[NSFileManager defaultManager] createDirectoryAtPath:stagingDir withIntermediateDirectories:YES attributes:nil error:nil];
        EUTrolleLog(@"巨魔E：解包 IPA…");
        int r = exec_cmd_trusted(unzipPath.fileSystemRepresentation, "-q", "-o",
                                 appURL.fileSystemRepresentation, "-d", stagingDir.fileSystemRepresentation, NULL);
        if (r != 0) {
            if (error) *error = fail(EUTrollEErrorCodeUnpackFailed, [NSString stringWithFormat:@"unzip 返回 %d", r]);
            return NO;
        }
        // 定位 Payload/*.app
        NSString *payloadDir = [stagingDir stringByAppendingPathComponent:@"Payload"];
        NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:payloadDir error:nil];
        for (NSString *item in contents) {
            if ([item hasSuffix:@".app"]) { appBundlePath = [payloadDir stringByAppendingPathComponent:item]; break; }
        }
        if (!appBundlePath && contents.count > 0) {
            // 容错：IPA 根目录直接就是 .app（少见布局）
            for (NSString *item in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:stagingDir error:nil]) {
                if ([item hasSuffix:@".app"]) { appBundlePath = [stagingDir stringByAppendingPathComponent:item]; break; }
            }
        }
    }
    else if ([appURL.pathExtension.caseInsensitiveCompare:@"app"] == NSOrderedSame) {
        appBundlePath = appURL.path;
    }

    if (!appBundlePath) {
        if (error) *error = fail(EUTrollEErrorCodeNoPayload, @"IPA 内未找到 Payload/*.app");
        return NO;
    }

    // ② 主二进制 + CDHash
    NSString *infoPlistPath = [appBundlePath stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
    NSString *bundleID = info[@"CFBundleIdentifier"] ?: appBundlePath.lastPathComponent;
    NSString *execName = info[@"CFBundleExecutable"];
    if (!execName.length) {
        if (error) *error = fail(EUTrollEErrorCodeInvalidInput, @"Info.plist 缺少 CFBundleExecutable");
        return NO;
    }
    NSString *execPath = [appBundlePath stringByAppendingPathComponent:execName];

    uint8_t cdhash[CS_CDHASH_LEN] = {0};
    EUTrolleLog(@"巨魔E：计算 CDHash…");
    if (!EUTrollEComputeCDHash(execPath, cdhash)) {
        if (error) *error = fail(EUTrollEErrorCodeUnsignedBinary,
            @"主二进制无代码签名或无法计算 CDHash（巨魔E 需要 adhoc/伪签 IPA）");
        return NO;
    }
    NSMutableString *cdhashHex = [NSMutableString stringWithCapacity:CS_CDHASH_LEN * 2];
    for (int i = 0; i < CS_CDHASH_LEN; i++) [cdhashHex appendFormat:@"%02x", cdhash[i]];

    // ③ 注入运行时信任缓存（与系统二进制同权 → 永久免签、任意 entitlements 生效）
    EUTrolleLog(@"巨魔E：注入信任缓存（%@）…", cdhashHex);
    if (jb_trustcache_add_cdhashes((cdhash_t *)cdhash, 1) != 0) {
        if (error) *error = fail(EUTrollEErrorCodeTrustCacheFailed, @"信任缓存注入失败（jbserver 通道异常）");
        return NO;
    }

    // ④ 拷入 /var/jb/Applications（root）
    __block BOOL copied = NO;
    NSString *destPath = JBROOT_PATH(([NSString stringWithFormat:@"/Applications/%@", appBundlePath.lastPathComponent]));
    [[EUEnvironmentManager sharedManager] runAsRoot:^{
        [[NSFileManager defaultManager] removeItemAtPath:destPath error:nil];
        copied = [[NSFileManager defaultManager] copyItemAtPath:appBundlePath toPath:destPath error:nil];
    }];
    if (!copied) {
        if (error) *error = fail(EUTrollEErrorCodeCopyFailed, @"拷贝到 /var/jb/Applications 失败");
        return NO;
    }

    // ⑤ uicache 刷新图标
    int r = exec_cmd_trusted(JBROOT_PATH("/usr/bin/uicache").fileSystemRepresentation,
                             "-p", destPath.fileSystemRepresentation, NULL);
    if (r != 0) {
        EUTrolleLog(@"巨魔E：uicache 返回 %d（图标可能需注销后出现）", r);
    }

    // ⑥ 重放表登记
    NSMutableArray *entries = [[self installedApplications] mutableCopy];
    [entries filterUsingPredicate:[NSPredicate predicateWithFormat:@"bundleID != %@", bundleID]];
    [entries addObject:@{
        @"bundleID" : bundleID,
        @"path" : destPath,
        @"cdhash" : cdhashHex,
        @"installedAt" : @([[NSDate date] timeIntervalSince1970]),
    }];
    [self saveEntries:entries];

    // 清理暂存
    if (stagingDir) [[NSFileManager defaultManager] removeItemAtPath:stagingDir error:nil];

    EUTrolleLog(@"巨魔E：安装完成（%@）", bundleID);
    return YES;
}

#pragma mark 卸载

- (BOOL)uninstallApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
    if (![[EUEnvironmentManager sharedManager] isJailbroken]) {
        if (error) *error = [NSError errorWithDomain:EUTrollEErrorDomain code:EUTrollEErrorCodeNotJailbroken
                                            userInfo:@{NSLocalizedDescriptionKey : @"需要越狱状态"}];
        return NO;
    }
    NSDictionary *target = nil;
    for (NSDictionary *entry in [self installedApplications]) {
        if ([entry[@"bundleID"] isEqualToString:bundleID]) { target = entry; break; }
    }
    if (!target) {
        if (error) *error = [NSError errorWithDomain:EUTrollEErrorDomain code:EUTrollEErrorCodeInvalidInput
                                            userInfo:@{NSLocalizedDescriptionKey : @"未在巨魔E 重放表中找到该应用"}];
        return NO;
    }

    __block BOOL removed = NO;
    [[EUEnvironmentManager sharedManager] runAsRoot:^{
        removed = [[NSFileManager defaultManager] removeItemAtPath:target[@"path"] error:nil];
    }];
    // TC 条目随下次重启自然失效；本次越狱期间残留无害（仅"已删二进制的哈希"，不可被利用来运行新代码）

    NSMutableArray *entries = [[self installedApplications] mutableCopy];
    [entries filterUsingPredicate:[NSPredicate predicateWithFormat:@"bundleID != %@", bundleID]];
    [self saveEntries:entries];

    exec_cmd_trusted(JBROOT_PATH("/usr/bin/uicache").fileSystemRepresentation, "-u", [target[@"path"] stringByDeletingLastPathComponent].fileSystemRepresentation, NULL);
    return removed;
}

#pragma mark 引擎B：免越狱一次性会话（C23/C24 语义，B25 契约实现）

/// 免越狱永久域判定（C24 修正版矩阵，用户 11:47:32 build 级勘误后）：
///   CT 全史域 = 14.0b2–16.7RC 连续带（16.6.2/16.7b1–b6/16.7RC 全支持）+ 17.0 全系（b1–5/GA）
///   死区 = 16.7.x GA 系列（16.7~16.7.10；RC 20H18 除外）→ 会话档（DarkSword）兜底
///   17.0.1+ = CT 已修，免越狱永久档不可达（无公开第三 CT bug；TrollStore 2.1.1@2026-04 佐证）
- (BOOL)eutrolle_deviceInCoreTrustDomain
{
    NSOperatingSystemVersion v = [NSProcessInfo processInfo].operatingSystemVersion;
    if (v.majorVersion > 17) return NO;
    if (v.majorVersion == 17) return (v.minorVersion == 0); // 17.0 全系
    if (v.minorVersion == 7) { // 16.7.x：仅 RC（20H18）在 CT 域
        char osversion[32] = {0};
        size_t len = sizeof(osversion) - 1;
        sysctlbyname("kern.osversion", osversion, &len, NULL, 0);
        return (strcmp(osversion, "20H18") == 0);
    }
    return YES; // ≤16.6.x 连续带
}

/// 免越狱解包： jailed 环境无 /var/jb/unzip → 用系统自带 libarchive
/// （/usr/lib/libarchive.2.dylib，iOS 14–17 均随系统提供；进程此时已 root，无权限问题）
// libarchive 运行时自备声明（dlopen 动态解析，不依赖构建期头文件）
struct archive;
struct archive_entry;
#ifndef ARCHIVE_OK
#define ARCHIVE_OK 0
#endif
#ifndef ARCHIVE_EXTRACT_TIME
#define ARCHIVE_EXTRACT_TIME (1 << 2)
#endif
#ifndef AE_IFDIR
#define AE_IFDIR 0040000 // S_IFDIR
#endif
#ifndef AE_IFLNK
#define AE_IFLNK 0120000 // S_IFLNK
#endif

static BOOL EUTrollEExtractZipWithLibarchive(NSString *zipPath, NSString *destDir)
{
    void *handle = dlopen("/usr/lib/libarchive.2.dylib", RTLD_NOW);
    if (!handle) return NO;

    struct archive *(*a_read_new)(void) = dlsym(handle, "archive_read_new");
    int (*a_read_support_format_zip)(struct archive *) = dlsym(handle, "archive_read_support_format_zip");
    int (*a_read_support_filter_all)(struct archive *) = dlsym(handle, "archive_read_support_filter_all");
    int (*a_read_open_filename)(struct archive *, const char *, size_t) = dlsym(handle, "archive_read_open_filename");
    int (*a_read_next_header)(struct archive *, struct archive_entry **) = dlsym(handle, "archive_read_next_header");
    const char *(*a_entry_pathname)(struct archive_entry *) = dlsym(handle, "archive_entry_pathname");
    void (*a_entry_set_pathname)(struct archive_entry *, const char *) = dlsym(handle, "archive_entry_set_pathname");
    int (*a_entry_filetype)(struct archive_entry *) = dlsym(handle, "archive_entry_filetype");
    int (*a_read_data_block)(struct archive *, const void **, size_t *, int64_t *) = dlsym(handle, "archive_read_data_block");
    struct archive *(*a_write_disk_new)(void) = dlsym(handle, "archive_write_disk_new");
    int (*a_write_disk_set_options)(struct archive *, int) = dlsym(handle, "archive_write_disk_set_options");
    int (*a_write_header)(struct archive *, struct archive_entry *) = dlsym(handle, "archive_write_header");
    int (*a_write_data_block)(struct archive *, const void *, size_t, int64_t) = dlsym(handle, "archive_write_data_block");
    int (*a_write_finish_entry)(struct archive *) = dlsym(handle, "archive_write_finish_entry");
    int (*a_read_free)(struct archive *) = dlsym(handle, "archive_read_free");
    int (*a_write_free)(struct archive *) = dlsym(handle, "archive_write_free");

    if (!a_read_new || !a_read_support_format_zip || !a_read_open_filename || !a_read_next_header ||
        !a_entry_set_pathname || !a_write_disk_new || !a_write_header || !a_read_free) {
        return NO;
    }

    struct archive *a = a_read_new();
    struct archive *ext = a_write_disk_new();
    if (!a || !ext) return NO;
    if (a_read_support_filter_all) a_read_support_filter_all(a);
    a_read_support_format_zip(a);
    // 安全选项级联（B 评审缺陷②修复，15:20）：SECURE_SYMLINKS=拒绝经符号链接/硬链接逃逸
    // 写穿解包目录（默认不开启——必须显式加）；SECURE_NODOTDOT/NOABSOLUTEPATHS 与
    // 手工消毒（绝对路径/../..）双保险。NOABSOLUTEPATHS 为 libarchive 3.4+ 新位，
    // 老系统库不识别→级联降级重试（set_options 对未知位返回非 OK）。
    if (a_write_disk_set_options) {
        int optSets[] = {
            ARCHIVE_EXTRACT_TIME | 0x0100 /*SECURE_SYMLINKS*/ | 0x0200 /*SECURE_NODOTDOT*/ | 0x10000 /*SECURE_NOABSOLUTEPATHS*/,
            ARCHIVE_EXTRACT_TIME | 0x0100 | 0x0200,
            ARCHIVE_EXTRACT_TIME,
        };
        BOOL optsOK = NO;
        for (size_t i = 0; i < sizeof(optSets) / sizeof(optSets[0]) && !optsOK; i++) {
            if (a_write_disk_set_options(ext, optSets[i]) == 0 /*ARCHIVE_OK*/) optsOK = YES;
        }
        if (!optsOK) { a_read_free(a); a_write_free(ext); return NO; }
    }

    BOOL ok = NO;
    if (a_read_open_filename(a, zipPath.fileSystemRepresentation, 10240) == ARCHIVE_OK) {
        ok = YES;
        struct archive_entry *entry = NULL;
        while (a_read_next_header(a, &entry) == ARCHIVE_OK) {
            // 消毒：拒绝绝对路径/.. 穿越（C 侧复核一遍，纵深防御）
            const char *pname = a_entry_pathname(entry);
            if (!pname || pname[0] == '/' || strstr(pname, "..")) { ok = NO; break; }
            // B 评审修正（15:15）：拒绝符号链接条目——恶意压缩包可先放内嵌 symlink
            // 再经其写穿 destDir 之外（sanitize 挡不住合法路径名经链接逃逸）；
            // 版本无关的硬拒绝（不依赖 libarchive SECURE_* 选项位在 2.x 的可用性）
            if (a_entry_filetype && (a_entry_filetype(entry) & AE_IFLNK) == AE_IFLNK) { ok = NO; break; }
            // 重写落盘路径 → destDir/<原路径>（libarchive 按条目路径写盘）
            NSString *full = [destDir stringByAppendingPathComponent:@(pname)];
            if (a_entry_filetype && a_entry_filetype(entry) == AE_IFDIR) {
                [[NSFileManager defaultManager] createDirectoryAtPath:full withIntermediateDirectories:YES attributes:nil error:nil];
                a_entry_set_pathname(entry, full.fileSystemRepresentation);
            } else {
                a_entry_set_pathname(entry, full.fileSystemRepresentation);
            }
            if (a_write_header(ext, entry) == ARCHIVE_OK) {
                const void *buff = NULL; size_t size = 0; int64_t offset = 0;
                while (a_read_data_block(a, &buff, &size, &offset) == ARCHIVE_OK) {
                    if (a_write_data_block(ext, buff, size, offset) != ARCHIVE_OK) { ok = NO; break; }
                }
                a_write_finish_entry(ext);
            } else { ok = NO; break; }
        }
    }
    a_read_free(a); a_write_free(ext);
    return ok;
}

/// CT 永久签名安装（B25-1 ③ 重做，2026-08-31：TrollStore custom 法 in-process 移植）。
///
/// 推翻原 MobileInstallationInstall 路线的根因（B25-1 评审，源码级对照 opa334/TrollStore@master）：
/// "TrollHelper 同构"不成立——TrollHelper 的 installd 通道背后是 TrollStore 本体经 CT
/// 漏洞获得的 entitlements（RootHelper 带全套通行证）；Engine B 进程只有 KRW root 没有
/// 这些通行证，XPC 门槛可能拒收。TrollStore 真实安装链（RootHelper/main.m custom 分支）：
///   MCMAppContainer 直建 Bundle 容器 → 文件系统直拷 .app → 写 `_TrollStore` 标记 →
///   fixPermissionsOfAppBundle 两遍法 → LSApplicationWorkspace 注册字典直注册。
/// 全程不经 installd XPC，语义=同步拷贝+注册，无异步回调竞态面（原 30s 信号量等待删除）。
///
/// ⚠️ 剩余已知风险（B25-1 ➕ 新发现，v1.2 风险簿首位）：lsd/containermanagerd 侧
/// entitlement 门禁——公开生态零先例（TrollStore=有 entitlement；越狱=有 AMFI 补丁；
/// 我们两条都不占）。三候选 spike（csflags 平台位单点写入 / 内核 entitlements 指针
/// 移植 / 绕 XPC 直写）由 B 线排期实机裁决；本实现的失败路径保持清晰可观测，
/// 供 spike 定位。

// MARK: MachO 文件探测（TrollStore main.m isMachoFile 同构；决定 0755 提权位）
static BOOL EUTrollEIsMachoFile(NSString *filePath)
{
    FILE *file = fopen(filePath.fileSystemRepresentation, "r");
    if (!file) return NO;
    uint32_t magic = 0;
    size_t rd = fread(&magic, sizeof(uint32_t), 1, file);
    fclose(file);
    if (rd != 1) return NO;
    return magic == FAT_MAGIC || magic == FAT_CIGAM ||
           magic == MH_MAGIC_64 || magic == MH_CIGAM_64;
}

// MARK: 权限修正两遍法（TrollStore main.m:178 fixPermissionsOfAppBundle 同构）
// 第一遍全量 chown(33,33)+chmod 0644；第二遍目录与 MachO 可执行提权 0755
static void EUTrollEFixPermissionsOfAppBundle(NSString *appBundlePath)
{
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager]
        enumeratorAtURL:[NSURL fileURLWithPath:appBundlePath]
        includingPropertiesForKeys:nil options:0 errorHandler:nil];
    for (NSURL *fileURL in enumerator) {
        chown(fileURL.path.fileSystemRepresentation, 33, 33);
        chmod(fileURL.path.fileSystemRepresentation, 0644);
    }
    enumerator = [[NSFileManager defaultManager]
        enumeratorAtURL:[NSURL fileURLWithPath:appBundlePath]
        includingPropertiesForKeys:nil options:0 errorHandler:nil];
    for (NSURL *fileURL in enumerator) {
        BOOL isDir = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:fileURL.path isDirectory:&isDir];
        if (isDir || EUTrollEIsMachoFile(fileURL.path)) {
            chmod(fileURL.path.fileSystemRepresentation, 0755);
        }
    }
}

// MARK: 注册（TrollStore uicache.m registerPath 同构移植）
// 经 LSApplicationWorkspace 注册字典将 .app 登记进 LaunchServices。
// 与 TrollStore 差异（裁剪，非门禁必需项）：Entitlements/TeamIdentifier/
// GroupContainers/_LSBundlePlugins 需 ldid dump 或多容器构建，Engine B 首装
// 本体场景从简（containerization 从简=默认容器化，container ID=bundleID——
// TrollStore 对无 entitlements 应用走同一默认）。
static BOOL EUTrollERegisterAppPath(NSString *appPath, BOOL forceSystem)
{
    if (!appPath) return NO;

    NSDictionary *appInfoPlist = [NSDictionary dictionaryWithContentsOfFile:
        [appPath stringByAppendingPathComponent:@"Info.plist"]];
    NSString *appBundleID = appInfoPlist[@"CFBundleIdentifier"];
    if (![appBundleID isKindOfClass:[NSString class]] || !appBundleID.length) return NO;

    // data 容器（MCMAppDataContainer，TrollStore 同构；类经 dlopen 后 NSClassFromString 解析）
    NSString *containerPath = nil;
    void *mcm = dlopen("/System/Library/PrivateFrameworks/MobileContainerManager.framework/MobileContainerManager", RTLD_NOW);
    if (mcm) {
        Class dataContainerClass = NSClassFromString(@"MCMAppDataContainer");
        if (dataContainerClass) {
            id container = ((id (*)(id, SEL, NSString *, BOOL, BOOL *, NSError **))objc_msgSend)(
                dataContainerClass,
                sel_registerName("containerWithIdentifier:createIfNecessary:existed:error:"),
                appBundleID, YES, NULL, NULL);
            if (container) {
                id containerURL = ((id (*)(id, SEL))objc_msgSend)(container, sel_registerName("url"));
                containerPath = [containerURL path];
            }
        }
    }

    // LSApplicationWorkspace（dyld cache 内私有类；dlopen 触发映像加载后 NSClassFromString）
    void *lsfw = dlopen("/System/Library/PrivateFrameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_NOW);
    if (!lsfw) lsfw = dlopen("/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_NOW);
    Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!wsClass) return NO;
    id workspace = ((id (*)(id, SEL))objc_msgSend)(wsClass, sel_registerName("defaultWorkspace"));
    if (!workspace) return NO;

    // 注册字典（TrollStore uicache.m 键集逐一校准：SignatureVersion=@132352、
    // SignerIdentity="Apple iPhone OS Application Signing" 等——CT 漏洞签名的
    // 伪 Apple 平台签形态，lsd 据此按系统级签发处理）
    BOOL registerAsUser = [appPath hasPrefix:@"/var/containers"] && !forceSystem;
    NSMutableDictionary *dictToRegister = [NSMutableDictionary dictionary];
    dictToRegister[@"ApplicationType"] = registerAsUser ? @"User" : @"System";
    dictToRegister[@"CFBundleIdentifier"] = appBundleID;
    dictToRegister[@"CodeInfoIdentifier"] = appBundleID;
    dictToRegister[@"CompatibilityState"] = @0;
    dictToRegister[@"IsContainerized"] = @YES;
    if (containerPath) {
        dictToRegister[@"Container"] = containerPath;
        dictToRegister[@"EnvironmentVariables"] = @{
            @"CFFIXED_USER_HOME" : containerPath,
            @"HOME" : containerPath,
            @"TMPDIR" : [containerPath stringByAppendingPathComponent:@"tmp"],
        };
    }
    dictToRegister[@"IsDeletable"] = @YES;
    dictToRegister[@"Path"] = appPath;
    dictToRegister[@"SignerOrganization"] = @"Apple Inc.";
    dictToRegister[@"SignatureVersion"] = @132352;
    dictToRegister[@"SignerIdentity"] = @"Apple iPhone OS Application Signing";
    dictToRegister[@"IsAdHocSigned"] = @YES;
    dictToRegister[@"LSInstallType"] = @1;
    dictToRegister[@"HasMIDBasedSINF"] = @0;
    dictToRegister[@"MissingSINF"] = @0;
    dictToRegister[@"FamilyID"] = @0;
    dictToRegister[@"IsOnDemandInstallCapable"] = @0;

    return ((BOOL (*)(id, SEL, NSDictionary *))objc_msgSend)(
        workspace, sel_registerName("registerApplicationDictionary:"), dictToRegister);
}

// MARK: custom 法安装主体（TrollStore RootHelper/main.m installApp custom 分支同构）
static BOOL EUTrollEPermasignInstall(NSString *appBundlePath, NSString **outInstalledPath, NSError **error)
{
    NSError * (^fail)(NSString *) = ^NSError *(NSString *msg) {
        return [NSError errorWithDomain:EUTrollEErrorDomain code:EUTrollEErrorCodePermasignInstallFailed
                                userInfo:@{NSLocalizedDescriptionKey : msg}];
    };

    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
        [appBundlePath stringByAppendingPathComponent:@"Info.plist"]];
    NSString *appId = info[@"CFBundleIdentifier"];
    if (![appId isKindOfClass:[NSString class]] || !appId.length) {
        if (error) *error = fail(@"Info.plist 缺 CFBundleIdentifier");
        return NO;
    }

    // 1. Bundle 容器（MCMAppContainer：/var/containers/Bundle/Application/<UUID>）
    void *mcm = dlopen("/System/Library/PrivateFrameworks/MobileContainerManager.framework/MobileContainerManager", RTLD_NOW);
    if (!mcm) {
        if (error) *error = fail(@"MobileContainerManager 私有框架加载失败");
        return NO;
    }
    Class appContainerClass = NSClassFromString(@"MCMAppContainer");
    if (!appContainerClass) {
        if (error) *error = fail(@"MCMAppContainer 类缺失（系统 ABI 变更）");
        return NO;
    }
    NSError *mcmError = nil;
    id appContainer = ((id (*)(id, SEL, NSString *, BOOL, BOOL *, NSError **))objc_msgSend)(
        appContainerClass,
        sel_registerName("containerWithIdentifier:createIfNecessary:existed:error:"),
        appId, YES, NULL, &mcmError);
    if (!appContainer || mcmError) {
        // entitlement 门禁首现点（containermanagerd XPC 查 entitlements）：
        // B25-1 ➕ spike 三候选路线裁决中，失败信息保留 mcmError 供定位
        if (error) *error = fail([NSString stringWithFormat:@"Bundle 容器创建失败（entitlement 门禁？spike 裁决中）：%@",
                                  mcmError.localizedDescription ?: @"未知错误"]);
        return NO;
    }
    id containerURL = ((id (*)(id, SEL))objc_msgSend)(appContainer, sel_registerName("url"));
    NSString *bundleContainerPath = [containerURL path];
    if (!bundleContainerPath.length) {
        if (error) *error = fail(@"容器 URL 解析失败");
        return NO;
    }

    // 2. 已装检测（TrollStore 171 同构语义：非本生态标记且容器非空 → 拒绝，防覆盖商店应用）
    NSString *markerPath = [bundleContainerPath stringByAppendingPathComponent:@"_TrollStore"];
    NSString *newAppBundlePath = [bundleContainerPath stringByAppendingPathComponent:appBundlePath.lastPathComponent];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:newAppBundlePath] && ![fm fileExistsAtPath:markerPath]) {
        if (error) *error = fail(@"同 bundleID 应用已存在且非巨魔E/巨魔生态安装（拒绝覆盖，防破坏商店应用）");
        return NO;
    }
    // 覆盖安装（更新）：先清旧 .app（进程已 root）
    if ([fm fileExistsAtPath:newAppBundlePath]) {
        [fm removeItemAtPath:newAppBundlePath error:nil];
    }

    // 3. 直拷 .app → Bundle 容器
    NSError *copyError = nil;
    if (![fm copyItemAtPath:appBundlePath toPath:newAppBundlePath error:&copyError]) {
        if (error) *error = fail([NSString stringWithFormat:@".app 拷贝入容器失败：%@",
                                  copyError.localizedDescription ?: @"未知错误"]);
        return NO;
    }

    // 4. 写 `_TrollStore` 标记（容器根，空文件；TrollStore 生态识别语义，保持互认兼容）
    if (![fm fileExistsAtPath:markerPath]) {
        if (![[NSData data] writeToFile:markerPath options:0 error:nil]) {
            if (error) *error = fail(@"`_TrollStore` 标记写入失败");
            return NO;
        }
    }

    // 5. 权限修正（两遍法：chown 33:33 → 目录/MachO 0755、其余 0644）
    EUTrollEFixPermissionsOfAppBundle(newAppBundlePath);

    // 6. 注册（LSApplicationWorkspace 注册字典）
    if (!EUTrollERegisterAppPath(newAppBundlePath, NO)) {
        // 注册失败回滚整个容器（TrollStore 181 同构：零残留）
        [fm removeItemAtPath:bundleContainerPath error:nil];
        if (error) *error = fail(@"LaunchServices 注册失败（lsd XPC entitlement 门禁？B25-1 ➕ spike 裁决中）");
        return NO;
    }

    if (outInstalledPath) *outInstalledPath = newAppBundlePath;
    if (error) *error = nil;
    return YES;
}

#pragma mark - jailed root 化（B25-1 ② 判修：iOS 17+ 直接内核写入版）

/// 绕过 proc_ucred_update_content 的 17+ 分支——该分支走 target_proc_with_ucred：
/// posix_spawn 一个 setuid-root 子进程（须实现 --fd/--uid argv 协议并向 fd 3 回写
/// 新 ucred）再 proc_copy_ucred 拷回。Dopamine 语境子进程=launchdhook（越狱注入
/// 产物），Engine B jailed 传入普通 sideload 二进制 → 17.0 域必死（B25-1 ②）。
/// 本函数直接 kwrite 本进程 ucred：uid/svuid/svgid/groups[0] → 0 +
/// task_tokens.audit_token 四字补丁（util.c:1107-1117 原样；≤16.6.1 域 Dopamine
/// 15-16 同款直写实践，17.0 域可行性由本仓 proc_ro→ucred 解引用基础设施保证，
/// kernel.c:46-55）。
/// 前置 cr_ref==1：原地改共享 ucred 会污染共享者（内核态 UB 面），非 1 直接
/// 失败保零残留（B25-1 评审要求）。
static BOOL EUTrollEJailedRootify(uint64_t selfProc)
{
    if (selfProc == 0) return NO;
    uint64_t ucred = proc_ucred(selfProc);
    if (ucred == 0) return NO;

    // 共享 ucred 拒改（kauth_cred 引用计数 >1 = 有其他进程共享，原地写=污染）
    if (kread32(ucred + koffsetof(ucred, ref)) != 1) return NO;

    // 四写：uid/svuid/svgid/groups[0] → 0（groups[0]=gid 0 即 root 语义；cr_ngroups
    // 不动——B25-1 记化妆级瑕疵，不影响 root 判定）
    kwrite32(ucred + koffsetof(ucred, svuid), 0);
    kwrite32(ucred + koffsetof(ucred, uid), 0);
    kwrite32(ucred + koffsetof(ucred, svgid), 0);
    kwrite32(ucred + koffsetof(ucred, groups), 0);

    // task_tokens.audit_token 四字补丁（17.0+ proc_ro 域必须：XPC 对端读的是
    // audit token 而非实时 ucred，不补则 root 化对守护进程不可见）
    if (gSystemInfo.kernelStruct.proc_ro.exists) {
        uint64_t proc_ro = kread_ptr(selfProc + koffsetof(proc, proc_ro));
        if (proc_ro != 0 && koffsetof(proc_ro, task_tokens)) {
            uint64_t auditToken = proc_ro + koffsetof(proc_ro, task_tokens)
                                + koffsetof(task_token_ro_data, audit_token);
            kwrite32(auditToken + 4, 0);  // uid
            kwrite32(auditToken + 8, 0);  // gid
            kwrite32(auditToken + 12, 0); // ruid
            kwrite32(auditToken + 16, 0); // rgid
        }
    }

    return (getuid() == 0);
}

/// 引擎B 主流程：一次性漏洞会话（kfd KRW + dmaFail PPL）→ root → CT 永久签名装本体
/// + Persistence Helper（第二槽位，TrollStore 2 同款"本体兼 helper"模式）。
/// 契约要点（B25）：成功=登记同一张重放表；会话失败=零残留（回滚 staging，不留半装状态）。
- (BOOL)installApplicationJailbreakFreeAtURL:(NSURL *)appURL error:(NSError **)error
{
    NSError * (^fail)(EUTrollEErrorCode, NSString *) = ^NSError *(EUTrollEErrorCode code, NSString *msg) {
        return [NSError errorWithDomain:EUTrollEErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey : msg}];
    };

    if (!appURL || ![[NSFileManager defaultManager] fileExistsAtPath:appURL.path]) {
        if (error) *error = fail(EUTrollEErrorCodeInvalidInput, @"路径不存在");
        return NO;
    }

    // ① 域校验（C24 矩阵）
    if (![self eutrolle_deviceInCoreTrustDomain]) {
        NSOperatingSystemVersion v = [NSProcessInfo processInfo].operatingSystemVersion;
        NSString *hint = (v.majorVersion >= 17 && v.minorVersion >= 1) || v.majorVersion > 17
            ? @"当前系统 CT 已修复：免越狱永久档不可达（16.6.1~18.7.1 可用越狱会话档【实验性，实机验证未完成】；16.7b/RC/17.0 可用 PC 备份注入档）"
            : @"16.7.x GA 系列 CT 已修复：免越狱永久档不可达（本版本可用越狱会话档兜底【实验性】）";
        if (error) *error = fail(EUTrollEErrorCodeDomainUnsupported, hint);
        return NO;
    }

    // ② helper 快路径：巨魔E 本体已装（重放表含 role=body 且容器在位）
    //    → 直接经 URL scheme 移交本体安装（TrollStore 语义；本体自身经 CT 永久签名常驻）
    NSArray *entries = [self installedApplications];
    for (NSDictionary *entry in entries) {
        if ([entry[@"role"] isEqualToString:@"body"] &&
            [[NSFileManager defaultManager] fileExistsAtPath:entry[@"path"]]) {
            NSString *handoff = [NSString stringWithFormat:@"euphoria-trolle://install?url=%@",
                                 [appURL.absoluteString stringByAddingPercentEncodingWithAllowedCharacters:
                                  [NSCharacterSet URLQueryAllowedCharacterSet]]];
            NSURL *url = [NSURL URLWithString:handoff];
            if (url) {
                // 此文件同时编译进 BaseBin/euphoria CLI（无 UIKit），
                // 运行时解析 UIApplication，避免链接期缺符号（仅构建修复）
                Class uiAppCls = NSClassFromString(@"UIApplication");
                if (uiAppCls) {
                    id app = ((id (*)(id, SEL))objc_msgSend)((id)uiAppCls, sel_registerName("sharedApplication"));
                    if (app) {
                        ((void (*)(id, SEL, NSURL *, NSDictionary *, id))objc_msgSend)(
                            app, sel_registerName("openURL:options:completionHandler:"), url, @{}, nil);
                    }
                }
                EUTrolleLog(@"巨魔E：本体在位，已移交安装 → %@", appURL.lastPathComponent);
                if (error) *error = nil;
                return YES;
            }
            break;
        }
    }

    // ③ 一次性漏洞会话：内核 KRW（kfd 系）+ PPL 物理 写（dmaFail）
    EUExploitManager *mgr = [EUExploitManager sharedManager];
    EUExploit *kernel = mgr.preferredKernelExploit;
    EUExploit *ppl = mgr.preferredPPLBypass;
    BOOL kernelStarted = NO, pplStarted = NO;

    // 会话内资源统一收尾（成功/失败都走：零残留）
    void (^sessionTeardown)(void) = ^{
        if (pplStarted) [ppl cleanup];
        if (kernelStarted) [kernel cleanup];
    };
    void (^sessionFail)(NSString *) = ^(NSString *msg) {
        sessionTeardown();
        if (error) *error = fail(EUTrollEErrorCodeSessionFailed, msg);
    };

    if (!kernel || ![kernel isSupported]) { sessionFail(@"无可用内核漏洞（kfd 系，免越狱域需 ≤16.6.1 且非 arm64e 16.6+ 设备端装法）"); return NO; }
    EUTrolleLog(@"巨魔E：启动一次性漏洞会话（内核=%@）…", kernel.displayName);
    if ([kernel load] != 0 || [kernel run] != 0) { sessionFail(@"内核漏洞会话失败（可重试；失败不残留）"); return NO; }
    kernelStarted = YES;

    if (ppl && [ppl isSupported]) {
        if ([ppl load] != 0 || [ppl run] != 0) { sessionFail(@"PPL 绕过（dmaFail）会话失败"); return NO; }
        pplStarted = YES;
    }
    // 注：纯 KRW（无 PPL）在 A12–A13 kfd 路线亦足以完成 ucred root 化；PPL 写仅在
    // 需要物理写路径时必备（dmaFail 优先带上，与越狱链同源）。

    // ④ root 化（B25-1 ② 判修：iOS 17+ 弃用 proc_ucred_update_content——其 17+ 分支
    //    走 target_proc_with_ucred spawn setuid-root 子进程协议，jailed 语境无此
    //    产物必死；≤16.x 维持原调用（else 分支=同款直接写，既有实践正确））
    uint64_t selfProc = proc_self();
    if (@available(iOS 17.0, *)) {
        if (!EUTrollEJailedRootify(selfProc)) {
            sessionFail(@"root 化失败（17+ 直接内核写入未生效：ucred 共享或 kwrite 异常）");
            return NO;
        }
    }
    else {
        gid_t rootGroups[NGROUPS_MAX] = {0}; // B25-1：原 [1] 长度传入后被按 NGROUPS_MAX 遍历 → 栈越界读（UB）
        NSString *selfExec = [NSBundle mainBundle].executablePath;
        if (selfProc == 0 || proc_ucred_update_content(selfProc, selfExec.fileSystemRepresentation,
                                                        0, 0, 0, 0, rootGroups) != 0 || getuid() != 0) {
            sessionFail(@"root 化失败（ucred 更新未生效）");
            return NO;
        }
    }
    EUTrolleLog(@"巨魔E：会话 root 就绪（uid=0）");

    // ⑤ 解包（系统 libarchive；staging=临时目录，失败零残留）
    NSString *stagingDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                            [NSString stringWithFormat:@"trolle_b_%@", [[NSUUID UUID] UUIDString]]];
    NSString *appBundlePath = nil;
    @try {
        [[NSFileManager defaultManager] createDirectoryAtPath:stagingDir withIntermediateDirectories:YES attributes:nil error:nil];
        EUTrolleLog(@"巨魔E：解包 IPA（libarchive）…");
        if (!EUTrollEExtractZipWithLibarchive(appURL.path, stagingDir)) {
            sessionFail(@"IPA 解包失败（libarchive）");
            return NO;
        }
        NSString *payloadDir = [stagingDir stringByAppendingPathComponent:@"Payload"];
        for (NSString *item in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:payloadDir error:nil]) {
            if ([item hasSuffix:@".app"]) { appBundlePath = [payloadDir stringByAppendingPathComponent:item]; break; }
        }
        if (!appBundlePath) { sessionFail(@"IPA 内未找到 Payload/*.app"); return NO; }
    } @finally {
        // staging 在成功路径上于⑥后清理；此处兜底防中途抛异常残留
    }

    // ⑥ CT 永久签名安装（B25-1 ③：custom 法——MCMAppContainer 直建容器+直拷+注册）
    //   + Persistence Helper 第二槽位
    EUTrolleLog(@"巨魔E：永久签名安装（CT 域，custom 法）…");
    NSString *installedPath = nil;
    if (!EUTrollEPermasignInstall(appBundlePath, &installedPath, error)) {
        [[NSFileManager defaultManager] removeItemAtPath:stagingDir error:nil];
        if (error && *error == nil) *error = fail(EUTrollEErrorCodePermasignInstallFailed, @"永久签名安装失败");
        sessionTeardown();
        return NO;
    }

    // 主二进制 CDHash（登记重放表用；ChOma 桥接同引擎A）
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[appBundlePath stringByAppendingPathComponent:@"Info.plist"]];
    NSString *execPath = [appBundlePath stringByAppendingPathComponent:info[@"CFBundleExecutable"] ?: @""];
    uint8_t cdhash[CS_CDHASH_LEN] = {0};
    if (!execPath.length || !EUTrollEComputeCDHash(execPath, cdhash)) {
        [[NSFileManager defaultManager] removeItemAtPath:stagingDir error:nil];
        if (error) *error = fail(EUTrollEErrorCodeCDHashFailed, @"主二进制 CDHash 计算失败");
        sessionTeardown();
        return NO;
    }
    NSMutableString *cdhashHex = [NSMutableString string];
    for (int i = 0; i < CS_CDHASH_LEN; i++) [cdhashHex appendFormat:@"%02x", cdhash[i]];

    // custom 法直接返回容器内落盘路径（/var/containers/Bundle/Application/<UUID>/
    // <App>.app），原 installd 迁移后的 UUID 目录扫描已不需要
    NSString *bundleID = info[@"CFBundleIdentifier"] ?: appBundlePath.lastPathComponent;

    // Persistence Helper：同本体第二槽位安装（TrollStore 2"本体兼 helper"模式；
    // helper 负责 respring/图标缓存重载后的签名态恢复——C23 实证必要性）
    EUTrolleLog(@"巨魔E：安装 Persistence Helper（第二槽位）…");
    [self eutrolle_installPersistenceHelperFromBundle:appBundlePath];

    // ⑦ 登记重放表（与引擎A 同表；后续越狱时 Engine A 幂等重放信任缓存）
    NSMutableArray *newEntries = [entries mutableCopy];
    [newEntries addObject:@{
        @"bundleID" : bundleID,
        @"path" : installedPath,
        @"cdhash" : cdhashHex,
        @"role" : @"body",           // 引擎B 装出的首个应用=巨魔E 本体
        @"engine" : @"B",            // 来源标记（A/B 互不冲突）
        @"installedAt" : @([[NSDate date] timeIntervalSince1970]),
    }];
    // 保存此时进程为 root，直接落盘（无 runAsRoot 依赖——那是越狱态通道）
    NSString *registryDir = [[EUTrollE registryPath] stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:registryDir withIntermediateDirectories:YES attributes:nil error:nil];
    [self saveEntries:newEntries];

    // ⑧ 会话收尾（成功路径：清 staging + 漏洞清理，零残留）
    [[NSFileManager defaultManager] removeItemAtPath:stagingDir error:nil];
    sessionTeardown();
    EUTrolleLog(@"巨魔E：免越狱安装完成（永久签名，重启可用）");
    return YES;
}

/// Persistence Helper 安装：将本体 .app 复制到第二容器槽位（root 直拷+installd 注册）。
/// 简化实现（TrollStore 2 同款语义）：helper=本体自身第二副本，重装/自愈由其 UI 承担。
- (void)eutrolle_installPersistenceHelperFromBundle:(NSString *)appBundlePath
{
    @try {
        NSString *helperUUID = [[NSUUID UUID] UUIDString];
        NSString *helperDir = [@"/var/containers/Bundle/Application" stringByAppendingPathComponent:helperUUID];
        NSString *helperApp = [helperDir stringByAppendingPathComponent:appBundlePath.lastPathComponent];
        if ([[NSFileManager defaultManager] createDirectoryAtPath:helperDir withIntermediateDirectories:YES attributes:nil error:nil]) {
            if ([[NSFileManager defaultManager] copyItemAtPath:appBundlePath toPath:helperApp error:nil]) {
                EUTrollEPermasignInstall(helperApp, NULL, NULL); // CT 注册（失败不阻塞主流程；helper 缺失仅影响图标缓存重载自愈）
                NSMutableArray *entries = [[self installedApplications] mutableCopy];
                [entries addObject:@{@"bundleID" : @"dev.euphoria.trolle.helper",
                                     @"path" : helperApp,
                                     @"cdhash" : @"",        // 与本体同二进制：重放时按本体 cdhash 复用
                                     @"role" : @"helper",
                                     @"engine" : @"B"}];
                [self saveEntries:entries];
            }
        }
    } @catch (NSException *e) {
        EUTrolleLog(@"巨魔E：helper 安装异常（不阻塞）——%@", e);
    }
}

#pragma mark 引擎C：容器模式安装侧（B26 L1 基线，无漏洞全版本域）

/// 引擎C 安装侧：IPA 解包 → 暂存宿主沙盒容器目录 → 登记重放表（engine=C）。
/// 语义（B26 分层可用 / LiveContainer 机制借鉴·协议式重实现，无 GPL 代码搬运）：
///   - 无漏洞、无越狱、全版本域（iOS 15+）；app 以"插件"形态在容器内运行
///   - JIT 可用（<26）：签名全绕；JIT-Less：宿主证书代签（运行时层职责）
///   - 主屏图标 = 快捷指令 + URL scheme（LC 实证机制：euphoria-trolle://launch?id=<uuid>）
///   - 登记重放表 → 后续越狱时 Engine A 幂等重放，L1 自动升级为 L3 满血形态
/// 边界（如实）：L1 非"真永久"——宿主签名过期未续签=容器内 app 全灭；
/// UI 层须暴露"签名健康度"（B26 §3.1）。
- (BOOL)installApplicationContainerizedAtURL:(NSURL *)appURL error:(NSError **)error
{
    NSError * (^fail)(EUTrollEErrorCode, NSString *) = ^NSError *(EUTrollEErrorCode code, NSString *msg) {
        return [NSError errorWithDomain:EUTrollEErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey : msg}];
    };

    if (!appURL || ![[NSFileManager defaultManager] fileExistsAtPath:appURL.path]) {
        if (error) *error = fail(EUTrollEErrorCodeInvalidInput, @"路径不存在");
        return NO;
    }

    // ① 解包（复用引擎B的 libarchive 通道；此处无 root，目标目录=宿主沙盒内，无权限问题）
    NSString *containersRoot = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/EUTrollEContainers"];
    NSString *uuid = [[NSUUID UUID] UUIDString];
    NSString *containerDir = [containersRoot stringByAppendingPathComponent:uuid];
    NSString *stagingDir = [containerDir stringByAppendingPathComponent:@"staging"];

    [[NSFileManager defaultManager] createDirectoryAtPath:stagingDir withIntermediateDirectories:YES attributes:nil error:nil];
    EUTrolleLog(@"巨魔E（容器）：解包 IPA（libarchive，免越狱无漏洞通道）…");
    if (!EUTrollEExtractZipWithLibarchive(appURL.path, stagingDir)) {
        [[NSFileManager defaultManager] removeItemAtPath:containerDir error:nil]; // 零残留
        if (error) *error = fail(EUTrollEErrorCodeUnpackFailed, @"IPA 解包失败（libarchive）");
        return NO;
    }

    // ② 定位 Payload/*.app → 落位容器目录
    NSString *appBundlePath = nil;
    NSString *payloadDir = [stagingDir stringByAppendingPathComponent:@"Payload"];
    for (NSString *item in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:payloadDir error:nil]) {
        if ([item hasSuffix:@".app"]) { appBundlePath = [payloadDir stringByAppendingPathComponent:item]; break; }
    }
    if (!appBundlePath) {
        [[NSFileManager defaultManager] removeItemAtPath:containerDir error:nil];
        if (error) *error = fail(EUTrollEErrorCodeNoPayload, @"IPA 内未找到 Payload/*.app");
        return NO;
    }
    NSString *finalPath = [containerDir stringByAppendingPathComponent:appBundlePath.lastPathComponent];
    if (![[NSFileManager defaultManager] moveItemAtPath:appBundlePath toPath:finalPath error:nil]) {
        [[NSFileManager defaultManager] removeItemAtPath:containerDir error:nil];
        if (error) *error = fail(EUTrollEErrorCodeCopyFailed, @"容器落位失败");
        return NO;
    }
    [[NSFileManager defaultManager] removeItemAtPath:stagingDir error:nil];

    // ③ 元数据 + CDHash（登记重放表：保留 L1→L3 升级路径——越狱时 Engine A 顺带重放）
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[finalPath stringByAppendingPathComponent:@"Info.plist"]];
    NSString *bundleID = info[@"CFBundleIdentifier"] ?: finalPath.lastPathComponent;
    NSString *execPath = [finalPath stringByAppendingPathComponent:info[@"CFBundleExecutable"] ?: @""];
    NSMutableString *cdhashHex = [NSMutableString string];
    uint8_t cdhash[CS_CDHASH_LEN] = {0};
    if (execPath.length && EUTrollEComputeCDHash(execPath, cdhash)) {
        for (int i = 0; i < CS_CDHASH_LEN; i++) [cdhashHex appendFormat:@"%02x", cdhash[i]];
    }

    // ④ 登记重放表（engine=C；cdhash 可算出则记录，L1→L3 升级即用）
    NSMutableArray *entries = [[self installedApplications] mutableCopy];
    [entries addObject:@{
        @"bundleID" : bundleID,
        @"path" : finalPath,
        @"cdhash" : cdhashHex.length ? [cdhashHex copy] : @"",
        @"role" : @"guest",           // 容器内访客应用
        @"engine" : @"C",
        @"container" : uuid,          // 启动引用：euphoria-trolle://launch?id=<uuid>
        @"installedAt" : @([[NSDate date] timeIntervalSince1970]),
    }];
    [self saveEntries:entries];

    EUTrolleLog(@"巨魔E（容器）：安装完成（L1 基线，%@）——后续越狱时自动升级为满血形态", bundleID);
    return YES;
}

#pragma mark 沙盒镜像表迁移（免越狱期条目 → 主表，幂等）

/// 越狱引导时调用：把引擎B/C 在免越狱期写入沙盒镜像表的条目合并进主表（按 path 去重），
/// 随后清空镜像表。条目进入主表后由 Engine A 幂等重放信任缓存——即 B25 的
/// "L1/L2 装的应用在后续越狱时升级为满血形态"闭环。
+ (void)migrateSandboxRegistryIfNeeded
{
    NSString *sandboxPath = [self sandboxRegistryPath];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:sandboxPath]) return;

    NSArray *sandboxEntries = [NSDictionary dictionaryWithContentsOfFile:sandboxPath][@"entries"];
    if (![sandboxEntries isKindOfClass:[NSArray class]] || sandboxEntries.count == 0) {
        [fm removeItemAtPath:sandboxPath error:nil];
        return;
    }

    // 主表条目（此时 registryPath 已指 /var/jb——越狱引导期 isJailbroken 已就位）
    NSString *mainPath = JBROOT_PATH(@"/var/db/euphoria/trolle.plist");
    NSMutableArray *main = [[NSDictionary dictionaryWithContentsOfFile:mainPath][@"entries"] mutableCopy] ?: [NSMutableArray array];
    if (![main isKindOfClass:[NSMutableArray class]]) main = [NSMutableArray array];

    NSSet *existingPaths = [NSSet setWithArray:[main valueForKey:@"path"]];
    for (NSDictionary *entry in sandboxEntries) {
        if ([entry isKindOfClass:[NSDictionary class]] && entry[@"path"] && ![existingPaths containsObject:entry[@"path"]]) {
            [main addObject:entry];
        }
    }

    NSString *dir = [mainPath stringByDeletingLastPathComponent];
    [[EUEnvironmentManager sharedManager] runAsRoot:^{
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        [@{@"entries" : main} writeToFile:mainPath atomically:YES];
        [[NSFileManager defaultManager] removeItemAtPath:sandboxPath error:nil]; // 搬运完成即清源（幂等）
    }];
}

#pragma mark 越狱时重放（幂等）

+ (void)replayTrustCacheEntries
{
    // 先迁移沙盒镜像表（引擎B/C 在免越狱期写入的条目）→ 主表，幂等（B25 契约修订）
    [self migrateSandboxRegistryIfNeeded];

    NSString *path = [EUTrollE registryPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return;

    NSArray *entries = [[EUTrollE sharedInstance] installedApplications];
    if (entries.count == 0) return;

    EUTrolleLog(@"巨魔E：重放信任缓存（%lu 项）…", (unsigned long)entries.count);
    NSMutableArray *valid = [NSMutableArray array];
    for (NSDictionary *entry in entries) {
        NSString *cdhashHex = entry[@"cdhash"];
        if (![cdhashHex isKindOfClass:[NSString class]] || cdhashHex.length != CS_CDHASH_LEN * 2) continue;
        if (![[NSFileManager defaultManager] fileExistsAtPath:entry[@"path"]]) continue; // 应用被手动删除 → 跳过并出清

        uint8_t cdhash[CS_CDHASH_LEN] = {0};
        const char *hex = cdhashHex.UTF8String;
        for (int i = 0; i < CS_CDHASH_LEN; i++) {
            unsigned byte = 0;
            sscanf(hex + (i * 2), "%02x", &byte);
            cdhash[i] = (uint8_t)byte;
        }
        if (jb_trustcache_add_cdhashes((cdhash_t *)cdhash, 1) == 0) {
            [valid addObject:entry];
        }
    }

    // 出清已被删除的应用条目（幂等自洁）
    if (valid.count != entries.count) {
        [[EUTrollE sharedInstance] saveEntries:valid];
    }
}

@end
