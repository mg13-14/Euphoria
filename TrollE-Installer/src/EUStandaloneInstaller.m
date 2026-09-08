//
//  EUStandaloneInstaller.m
//  TrollE-Installer
//
//  引擎 B/C 完整抽取件——源：主树 Application/Euphoria/Jailbreak/EUTrollE.m
//  （作者 B 线，27.08.2026；抽取时逐段标注【源 Lx-Ly】）。
//  解耦五点（详见 README §四）：
//   #1 EUTrolleLog → EUStandaloneLogger
//   #2 EUEnvironmentManager → EUStandaloneEnvironment
//   #3 EUExploitManager → EUStandaloneExploitManager
//   #4 JBROOT_PATH → EUStandaloneJBROOT
//   #5 registryPath 双模 → 沙盒镜像表唯一化（独立安装器永不写越狱主表）
//  抽离：并行搜索员C，2026-09-03。深度移植/实机验证：B 线。
//

#import "EUStandaloneInstaller.h"
#import "EUStandaloneLogger.h"
#import "EUStandaloneEnvironment.h"
#import "EUStandaloneExploit.h"
#import "EUStandaloneConfig.h"
#import <libjailbreak/util.h>        // proc_ucred_update_content（≤16.x root 化，B 线 09-04 补）
#import <libjailbreak/kernel.h>      // proc_ucred / proc_self【源 L14】
#import <libjailbreak/primitives.h>  // kread32/kwrite32/kread_ptr【源 L15】
#import <libjailbreak/info.h>        // gSystemInfo / koffsetof【源 L17】
#import <choma/Fat.h>
#import <choma/MachO.h>
#import <choma/CSBlob.h>
#import <choma/CodeDirectory.h>        // CS_CDHASH_LEN（B 线补：显式引入，防 SDK 无 codesign.h 兜底路径失效）
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <sys/sysctl.h>
#import <string.h>
#import <unistd.h>
#import <limits.h>                   // NGROUPS_MAX【源 L26】
#import <objc/message.h>             // objc_msgSend【源 L27】
#import <objc/runtime.h>
#import <mach-o/loader.h>            // MH_MAGIC_64【源 L29】
#import <mach-o/fat.h>               // FAT_MAGIC【源 L30】

// CS_CDHASH_LEN（choma 头内定义；与主树一致）
#ifndef CS_CDHASH_LEN
#include <codesign.h>
#endif

NSString *const EUStandaloneInstallerErrorDomain = @"EUStandaloneInstallerErrorDomain";

/// 解耦点 #1：主树 EUTrolleLog（EUUIManager.sendLog）→ 独立 Logger
#define EUStandaloneLog(fmt, ...) [[EUStandaloneLogger sharedLogger] log:(fmt), ##__VA_ARGS__]

@implementation EUStandaloneInstaller

// 修复#1：头文件声明 +sharedInstaller 但 .m 从未实现（19 处调用点链接 undefined symbol）
// ——补 dispatch_once 单例（与 EUStandaloneLogger/Environment 同构）
+ (instancetype)sharedInstaller
{
    static EUStandaloneInstaller *sShared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sShared = [[EUStandaloneInstaller alloc] init];
    });
    return sShared;
}

#pragma mark - 沙盒镜像表（解耦点 #5；源 L68-117 双模段的独立版语义）

+ (NSString *)sandboxRegistryPath
{
    return [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/EUTrollE"]
            stringByAppendingPathComponent:@"registry.plist"];
}

- (NSString *)registryPath
{
    // 独立安装器免越狱态=沙盒镜像表唯一注册表（解耦点 #5）。
    // 越狱态只读兼容：主表在位（/var/jb/var/db/euphoria/trolle.plist）时读它，
    // 用于 helper 快路径判断"本体是否已装"；本类永不写入主表（写入权归主树 Euphoria）。
    if ([[EUStandaloneEnvironment sharedEnvironment] isJailbroken] &&
        [[NSFileManager defaultManager] fileExistsAtPath:EUStandaloneJBROOT(@"/var/db/euphoria/trolle.plist")]) {
        return EUStandaloneJBROOT(@"/var/db/euphoria/trolle.plist");
    }
    return [EUStandaloneInstaller sandboxRegistryPath];
}

- (NSArray<NSDictionary<NSString *, id> *> *)installedApplications
{
    NSString *path = [self registryPath];
    NSArray *entries = [NSDictionary dictionaryWithContentsOfFile:path][@"entries"];
    return [entries isKindOfClass:[NSArray class]] ? entries : @[];
}

- (void)saveEntries:(NSArray<NSDictionary<NSString *, id> *> *)entries
{
    // 独立版语义（源 L103-117 精简）：镜像表路径恒在沙盒（可写），root 会话期
    // /非 root 一律直写——runAsRoot 借道通道仅越狱态需要，独立安装器无此场景。
    void (^write)(void) = ^{
        NSString *dir = [[EUStandaloneInstaller sandboxRegistryPath] stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES attributes:nil error:nil];
        [@{@"entries" : entries ?: @[]} writeToFile:[EUStandaloneInstaller sandboxRegistryPath]
                                          atomically:YES];
    };
    write();
}

#pragma mark - CT 域判定（源 L311-327，原样）

/// 免越狱永久域判定（C24 修正版矩阵）：
///   CT 全史域 = 14.0b2–16.7RC 连续带 + 17.0 全系（b1–5/GA）
///   死区 = 16.7.x GA 系列（16.7~16.7.10；RC 20H18 除外）
///   17.0.1+ = CT 已修，免越狱永久档不可达（TrollStore 2.1.1@2026-04 佐证）
- (BOOL)deviceInCoreTrustDomain
{
    NSOperatingSystemVersion v = [NSProcessInfo processInfo].operatingSystemVersion;
    if (v.majorVersion > 17) return NO;
    // 修复#13：17.0.1+ 域外（文档矩阵）——原判定 minorVersion==0 会把 17.0.1~17.0.2
    // （patch≥1）误判为域内；17.0 全系=17.0.0（b1–5/GA 同 20A 系列，patch 恒 0）
    if (v.majorVersion == 17) return (v.minorVersion == 0 && v.patchVersion == 0);
    if (v.minorVersion == 7) {
        char osversion[32] = {0};
        size_t len = sizeof(osversion) - 1;
        sysctlbyname("kern.osversion", osversion, &len, NULL, 0);
        return (strcmp(osversion, "20H18") == 0);
    }
    return YES;
}

#pragma mark - ChOma C 桥接（源 L36-62，原样）

static BOOL EUStandaloneComputeCDHash(NSString *binaryPath, uint8_t cdhash[CS_CDHASH_LEN])
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

#pragma mark - libarchive 免越狱解包（源 L329-427，原样）

/// jailed 环境无 /var/jb/unzip → 用系统自带 libarchive
/// （/usr/lib/libarchive.2.dylib，iOS 14–17 均随系统提供；引擎B 会话期进程已 root）
struct archive;
struct archive_entry;
#ifndef ARCHIVE_OK
#define ARCHIVE_OK 0
#endif
#ifndef ARCHIVE_EXTRACT_TIME
#define ARCHIVE_EXTRACT_TIME (1 << 2)
#endif
#ifndef AE_IFDIR
#define AE_IFDIR 0040000
#endif
#ifndef AE_IFLNK
#define AE_IFLNK 0120000
#endif

static BOOL EUStandaloneExtractZipWithLibarchive(NSString *zipPath, NSString *destDir)
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
    // 安全选项级联（B 评审缺陷②修复）：SECURE_SYMLINKS/NODOTDOT/NOABSOLUTEPATHS 级联降级
    if (a_write_disk_set_options) {
        int optSets[] = {
            ARCHIVE_EXTRACT_TIME | 0x0100 | 0x0200 | 0x10000,
            ARCHIVE_EXTRACT_TIME | 0x0100 | 0x0200,
            ARCHIVE_EXTRACT_TIME,
        };
        BOOL optsOK = NO;
        for (size_t i = 0; i < sizeof(optSets) / sizeof(optSets[0]) && !optsOK; i++) {
            if (a_write_disk_set_options(ext, optSets[i]) == 0) optsOK = YES;
        }
        if (!optsOK) { a_read_free(a); a_write_free(ext); return NO; }
    }

    BOOL ok = NO;
    if (a_read_open_filename(a, zipPath.fileSystemRepresentation, 10240) == ARCHIVE_OK) {
        ok = YES;
        struct archive_entry *entry = NULL;
        while (a_read_next_header(a, &entry) == ARCHIVE_OK) {
            // 消毒：拒绝绝对路径/.. 穿越（C 侧复核，纵深防御）
            const char *pname = a_entry_pathname(entry);
            if (!pname || pname[0] == '/' || strstr(pname, "..")) { ok = NO; break; }
            // 拒绝符号链接条目（B 评审修正：防经内嵌 symlink 写穿越）
            if (a_entry_filetype && (a_entry_filetype(entry) & AE_IFLNK) == AE_IFLNK) { ok = NO; break; }
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

#pragma mark - MachO 探测 + 权限修正 + 注册（源 L445-553，原样）

// MachO 文件探测（TrollStore main.m isMachoFile 同构；决定 0755 提权位）
static BOOL EUStandaloneIsMachoFile(NSString *filePath)
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

// 权限修正两遍法（TrollStore main.m:178 fixPermissionsOfAppBundle 同构）
// 第一遍全量 chown(33,33)+chmod 0644；第二遍目录与 MachO 可执行提权 0755
static void EUStandaloneFixPermissionsOfAppBundle(NSString *appBundlePath)
{
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager]
        enumeratorAtURL:[NSURL fileURLWithPath:appBundlePath]
        includingPropertiesForKeys:nil options:0 errorHandler:nil];
    for (NSURL *url in enumerator) {
        chown(url.path.fileSystemRepresentation, 33, 33);
        chmod(url.path.fileSystemRepresentation, 0644);
    }
    // 修复#12：NSDirectoryEnumerator 是一次性迭代器——第二遍复用已耗尽实例拿到的
    // 是 0 个对象（目录/MachO 永不提权 0755，装出的 app 无法启动）。必须重建。
    NSDirectoryEnumerator *secondPass = [[NSFileManager defaultManager]
        enumeratorAtURL:[NSURL fileURLWithPath:appBundlePath]
        includingPropertiesForKeys:nil options:0 errorHandler:nil];
    for (NSURL *url in secondPass) { // 第二遍（源 L474-479 两遍法：目录与 MachO 提权）
        BOOL isDir = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&isDir];
        if (isDir || EUStandaloneIsMachoFile(url.path)) {
            chmod(url.path.fileSystemRepresentation, 0755);
        }
    }
    chown(appBundlePath.fileSystemRepresentation, 33, 33);
    chmod(appBundlePath.fileSystemRepresentation, 0755);
}

// LSApplicationWorkspace 注册字典直注册（源 L487-553，TrollStore 同构）
static BOOL EUStandaloneRegisterAppPath(NSString *appPath, BOOL forceSystem)
{
    // 【源 L487-553 原样；registerApplicationDictionary: 私有 API 运行时调用】
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
        [appPath stringByAppendingPathComponent:@"Info.plist"]];
    if (!info) return NO;

    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!workspaceClass) return NO;
    id workspace = ((id (*)(id, SEL))objc_msgSend)(workspaceClass, sel_registerName("defaultWorkspace"));
    if (!workspace) return NO;

    // 注册字典（TrollStore RootHelper main.m registerAppDictionary 同构字段集）
    NSMutableDictionary *dictToRegister = [NSMutableDictionary dictionary];
    dictToRegister[@"CFBundleIdentifier"] = info[@"CFBundleIdentifier"];
    dictToRegister[@"CFBundleExecutable"] = info[@"CFBundleExecutable"];
    dictToRegister[@"CFBundleName"] = info[@"CFBundleName"];
    dictToRegister[@"CFBundleDisplayName"] = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"];
    dictToRegister[@"CFBundleIconFile"] = info[@"CFBundleIconFile"] ?: info[@"CFBundleIcons"];
    dictToRegister[@"CFBundleShortVersionString"] = info[@"CFBundleShortVersionString"];
    dictToRegister[@"CFBundleVersion"] = info[@"CFBundleVersion"];
    dictToRegister[@"CFBundleInfoDictionaryVersion"] = info[@"CFBundleInfoDictionaryVersion"];
    dictToRegister[@"CFBundlePackageType"] = info[@"CFBundlePackageType"] ?: @"APPL";
    dictToRegister[@"DTPlatformBuild"] = info[@"DTPlatformBuild"];
    dictToRegister[@"DTSDKName"] = info[@"DTSDKName"];
    dictToRegister[@"LSRequiresIPhoneOS"] = info[@"LSRequiresIPhoneOS"] ?: @YES;
    dictToRegister[@"Path"] = appPath;
    dictToRegister[@"ContainerBundlePath"] = [appPath stringByDeletingLastPathComponent];
    dictToRegister[@"ApplicationType"] = @"User";
    dictToRegister[@"EnvironmentVariables"] = @{ @"_TROLLSTORE_INSTALLED_" : @YES };
    dictToRegister[@"IsDeletable"] = @YES;
    dictToRegister[@"FailsToLaunchInHidden"] = @YES;
    dictToRegister[@"VersionString"] = info[@"CFBundleShortVersionString"];
    if (forceSystem) dictToRegister[@"ApplicationType"] = @"System";
    dictToRegister[@"FamilyID"] = @0;
    dictToRegister[@"IsOnDemandInstallCapable"] = @0;

    return ((BOOL (*)(id, SEL, NSDictionary *))objc_msgSend)(
        workspace, sel_registerName("registerApplicationDictionary:"), dictToRegister);
}

#pragma mark - CT custom 法安装主体（源 L555-644，原样）

/// TrollStore RootHelper/main.m installApp custom 分支同构（B25-1 ③ 重做）：
/// MCMAppContainer 直建容器 → 直拷 .app → `_TrollStore` 标记 → 权限两遍法 →
/// LSApplicationWorkspace 注册。全程不经 installd XPC。
/// ⚠️ entitlement 门禁风险（lsd/containermanagerd）：无公开生态先例，
/// B25-1 ➕ spike 三候选裁决中——本安装器引擎B 路线据此标注【实验性】。
static BOOL EUStandalonePermasignInstall(NSString *appBundlePath, NSString **outInstalledPath, NSError **error)
{
    NSError * (^fail)(NSString *) = ^NSError *(NSString *msg) {
        return [NSError errorWithDomain:EUStandaloneInstallerErrorDomain
                                   code:EUStandaloneErrorPermasignInstallFailed
                               userInfo:@{NSLocalizedDescriptionKey : msg}];
    };

    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
        [appBundlePath stringByAppendingPathComponent:@"Info.plist"]];
    NSString *appId = info[@"CFBundleIdentifier"];
    if (![appId isKindOfClass:[NSString class]] || !appId.length) {
        if (error) *error = fail(@"Info.plist 缺 CFBundleIdentifier");
        return NO;
    }

    // 1. Bundle 容器（MCMAppContainer）
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
        // entitlement 门禁首现点（containermanagerd XPC）——B25-1 ➕ spike 裁决中
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

    // 2. 已装检测（非生态标记且容器非空 → 拒绝覆盖商店应用）
    NSString *markerPath = [bundleContainerPath stringByAppendingPathComponent:@"_TrollStore"];
    NSString *newAppBundlePath = [bundleContainerPath stringByAppendingPathComponent:appBundlePath.lastPathComponent];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:newAppBundlePath] && ![fm fileExistsAtPath:markerPath]) {
        if (error) *error = fail(@"同 bundleID 应用已存在且非巨魔E/巨魔生态安装（拒绝覆盖，防破坏商店应用）");
        return NO;
    }
    if ([fm fileExistsAtPath:newAppBundlePath]) {
        [fm removeItemAtPath:newAppBundlePath error:nil]; // 覆盖安装：先清旧 .app
    }

    // 3. 直拷 .app → Bundle 容器
    NSError *copyError = nil;
    if (![fm copyItemAtPath:appBundlePath toPath:newAppBundlePath error:&copyError]) {
        if (error) *error = fail([NSString stringWithFormat:@".app 拷贝入容器失败：%@",
                                  copyError.localizedDescription ?: @"未知错误"]);
        return NO;
    }

    // 4. `_TrollStore` 标记（TrollStore 生态互认语义）
    if (![fm fileExistsAtPath:markerPath]) {
        if (![[NSData data] writeToFile:markerPath options:0 error:nil]) {
            if (error) *error = fail(@"`_TrollStore` 标记写入失败");
            return NO;
        }
    }

    // 5. 权限修正（两遍法）
    EUStandaloneFixPermissionsOfAppBundle(newAppBundlePath);

    // 6. 注册（失败回滚整个容器：零残留）
    if (!EUStandaloneRegisterAppPath(newAppBundlePath, NO)) {
        [fm removeItemAtPath:bundleContainerPath error:nil];
        if (error) *error = fail(@"LaunchServices 注册失败（lsd XPC entitlement 门禁？B25-1 ➕ spike 裁决中）");
        return NO;
    }

    if (outInstalledPath) *outInstalledPath = newAppBundlePath;
    if (error) *error = nil;
    return YES;
}

#pragma mark - jailed root 化（源 L646-689，原样）

/// iOS 17+ 直接内核写入版（B25-1 ② 判修）：绕过 proc_ucred_update_content 的
/// 17+ setuid-root 子进程协议（jailed 语境无 launchdhook 产物必死）——直接
/// kwrite 本进程 ucred：uid/svuid/svgid/groups[0] → 0 + audit_token 四字补丁。
/// 前置 cr_ref==1（共享 ucred 拒改，防内核态污染）。
static BOOL EUStandaloneJailedRootify(uint64_t selfProc)
{
    if (selfProc == 0) return NO;
    uint64_t ucred = proc_ucred(selfProc);
    if (ucred == 0) return NO;

    if (kread32(ucred + koffsetof(ucred, ref)) != 1) return NO;

    kwrite32(ucred + koffsetof(ucred, svuid), 0);
    kwrite32(ucred + koffsetof(ucred, uid), 0);
    kwrite32(ucred + koffsetof(ucred, svgid), 0);
    kwrite32(ucred + koffsetof(ucred, groups), 0);

    // task_tokens.audit_token 四字补丁（17.0+ proc_ro 域必须：XPC 对端读 audit token
    // 而非实时 ucred，不补则 root 化对守护进程不可见）【源 L674-686】
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

#pragma mark - 引擎 B：免越狱一次性会话（源 L694-856，解耦 #1/#3）

/// 八步零残留管线（B25 契约）：会话→root→staging 解包→helper 快路径→custom 法
/// →CDHash→登记重放表→收尾（清 staging+漏洞清理）。
/// ⚠️ entitlement 门禁风险（v1.2 风险簿首位）未实机裁决——【实验性】。
- (BOOL)installPermasignedAppAtURL:(NSURL *)appURL error:(NSError **)error
{
    NSError * (^fail)(EUStandaloneInstallerErrorCode, NSString *) =
        ^NSError *(EUStandaloneInstallerErrorCode code, NSString *msg) {
        return [NSError errorWithDomain:EUStandaloneInstallerErrorDomain code:code
                               userInfo:@{NSLocalizedDescriptionKey : msg}];
    };

    if (!appURL || ![[NSFileManager defaultManager] fileExistsAtPath:appURL.path]) {
        if (error) *error = fail(EUStandaloneErrorInvalidInput, @"路径不存在");
        return NO;
    }

    // ① 域校验（源 L705-713；C24 矩阵 + 域外降级提示）
    if (![self deviceInCoreTrustDomain]) {
        NSOperatingSystemVersion v = [NSProcessInfo processInfo].operatingSystemVersion;
        NSString *hint = (v.majorVersion >= 17 && v.minorVersion >= 1) || v.majorVersion > 17
            ? @"当前系统 CT 已修复：免越狱永久档不可达（可用容器模式兜底；16.7b/RC/17.0 可用 PC 备份注入档）"
            : @"16.7.x GA 系列 CT 已修复：免越狱永久档不可达（本版本可用容器模式兜底）";
        if (error) *error = fail(EUStandaloneErrorDomainUnsupported, hint);
        return NO;
    }

    // ② helper 快路径：巨魔E 本体已装（镜像表含 role=body 且容器在位）
    //    → 经 URL scheme 移交本体安装（TrollStore 语义）【源 L715-731】
    for (NSDictionary *entry in [self installedApplications]) {
        if ([entry[@"role"] isEqualToString:@"body"] &&
            [[NSFileManager defaultManager] fileExistsAtPath:entry[@"path"]]) {
            NSString *handoff = [NSString stringWithFormat:@"euphoria-trolle://install?url=%@",
                                 [appURL.absoluteString stringByAddingPercentEncodingWithAllowedCharacters:
                                  [NSCharacterSet URLQueryAllowedCharacterSet]]];
            NSURL *url = [NSURL URLWithString:handoff];
            if (url) {
                // B 线修正（2026-09-03）：安装链现于后台串行队列运行，
                // openURL 必须 hop 回主线程（UIKit 线程安全）
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
                });
                EUStandaloneLog(@"本体在位，已移交安装 → %@", appURL.lastPathComponent);
                return YES;
            }
        }
    }

    // ③ 漏洞会话（源 L736-761 对齐，B 线 09-04 修正：kfd KRW 必选 + PPL 可选。
    //    原版 !kernel||!ppl 硬门槛会误杀"纯 KRW 可达"的 A12–A13 kfd 域——
    //    PPL 物理写仅需要时必备，dmaFail 优先带上；解耦 #3 → 独立管理器）
    EUStandaloneExploit *kernel = [EUStandaloneExploitManager sharedManager].preferredKernelExploit;
    EUStandaloneExploit *ppl = [EUStandaloneExploitManager sharedManager].preferredPPLBypass;
    if (!kernel || ![kernel isSupported]) {
        if (error) *error = fail(EUStandaloneErrorSessionFailed,
            @"无可用内核漏洞（kfd 系）——请检查 Frameworks/ 注入与版本域");
        return NO;
    }
    EUStandaloneLog(@"漏洞会话启动：%@(%@)%@…",
        kernel.displayName, kernel.flavorName,
        (ppl && [ppl isSupported])
            ? [NSString stringWithFormat:@" + %@(%@)", ppl.displayName, ppl.flavorName]
            : @"（纯 KRW）");
    void (^sessionTeardown)(void) = ^{
        int r = [[EUStandaloneExploitManager sharedManager] cleanUpExploits];
        EUStandaloneLog(@"漏洞会话清理：%@（残留=%d）", r == 0 ? @"成功" : @"失败", r);
    };
    if ([kernel load] != 0 || [kernel run] != 0) {
        sessionTeardown();
        if (error) *error = fail(EUStandaloneErrorSessionFailed, @"内核漏洞会话失败（kfd）");
        return NO;
    }
    // PPL 可选（主树 L756-761 同款：ppl && isSupported 才挂载）
    if (ppl && [ppl isSupported]) {
        if ([ppl load] != 0 || [ppl run] != 0) {
            sessionTeardown();
            if (error) *error = fail(EUStandaloneErrorSessionFailed, @"PPL 绕过失败（dmaFail）");
            return NO;
        }
    }
    // 注：纯 KRW（无 PPL）在 A12–A13 kfd 路线亦足以完成 ucred root 化；PPL 写仅在
    // 需要物理写路径时必备（dmaFail 优先带上，与越狱链同源）【源 L760-761】

    // ④ root 化（B 线 09-04 补齐主树 L763-781 双分支：iOS 17+ 直接 kwrite ucred；
    //    ≤16.x 走 proc_ucred_update_content 原生路径。独立版此前只有 17+ 分支，
    //    15.0–16.6.1 kfd 域 root 化整体走不通——本补丁闭合）
    uint64_t selfProc = proc_self();
    if (@available(iOS 17.0, *)) {
        if (!EUStandaloneJailedRootify(selfProc)) {
            sessionTeardown();
            if (error) *error = fail(EUStandaloneErrorSessionFailed,
                @"root 化失败（17+ 直接内核写入未生效：ucred 共享或 kwrite 异常）——会话已零残留回滚");
            return NO;
        }
    }
    else {
        // ≤16.x 分支（主树 L774-780 原样）：满长零数组防栈越界读（B25-1 勘误）
        gid_t rootGroups[NGROUPS_MAX] = {0};
        NSString *selfExec = [NSBundle mainBundle].executablePath;
        if (selfProc == 0 || proc_ucred_update_content(selfProc, selfExec.fileSystemRepresentation,
                                                        0, 0, 0, 0, rootGroups) != 0 || getuid() != 0) {
            sessionTeardown();
            if (error) *error = fail(EUStandaloneErrorSessionFailed,
                @"root 化失败（ucred 更新未生效，≤16.x 分支）——会话已零残留回滚");
            return NO;
        }
    }
    EUStandaloneLog(@"root 化完成（uid=%d）——CT custom 法安装开始", getuid());

    // ⑤ staging 解包（源 L795-810 段；libarchive 同函数）
    NSString *stagingDir = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[NSString stringWithFormat:@"trolle-stage-%@", [[NSUUID UUID] UUIDString]]];
    [[NSFileManager defaultManager] createDirectoryAtPath:stagingDir
                            withIntermediateDirectories:YES attributes:nil error:nil];
    if (!EUStandaloneExtractZipWithLibarchive(appURL.path, stagingDir)) {
        [[NSFileManager defaultManager] removeItemAtPath:stagingDir error:nil];
        sessionTeardown();
        if (error) *error = fail(EUStandaloneErrorUnpackFailed, @"IPA 解包失败（libarchive）");
        return NO;
    }

    // ⑥ 定位 Payload/*.app
    NSString *appBundlePath = nil;
    NSString *payloadDir = [stagingDir stringByAppendingPathComponent:@"Payload"];
    for (NSString *item in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:payloadDir error:nil]) {
        if ([item hasSuffix:@".app"]) { appBundlePath = [payloadDir stringByAppendingPathComponent:item]; break; }
    }
    if (!appBundlePath) {
        [[NSFileManager defaultManager] removeItemAtPath:stagingDir error:nil];
        sessionTeardown();
        if (error) *error = fail(EUStandaloneErrorNoPayload, @"IPA 内未找到 Payload/*.app");
        return NO;
    }

    // ⑦ CT custom 法安装（源 L810-830 段；MCMAppContainer 直建容器+直拷+注册字典，
    //    全程不经 installd XPC——本体，_TrollStore 标记，两遍法权限修正）
    NSString *installedPath = nil;
    if (!EUStandalonePermasignInstall(appBundlePath, &installedPath, error)) {
        [[NSFileManager defaultManager] removeItemAtPath:stagingDir error:nil];
        sessionTeardown();
        if (error && !*error) {
            *error = fail(EUStandaloneErrorPermasignInstallFailed, @"CT custom 法安装失败（见日志）");
        }
        return NO;
    }

    // ⑧ CDHash 计算 + 登记重放表（role=body engine=B；源 L830-849 段）
    NSString *execPath = [installedPath stringByAppendingPathComponent:
        [NSDictionary dictionaryWithContentsOfFile:
            [installedPath stringByAppendingPathComponent:@"Info.plist"]][@"CFBundleExecutable"] ?: @""];
    uint8_t cdhash[CS_CDHASH_LEN] = {0};
    NSMutableString *cdhashHex = [NSMutableString new];
    if (execPath.length && EUStandaloneComputeCDHash(execPath, cdhash)) {
        for (int i = 0; i < CS_CDHASH_LEN; i++) [cdhashHex appendFormat:@"%02x", cdhash[i]];
    }
    NSString *bundleID = [NSDictionary dictionaryWithContentsOfFile:
        [installedPath stringByAppendingPathComponent:@"Info.plist"]][@"CFBundleIdentifier"] ?: @"";

    NSMutableArray *newEntries = [[self installedApplications] mutableCopy];
    [newEntries addObject:@{
        @"bundleID" : bundleID,
        @"path" : installedPath,
        @"cdhash" : [cdhashHex copy],
        @"role" : @"body",           // 引擎B 装出的首个应用=巨魔E 本体【源 L842】
        @"engine" : @"B",
        @"installedAt" : @([[NSDate date] timeIntervalSince1970]), // 修复#4：字面量内 double 需装箱
    }];
    // 保存时进程已是 root（会话态），直接落盘【源 L846-849】
    [self saveEntries:newEntries];

    // ⑧' 会话收尾（成功路径：清 staging + 漏洞清理，零残留）
    [[NSFileManager defaultManager] removeItemAtPath:stagingDir error:nil];
    sessionTeardown();
    EUStandaloneLog(@"免越狱安装完成（永久签名，重启可用）");
    return YES;
}

#pragma mark - 引擎 C：容器模式安装侧（源 L869-938，解耦 #1/#5）

/// 免越狱容器化（B26 L1 基线）：无漏洞、全版本域；app 以"插件"形态在容器内跑。
/// 主屏图标=快捷指令+URL scheme（euphoria-trolle://launch?id=<uuid>，LC 实证机制）。
/// 边界（如实）：L1 非"真永久"——宿主签名过期未续签=容器内 app 全灭。
- (BOOL)installApplicationContainerizedAtURL:(NSURL *)appURL error:(NSError **)error
{
    NSError * (^fail)(EUStandaloneInstallerErrorCode, NSString *) =
        ^NSError *(EUStandaloneInstallerErrorCode code, NSString *msg) {
        return [NSError errorWithDomain:EUStandaloneInstallerErrorDomain code:code
                               userInfo:@{NSLocalizedDescriptionKey : msg}];
    };

    if (!appURL || ![[NSFileManager defaultManager] fileExistsAtPath:appURL.path]) {
        if (error) *error = fail(EUStandaloneErrorInvalidInput, @"路径不存在");
        return NO;
    }

    // ① 解包到沙盒容器目录（无 root，无权限问题）【源 L880-892】
    NSString *containersRoot = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/EUTrollEContainers"];
    NSString *uuid = [[NSUUID UUID] UUIDString];
    NSString *containerDir = [containersRoot stringByAppendingPathComponent:uuid];
    NSString *stagingDir = [containerDir stringByAppendingPathComponent:@"staging"];
    [[NSFileManager defaultManager] createDirectoryAtPath:stagingDir
                            withIntermediateDirectories:YES attributes:nil error:nil];
    EUStandaloneLog(@"（容器）解包 IPA（libarchive，免越狱无漏洞通道）…");
    if (!EUStandaloneExtractZipWithLibarchive(appURL.path, stagingDir)) {
        [[NSFileManager defaultManager] removeItemAtPath:containerDir error:nil]; // 零残留
        if (error) *error = fail(EUStandaloneErrorUnpackFailed, @"IPA 解包失败（libarchive）");
        return NO;
    }

    // ② 定位 Payload/*.app → 落位容器目录【源 L894-907】
    NSString *appBundlePath = nil;
    NSString *payloadDir = [stagingDir stringByAppendingPathComponent:@"Payload"];
    for (NSString *item in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:payloadDir error:nil]) {
        if ([item hasSuffix:@".app"]) { appBundlePath = [payloadDir stringByAppendingPathComponent:item]; break; }
    }
    if (!appBundlePath) {
        [[NSFileManager defaultManager] removeItemAtPath:containerDir error:nil];
        if (error) *error = fail(EUStandaloneErrorNoPayload, @"IPA 内未找到 Payload/*.app");
        return NO;
    }
    NSString *finalPath = [containerDir stringByAppendingPathComponent:appBundlePath.lastPathComponent];
    if (![[NSFileManager defaultManager] moveItemAtPath:appBundlePath toPath:finalPath error:nil]) {
        [[NSFileManager defaultManager] removeItemAtPath:containerDir error:nil];
        if (error) *error = fail(EUStandaloneErrorCopyFailed, @"容器落位失败");
        return NO;
    }

    // ③ 读 Info + CDHash（可算则记录；L1→L3 升级即用）【源 L909-921】
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
        [finalPath stringByAppendingPathComponent:@"Info.plist"]];
    NSString *bundleID = info[@"CFBundleIdentifier"] ?: @"";
    NSString *execPath = [finalPath stringByAppendingPathComponent:info[@"CFBundleExecutable"] ?: @""];
    uint8_t cdhash[CS_CDHASH_LEN] = {0};
    NSMutableString *cdhashHex = [NSMutableString new];
    if (execPath.length && EUStandaloneComputeCDHash(execPath, cdhash)) {
        for (int i = 0; i < CS_CDHASH_LEN; i++) [cdhashHex appendFormat:@"%02x", cdhash[i]];
    }

    // ④ 登记重放表（engine=C；镜像表——后续越狱时主树幂等合并升级）【源 L923-934】
    NSMutableArray *entries = [[self installedApplications] mutableCopy];
    [entries addObject:@{
        @"bundleID" : bundleID,
        @"path" : finalPath,
        @"cdhash" : cdhashHex.length ? [cdhashHex copy] : @"",
        @"role" : @"guest",           // 容器内访客应用
        @"engine" : @"C",
        @"container" : uuid,          // 启动引用：euphoria-trolle://launch?id=<uuid>
        @"installedAt" : @([[NSDate date] timeIntervalSince1970]), // 修复#4：字面量内 double 需装箱
    }];
    [self saveEntries:entries];

    EUStandaloneLog(@"（容器）安装完成（L1 基线，%@）——后续越狱时自动升级为满血形态", bundleID);
    return YES;
}

#pragma mark - 卸载（引擎 C 容器条目）

- (BOOL)uninstallContainerizedWithBundleID:(NSString *)bundleID error:(NSError **)error
{
    // 引擎 C 容器条目卸载（源 L276-307 段的容器子集）：删容器目录+移除镜像表条目
    if (!bundleID.length) return NO;
    NSDictionary *target = nil;
    for (NSDictionary *entry in [self installedApplications]) {
        if ([entry[@"bundleID"] isEqualToString:bundleID] && [entry[@"engine"] isEqualToString:@"C"]) {
            target = entry; break;
        }
    }
    if (!target) {
        if (error) *error = [NSError errorWithDomain:EUStandaloneInstallerErrorDomain
                                                 code:EUStandaloneErrorInvalidInput
                                             userInfo:@{NSLocalizedDescriptionKey : @"镜像表未找到该容器条目"}];
        return NO;
    }
    // 修复#14：原实现只删条目 path（=容器内 .app 路径），容器目录整体残留
    //（sandbox Documents/EUTrollEContainers/<uuid>/ 壳+元数据）。正确语义=删容器根
    //（其父目录即 uuid 容器目录，.app 与配套件全在其中）。
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *appPath = target[@"path"];
    NSString *containerUUID = target[@"container"];
    NSString *containerDir = nil;
    if (containerUUID.length) {
        containerDir = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/EUTrollEContainers"]
            stringByAppendingPathComponent:containerUUID];
    }
    // 容器目录在位则整删（防御：path 若不在容器树内则仅删 path 本身，不动其他）
    BOOL removed = NO;
    if (containerDir.length && [fm fileExistsAtPath:containerDir]
        && [appPath hasPrefix:containerDir]) {
        removed = [fm removeItemAtPath:containerDir error:nil];
    } else {
        removed = [fm removeItemAtPath:appPath error:nil];
    }
    NSMutableArray *entries = [[self installedApplications] mutableCopy];
    [entries filterUsingPredicate:[NSPredicate predicateWithFormat:@"bundleID != %@", bundleID]];
    [self saveEntries:entries];
    return removed;
}

@end
