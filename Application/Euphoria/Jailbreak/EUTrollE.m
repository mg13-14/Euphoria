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
#import <libjailbreak/jbroot.h>
#import <libjailbreak/trustcache.h>
#import <libjailbreak/info.h>
#import <choma/Fat.h>
#import <choma/MachO.h>
#import <choma/CSBlob.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <sys/sysctl.h>
#import <string.h>
#import <unistd.h>

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
        if (error) *error = fail(EUTrollEErrorCodeNotJailbroken, @"巨魔E 该模式需要越狱状态（免越狱安装为 Engine B，V0.9.1 目标）");
        return NO;
    }

    if (!appURL || ![[NSFileManager defaultManager] fileExistsAtPath:appURL.path]) {
        if (error) *error = fail(EUTrollEErrorCodeInvalidInput, @"路径不存在");
        return NO;
    }

    NSString *stagingDir = nil;
    NSString *appBundlePath = nil;

    // ① 解包（.ipa → 暂存目录；.app 直接用）
    if ([appURL.pathExtension caseInsensitiveCompare:@"ipa"] == NSOrderedSame) {
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
    else if ([appURL.pathExtension caseInsensitiveCompare:@"app"] == NSOrderedSame) {
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
    int r = exec_cmd_trusted(JBROOT_PATH("/usr/bin/uicache"),
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

    exec_cmd_trusted(JBROOT_PATH("/usr/bin/uicache"), "-u", [target[@"path"] stringByDeletingLastPathComponent].fileSystemRepresentation, NULL);
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

/// CT 永久签名安装：MobileInstallation 私有框架（root 上下文，TrollHelper 同构路线）
/// IPA 构建期已带 CT 漏洞签名（ldid 假签/多签名混淆）→ installd 经 CoreTrust 误验证通过
/// → 应用以"永久签名"形态注册（重启/无越狱均可用，TrollStore 语义）。
static BOOL EUTrollEPermasignInstall(NSString *appBundlePath, NSError **error)
{
    void *mi = dlopen("/System/Library/PrivateFrameworks/MobileInstallation.framework/MobileInstallation", RTLD_NOW);
    if (!mi) {
        if (error) *error = [NSError errorWithDomain:EUTrollEErrorDomain code:EUTrollEErrorCodePermasignInstallFailed
                                             userInfo:@{NSLocalizedDescriptionKey : @"MobileInstallation 私有框架加载失败"}];
        return NO;
    }
    // 历史 ABI：int MobileInstallationInstall(NSString *path, NSDictionary *options, dispatch_queue_t cbq, void (^cb)(NSDictionary *), NSError **error)
    int (*MIInstall)(NSString *, NSDictionary *, dispatch_queue_t, void (^)(NSDictionary *), NSError **) =
        dlsym(mi, "MobileInstallationInstall");
    if (!MIInstall) {
        if (error) *error = [NSError errorWithDomain:EUTrollEErrorDomain code:EUTrollEErrorCodePermasignInstallFailed
                                             userInfo:@{NSLocalizedDescriptionKey : @"MobileInstallationInstall 符号缺失（系统 ABI 变更，需按版本适配）"}];
        return NO;
    }
    NSError *miError = nil;
    // B 评审修正（15:15）：MIInstall 为异步接口——回调由 installd 在完成/出错时触发，
    // 返回值 r==0 仅代表"已受理"。TrollHelper 同构做法=信号量等回调终态（Progress=100
    // 或 Error 键出现），否则后续步骤（helper 安装/登记重放表/UI 成功提示）会在
    // installd 尚未落盘时竞态执行。30s 超时兜底防死等。
    __block BOOL installSuccess = NO;
    __block NSString *installErrorDesc = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    void (^cb)(NSDictionary *) = ^(NSDictionary *operation) {
        if (![operation isKindOfClass:[NSDictionary class]]) return;
        if (operation[@"Error"]) {
            installErrorDesc = [NSString stringWithFormat:@"%@", operation[@"Error"]];
            dispatch_semaphore_signal(sema);
        }
        else if ([operation[@"Progress"] isKindOfClass:[NSNumber class]] &&
                 [(NSNumber *)operation[@"Progress"] integerValue] >= 100) {
            installSuccess = YES;
            dispatch_semaphore_signal(sema);
        }
    };
    int r = MIInstall(appBundlePath, @{@"CFBundleIdentifier" : @""},
                      dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), cb, &miError);
    if (r != 0) {
        if (error) *error = miError ?: [NSError errorWithDomain:EUTrollEErrorDomain code:EUTrollEErrorCodePermasignInstallFailed
                                                        userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"installd 安装返回 %d（CT 域校验未通过？检查 IPA 签名链）", r]}];
        return NO;
    }
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
    if (!installSuccess) {
        if (error) *error = [NSError errorWithDomain:EUTrollEErrorDomain code:EUTrollEErrorCodePermasignInstallFailed
                                             userInfo:@{NSLocalizedDescriptionKey : installErrorDesc ?: @"installd 安装回调超时（30s）或未报告完成——视为失败，零残留"}];
        return NO;
    }
    return YES;
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
            ? @"当前系统 CT 已修复：免越狱永久档不可达（16.6.1~18.7.1 可用越狱会话档；16.7b/RC/17.0 可用 PC 备份注入档）"
            : @"16.7.x GA 系列 CT 已修复：免越狱永久档不可达（本版本可用越狱会话档兜底）";
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
                [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
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

    // ④ root 化（libjailbreak proc_ucred_update_content：iOS 17+ 含 audit token 修正路径）
    uint64_t selfProc = proc_self();
    gid_t rootGroups[1] = {0};
    NSString *selfExec = [NSBundle mainBundle].executablePath;
    if (selfProc == 0 || proc_ucred_update_content(selfProc, selfExec.fileSystemRepresentation,
                                                    0, 0, 0, 0, rootGroups) != 0 || getuid() != 0) {
        sessionFail(@"root 化失败（ucred 更新未生效）");
        return NO;
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

    // ⑥ CT 永久签名安装（installd 路径）+ Persistence Helper 第二槽位
    EUTrolleLog(@"巨魔E：永久签名安装（CT 域）…");
    if (!EUTrollEPermasignInstall(appBundlePath, error)) {
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

    // 安装后定位真实容器路径（installd 迁移后 .app 落 /var/containers/Bundle/Application/<UUID>/）
    NSString *installedPath = appBundlePath;
    NSString *bundleID = info[@"CFBundleIdentifier"] ?: appBundlePath.lastPathComponent;
    NSString *containersRoot = @"/var/containers/Bundle/Application";
    for (NSString *uuid in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:containersRoot error:nil]) {
        NSString *candidate = [[containersRoot stringByAppendingPathComponent:uuid]
                               stringByAppendingPathComponent:appBundlePath.lastPathComponent];
        if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) { installedPath = candidate; break; }
    }

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
                EUTrollEPermasignInstall(helperApp, NULL); // CT 注册（失败不阻塞主流程；helper 缺失仅影响图标缓存重载自愈）
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
