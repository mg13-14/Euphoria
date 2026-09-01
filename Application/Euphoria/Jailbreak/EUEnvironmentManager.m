//
//  EnvironmentManager.m
//  Euphoria
//
//  Created by Lars Fröder on 10.01.24.
//

#import "EUEnvironmentManager.h"
#import "UIImage+JPEG2000.h"

#import <sys/sysctl.h>
#import <sys/mount.h>
#import <sys/utsname.h>
#import <sys/stat.h>
#import <unistd.h>
#import <mach-o/dyld.h>
#import <libgrabkernel2/libgrabkernel2.h>
#import <libjailbreak/info.h>
#import <libjailbreak/codesign.h>
#import <libjailbreak/util.h>
#import <libjailbreak/display.h>
#import <libjailbreak/machine_info.h>
#import <libjailbreak/carboncopy.h>

#import <IOKit/IOKitLib.h>
#import "EUUIManager.h"
#import "EUExploitManager.h"
#import "EUPreferenceManager.h"
#import "NSData+Hex.h"
#import <LocalAuthentication/LocalAuthentication.h>

int reboot3(uint64_t flags, ...);
CFPropertyListRef MGCopyAnswer(CFStringRef);
extern char **environ;

@implementation EUEnvironmentManager

+ (instancetype)sharedManager
{
    static EUEnvironmentManager *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[EUEnvironmentManager alloc] init];
    });
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _bootstrapNeedsMigration = NO;
        _bootstrapper = [[EUBootstrapper alloc] init];
        if ([self isJailbroken]) {
            gSystemInfo.jailbreakInfo.rootPath = strdup(jbclient_get_jbroot() ?: "");
        }
        else if ([self isInstalledThroughTrollStore]) {
            [self locateJailbreakRoot];
        }
    }
    return self;
}

- (NSString *)nightlyHash
{
#ifdef NIGHTLY
    return [NSString stringWithUTF8String:COMMIT_HASH];
#else
    return nil;
#endif
}

- (NSString *)appVersion
{
    return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
}

- (NSString *)appVersionDisplayString
{
    NSString *nightlyHash = [self nightlyHash];
    if (nightlyHash) {
        return [NSString stringWithFormat:@"%@~%@", self.appVersion, [nightlyHash substringToIndex:6]];
    }
    else {
        return [self appVersion];
    }
}

- (NSString *)privatePrebootPath
{
    return @"/private/preboot";
}

- (NSString *)activePrebootPath
{
    NSString *bootManifestString = [NSString stringWithUTF8String:boot_manifest_hash()];
    return [[self privatePrebootPath] stringByAppendingPathComponent:bootManifestString];
}

- (void)locateJailbreakRoot
{
    if (!gSystemInfo.jailbreakInfo.rootPath) {
        NSString *activePrebootPath = [self activePrebootPath];
        
        NSString *randomizedJailbreakPath;
        
        // First attempt at finding jailbreak root, look for Euphoria 2.x path
        for (NSString *subItem in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:activePrebootPath error:nil]) {
            if (subItem.length == 15 && [subItem hasPrefix:@"euphoria-"]) {
                randomizedJailbreakPath = [activePrebootPath stringByAppendingPathComponent:subItem];
                break;
            }
        }
        
        if (!randomizedJailbreakPath) {
            // Second attempt at finding jailbreak root, look for Euphoria 1.x path, but as other jailbreaks use it too, make sure it is Euphoria
            // Some other jailbreaks also commit the sin of creating .installed_euphoria, for these we try to filter them out by checking for their installed_ file
            // If we find this and are sure it's from Euphoria 1.x, rename it so all Euphoria 2.x users will have the same path
            for (NSString *subItem in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:activePrebootPath error:nil]) {
                if (subItem.length == 9 && [subItem hasPrefix:@"jb-"]) {
                    NSString *candidateLegacyPath = [activePrebootPath stringByAppendingPathComponent:subItem];
                    
                    BOOL installedEuphoria = [[NSFileManager defaultManager] fileExistsAtPath:[candidateLegacyPath stringByAppendingPathComponent:@"procursus/.installed_euphoria"]];
                    
                    if (installedEuphoria) {
                        // Hopefully all other jailbreaks that use jb-<UUID>?
                        // These checks exist because of dumb users (and jailbreak developers) creating .installed_euphoria on jailbreaks that are NOT euphoria...
                        BOOL installedNekoJB = [[NSFileManager defaultManager] fileExistsAtPath:[candidateLegacyPath stringByAppendingPathComponent:@"procursus/.installed_nekojb"]];
                        BOOL installedDefinitelyNotAGoodName = [[NSFileManager defaultManager] fileExistsAtPath:[candidateLegacyPath stringByAppendingPathComponent:@"procursus/.xia0o0o0o_jb_installed"]];
                        BOOL installedPalera1n = [[NSFileManager defaultManager] fileExistsAtPath:[candidateLegacyPath stringByAppendingPathComponent:@"procursus/.palecursus_strapped"]];
                        if (installedNekoJB || installedPalera1n || installedDefinitelyNotAGoodName) {
                            continue;
                        }
                        
                        randomizedJailbreakPath = candidateLegacyPath;
                        _bootstrapNeedsMigration = YES;
                        break;
                    }
                }
            }
        }
        
        if (randomizedJailbreakPath) {
            NSString *jailbreakRootPath = [randomizedJailbreakPath stringByAppendingPathComponent:@"procursus"];
            if ([[NSFileManager defaultManager] fileExistsAtPath:jailbreakRootPath]) {
                // This attribute serves as the primary source of what the root path is
                // Anything else in the jailbreak will get it from here
                gSystemInfo.jailbreakInfo.rootPath = strdup(jailbreakRootPath.fileSystemRepresentation);
            }
        }
    }
}

- (NSError *)ensureJailbreakRootExists
{
    NSError *error = nil;

    [self locateJailbreakRoot];

    // DOPACLEAN logic to move a corrupted euphoria directory to a different path to at least make jailbreaking work again
    // if (gSystemInfo.jailbreakInfo.rootPath) {
    //     NSString *randomizedJailbreakPath = [NSString stringWithUTF8String:gSystemInfo.jailbreakInfo.rootPath].stringByDeletingLastPathComponent;
    //     NSString *characterSet = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    //     NSUInteger stringLen = 6;
    //     NSMutableString *randomString = [NSMutableString stringWithCapacity:stringLen];
    //     for (NSUInteger i = 0; i < stringLen; i++) {
    //         NSUInteger randomIndex = arc4random_uniform((uint32_t)[characterSet length]);
    //         unichar randomCharacter = [characterSet characterAtIndex:randomIndex];
    //         [randomString appendFormat:@"%C", randomCharacter];
    //     }
        
    //     NSString *activePrebootPath = [self activePrebootPath];
    //     NSString *orphanedName = [NSString stringWithFormat:@"orphaned-%@", randomString];
    //     NSString *orphanedPath = [activePrebootPath stringByAppendingPathComponent:orphanedName];
    //     [[NSFileManager defaultManager] moveItemAtPath:randomizedJailbreakPath toPath:orphanedPath error:nil];
    // }

    // return [NSError errorWithDomain:@"Cleaned" code:1 userInfo:nil];

    if (!gSystemInfo.jailbreakInfo.rootPath || _bootstrapNeedsMigration) {
        [_bootstrapper ensurePrivatePrebootIsWritable];

        NSString *activePrebootPath = [self activePrebootPath];

        NSString *characterSet = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        NSUInteger stringLen = 6;
        NSMutableString *randomString = [NSMutableString stringWithCapacity:stringLen];
        for (NSUInteger i = 0; i < stringLen; i++) {
            NSUInteger randomIndex = arc4random_uniform((uint32_t)[characterSet length]);
            unichar randomCharacter = [characterSet characterAtIndex:randomIndex];
            [randomString appendFormat:@"%C", randomCharacter];
        }
        
        NSString *randomJailbreakFolderName = [NSString stringWithFormat:@"euphoria-%@", randomString];
        NSString *randomizedJailbreakPath = [activePrebootPath stringByAppendingPathComponent:randomJailbreakFolderName];
        NSString *jailbreakRootPath = [randomizedJailbreakPath stringByAppendingPathComponent:@"procursus"];
        
        if (_bootstrapNeedsMigration) {
            NSString *oldRandomizedJailbreakPath = [[NSString stringWithUTF8String:gSystemInfo.jailbreakInfo.rootPath] stringByDeletingLastPathComponent];
            [[NSFileManager defaultManager] moveItemAtPath:oldRandomizedJailbreakPath toPath:randomizedJailbreakPath error:&error];
        }
        else {
            if (![[NSFileManager defaultManager] fileExistsAtPath:jailbreakRootPath]) {
                [[NSFileManager defaultManager] createDirectoryAtPath:jailbreakRootPath withIntermediateDirectories:YES attributes:nil error:&error];
            }
        }
        
        if (!error) {
            gSystemInfo.jailbreakInfo.rootPath = strdup(jailbreakRootPath.UTF8String);
        }
    }
    
    return error;
}

- (BOOL)isArm64e
{
    cpu_subtype_t cpusubtype = 0;
    size_t len = sizeof(cpusubtype);
    if (sysctlbyname("hw.cpusubtype", &cpusubtype, &len, NULL, 0) == -1) return NO;
    return (cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_ARM64E;
}

- (BOOL)isSPTM
{
    if (@available(iOS 17.0, *)) {
        io_registry_entry_t memory_map = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/chosen/memory-map");
        if (memory_map == IO_OBJECT_NULL)   return NO;

        CFArrayRef keys = (CFArrayRef)IORegistryEntryCreateCFProperty(memory_map, CFSTR(kIORegistryEntryPropertyKeysKey), kCFAllocatorDefault, 0);
        IOObjectRelease(memory_map);
        if (!keys)  return NO;

        CFRange range = CFRangeMake(0, CFArrayGetCount(keys));

        bool isSPTM = CFArrayContainsValue(keys, range, CFSTR("SPTM")) && CFArrayContainsValue(keys, range, CFSTR("TXM"));
        CFRelease(keys);

        return isSPTM;
    }
    return false;
}

- (NSString *)versionSupportString
{
    cpu_subtype_t cpuFamily = 0;
    size_t cpuFamilySize = sizeof(cpuFamily);
    sysctlbyname("hw.cpufamily", &cpuFamily, &cpuFamilySize, NULL, 0);
    
    // R39 用户实机靶场（2026-08-29 11:48 报备）：A13@18.1.1 / A15@15.6.1 / A15@26.5.2 /
    // A17 Pro@17.6.1——覆盖 A12/A13 线（A13 实验性段）、A14~A17 线持久化档甜点区外沿
    // （A17 Pro 17.6.1 在 17.4+ 断链区=L1 会话档测试位）、26.x 线（A15 26.5.2 超 43520
    // 修复点 26.1=无公开链，攻面评审参考位）。实测回归按此四台排。
    if ([self isArm64e]) {
        if (cpuFamily == CPUFAMILY_ARM_VORTEX_TEMPEST || cpuFamily == CPUFAMILY_ARM_LIGHTNING_THUNDER) {
            // R34 支持矩阵诚实化（A 三档定案，00:3x）：实证=15.0~16.5.1（kfd+dmaFail）；
            // 16.6.1+（ClearSword/momentarius/DarkSword 链）代码在树、实机回归未做=实验性。
            // 砍单前此串曾写"18.7.6/26.3.x"（11:55 拉宽）——纸面推断，按用户"只留验证过的"收回。
            // A 11:46 声明窗终定（43520 修复点 18.7.2/26.1 硬边界）：实验性段
            // 上限随 DarkSword 声明窗收敛至 18.7.1+26.0.1，26.1+ 无链。
            return @"iOS 15.0 - 16.5.1（实证）；16.6.1 - 18.7.1 / 26.0 - 26.0.1 实验性（实机验证未完成）";
        }
        else if (![self isSPTM]) {
            // A14（PPL）：L1 会话档 16.6.1-18.7.1 可行（43520 data-only 不需 PPL，
            // A 11:47 认知修正）；持久化档断在 17.4+（Rocket 17.4 被修，无公开替代）。
            return @"iOS 15.0 - 17.3.1（持久化）；16.6.1 - 18.7.1 L1 会话实验性";
        }
        else {
            // A15+（SPTM）：同上——L1 会话档全域可行，持久化档断在 17.4。
            return @"iOS 17.0 - 17.3.1（持久化）；16.6.1 - 18.7.1 / 26.0 - 26.0.1 L1 会话实验性";
        }
    }
    else {
        // arm64：16.6+ 无 PPL bypass（dmaFail≤16.5.1、Titan 限 A14–A17、momentarius 限 A12/A13）→断链
        return @"iOS 15.0 - 16.5.1（实证）；16.6+ 不支持（PPL 断链）";
    }
}

- (BOOL)isInstalledThroughTrollStore
{
    static BOOL trollstoreInstallation = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString* trollStoreMarkerPath = [[[NSBundle mainBundle].bundlePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"_TrollStore"];
        trollstoreInstallation = [[NSFileManager defaultManager] fileExistsAtPath:trollStoreMarkerPath];
    });
    return trollstoreInstallation;
}

- (void)updateJailbreakState
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        char *jbVersionC = NULL;
        _isJailbroken = jbclient_euphoria_is_jailbroken(&jbVersionC);
        if (jbVersionC) {
            _jailbrokenVersion = [NSString stringWithUTF8String:jbVersionC];
            free(jbVersionC);
        }
    });
}

- (BOOL)isJailbroken
{
    [self updateJailbreakState];
    return _isJailbroken;
}

- (void)setJailbroken:(BOOL)jailbroken withVersion:(NSString *)version
{
    _isJailbroken = jailbroken;
    if (_isJailbroken) _jailbrokenVersion = version;
}

- (BOOL)isJailbrokenWithOtherJailbreak
{
    if (![self isJailbroken]) {
        uint32_t csFlags = 0;
        csops(getpid(), CS_OPS_STATUS, &csFlags, sizeof(csFlags));
        
        // Palera1n
        if (csFlags & CS_PLATFORM_BINARY) return YES;
        
        // Older Euphoria build
        if (!access("/usr/lib/systemhook.dylib", F_OK)) return YES;
    }
    return NO;
}

- (NSString *)jailbrokenVersion
{
    [self updateJailbreakState];
    if (!_isJailbroken) return nil;
    return _jailbrokenVersion;
}

- (NSString *)systemVersion
{
    return (__bridge NSString *)MGCopyAnswer((__bridge CFStringRef)@"ProductVersion");
}

- (BOOL)isBootstrapped
{
    return (BOOL)jbinfo(rootPath);
}

// R34 三态（用户 00:19"卡住→退出显示已越狱"配套，汇总员派单①余项）：
// hasLeftoverBootstrap=jbroot 存在（上次装过/半程残留）但当前未越狱——
// UI 据此显示"检测到未完成/残留环境"，引导用户重点越狱按钮幂等续跑，
// 而不是误读为"已越狱"。与 daemon 侧 .bootstrap_complete 双证判定配套：
// jbroot 在 + 标记不在 = 半程（卡死/中断）。
- (BOOL)hasLeftoverBootstrap
{
    return [self isBootstrapped] && ![self isJailbroken];
}

// R37（用户 2026-08-29 00:11 定案，取代 R36 推断式判定）：
// 三态=roothide/rootful 都没勾 → 默认 rootless（无隐藏软件，只有隐/显越狱）；
// 勾 roothide → roothide 模式（隐藏软件双开关）；
// 勾 rootful → 自动捆绑 roothide（服务端 jbsettings 写入侧+daemon 双兜底强制），
//              rootful 会话同样走 roothide 隐藏栈（用户令：rootful 默认为 roothide）。
// 消费方：EUSettingsController（隐藏软件双开关 vs 隐/显越狱单开关的渲染分叉）。
- (BOOL)isRoothideMode
{
    if (![self isJailbroken]) return NO;
    if (jbclient_jbsettings_get_bool("roothideUserEnabled")) return YES;
    // rootful 开着但 roothide 没开=违反联动的存量状态，服务端已兜底关 rootful；
    // 这里按"rootful 捆绑 roothide"语义视作 roothide（隐藏栈在 rootful 下也要在）。
    if (jbclient_jbsettings_get_bool("rootfulUserEnabled")) return YES;
    return NO; // 都没勾=纯 rootless
}

// R38（用户 2026-08-29 11:41 定案）："检测是 rootful 还是普通 roothide，
// 以此决定屏蔽软件的目标方向"——屏蔽软件双形态的 App 侧读出。
// daemon 在每次越狱时按 rootfulWanted 落形态（stealth 3 vs 1，幂等重放），
// 此处读 rootfulUserEnabled 同源判定；cloak 实际 policy（含用户手动覆盖）
// 以 jbsettings cloakStealthLevel 为准。
- (NSUInteger)cloakStealthForm
{
    if (![self isJailbroken]) return 0;
    if (jbclient_jbsettings_get_bool("rootfulUserEnabled")) return 3; // 深档（rootful 态）
    if ([self isRoothideMode]) return 1;                             // 基础档（普通 roothide）
    return 0;                                                        // rootless：隐藏栈未随行
}

- (void)runUnsandboxed:(void (^)(void))unsandboxBlock
{
    if ([self isInstalledThroughTrollStore]) {
        unsandboxBlock();
    }
    else if ([self isJailbroken]) {
        uint64_t labelBackup = 0;
        jbclient_root_set_mac_label(1, -1, &labelBackup);
        unsandboxBlock();
        jbclient_root_set_mac_label(1, labelBackup, NULL);
    }
    else {
        // Hope that we are already unsandboxed
        unsandboxBlock();
    }
}

- (void)runAsRoot:(void (^)(void))rootBlock
{
    uint32_t orgUser = geteuid();
    uint32_t orgGroup = getegid();
    
    if (orgUser == 0 && orgGroup == 0) {
        rootBlock();
        return;
    }

    if (self.isJailbroken) {
        if (jbclient_euphoria_get_root() == 0) {
            rootBlock();
            jbclient_euphoria_drop_root();
        }
    }
}

- (int)spawnJbctlAsRootWithArgs:(NSArray *)args
{
    bool needsLegacySolution = false;
    if (self.jailbrokenVersion) {
        needsLegacySolution = (strcmp(self.jailbrokenVersion.UTF8String, "3.0.5") < 0);
    }

    char **argBuf = malloc((args.count + 4) * sizeof(char *));
    argBuf[0] = strdup(JBROOT_PATH("/basebin/jbctl"));
    int i = 1;
    for (NSString *arg in args) {
        argBuf[i++] = strdup(arg.UTF8String);
    }

    if (!needsLegacySolution) {
        argBuf[i++] = strdup("--waitfor");
        argBuf[i++] = strdup("3");
    }
    argBuf[i++] = NULL;
    
    posix_spawn_file_actions_t act = NULL;
        posix_spawn_file_actions_init(&act);
    posix_spawnattr_t attr = NULL;
    posix_spawnattr_init(&attr);
     
    int waitPipe[2];
    
    if (!needsLegacySolution) {
        pipe(waitPipe);
        posix_spawn_file_actions_adddup2(&act, waitPipe[0], 3);
    }
    else {
        posix_spawnattr_setflags(&attr, POSIX_SPAWN_START_SUSPENDED);
    }

    __block int pid = 0;
    __block int r = -1;

    [self runAsRoot:^{
        [self runUnsandboxed:^{
            r = posix_spawn(&pid, argBuf[0], &act, &attr, (char *const *)argBuf, (char *const *)environ);
            if (needsLegacySolution) {
                // Legacy solution is a gamble, which is why it was removed and superseeded by --waitfor
                // But if jailbroken with <3.0.5, jbctl doesn't support --waitfor yet
                kill(pid, SIGCONT);
            }
        }];
        // We *NEED* to leave this block on iOS 17+ to avoid a panic, --waitfor ensures this always happens
    }];

    posix_spawnattr_destroy(&attr);
    posix_spawn_file_actions_destroy(&act);
    for (int y = 0; y < i; y++) {
        free(argBuf[y]);
    }
    free(argBuf);

    if (!needsLegacySolution) {
        if (r == 0) {
            // We left the root/unsandbox block, now resume jbctl by writing to pipe
            char w = 'w';
            write(waitPipe[1], &w, sizeof(w));
        }

        close(waitPipe[0]);
        close(waitPipe[1]);
    }

    return cmd_wait_for_exit(pid);
}

- (int)runTrollStoreAction:(NSString *)action
{
    if (![self isInstalledThroughTrollStore]) return -1;
    
    uint32_t selfPathSize = PATH_MAX;
    char selfPath[selfPathSize];
    _NSGetExecutablePath(selfPath, &selfPathSize);
    return exec_cmd_root(selfPath, "trollstore", action.UTF8String, NULL);
}

- (void)respring
{
    [self spawnJbctlAsRootWithArgs:@[@"respring"]];
}

- (void)rebootUserspace
{
    [self spawnJbctlAsRootWithArgs:@[@"reboot_userspace"]];
}

- (void)rebuildIconCache
{
    [self spawnJbctlAsRootWithArgs:@[@"rebuild_icon_cache"]];
}

- (void)refreshJailbreakApps
{
    [self runAsRoot:^{
        [self runUnsandboxed:^{
            exec_cmd(JBROOT_PATH("/usr/bin/uicache"), "-a", NULL);
        }];
    }];
}

- (void)unregisterJailbreakApps
{
    [self runAsRoot:^{
        [self runUnsandboxed:^{
            NSArray *jailbreakApps = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:JBROOT_PATH(@"/Applications") error:nil];
            if (jailbreakApps.count) {
                for (NSString *jailbreakApp in jailbreakApps) {
                    NSString *jailbreakAppPath = [JBROOT_PATH(@"/Applications") stringByAppendingPathComponent:jailbreakApp];
                    exec_cmd(JBROOT_PATH("/usr/bin/uicache"), "-u", jailbreakAppPath.fileSystemRepresentation, NULL);
                }
            }
        }];
    }];
}

- (void)reboot
{
    [self runAsRoot:^{
        [self runUnsandboxed:^{
            reboot3(0x8000000000000000, 0);
        }];
    }];
}


- (void)changeMobilePassword:(NSString *)newPassword
{
    [self runAsRoot:^{
        [self runUnsandboxed:^{
            NSString *dashCommand = [NSString stringWithFormat:@"printf \"%%s\\n\" \"%@\" | %@ usermod 501 -h 0", newPassword, JBROOT_PATH(@"/usr/sbin/pw")];
            exec_cmd(JBROOT_PATH("/usr/bin/dash"), "-c", dashCommand.UTF8String, NULL);
        }];
    }];
}

- (NSError*)updateEnvironment
{
    NSString *newBasebinTarPath = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"basebin.tar"];
    int result = jbclient_platform_stage_jailbreak_update(newBasebinTarPath.fileSystemRepresentation);
    if (result == 0) {
        [self rebootUserspace];
        return nil;
    }
    return [NSError errorWithDomain:@"Euphoria" code:result userInfo:nil];
}

- (void)updateJailbreakFromTIPA:(NSString *)tipaPath
{
    [self spawnJbctlAsRootWithArgs:@[@"update", @"tipa", tipaPath]];
}

- (BOOL)isTweakInjectionEnabled
{
    return ![[NSFileManager defaultManager] fileExistsAtPath:JBROOT_PATH(@"/basebin/.safe_mode")];
}

- (void)setTweakInjectionEnabled:(BOOL)enabled
{
    NSString *safeModePath = JBROOT_PATH(@"/basebin/.safe_mode");
    if ([self isJailbroken]) {
        [self runAsRoot:^{
            [self runUnsandboxed:^{
                if (enabled) {
                    [[NSFileManager defaultManager] removeItemAtPath:safeModePath error:nil];
                }
                else {
                    [[NSData data] writeToFile:safeModePath atomically:YES];
                }
            }];
        }];
    }
}

- (BOOL)isIDownloadEnabled
{
    __block BOOL isEnabled = NO;
    [self runAsRoot:^{
        [self runUnsandboxed:^{
            NSDictionary *disabledDict = [NSDictionary dictionaryWithContentsOfFile:@"/var/db/com.apple.xpc.launchd/disabled.plist"];
            NSNumber *idownloaddDisabledNum = disabledDict[@"dev.euphoria.Euphoria.idownloadd"];
            if (idownloaddDisabledNum) {
                isEnabled = ![idownloaddDisabledNum boolValue];
            }
            else {
                isEnabled = NO;
            }
        }];
    }];
    return isEnabled;
}

- (void)setIDownloadEnabled:(BOOL)enabled needsUnsandbox:(BOOL)needsUnsandbox
{
    void (^updateBlock)(void) = ^{
        if (enabled) {
            exec_cmd_trusted(JBROOT_PATH("/usr/bin/launchctl"), "enable", "system/dev.euphoria.Euphoria.idownloadd", NULL);
        }
        else {
            exec_cmd_trusted(JBROOT_PATH("/usr/bin/launchctl"), "disable", "system/dev.euphoria.Euphoria.idownloadd", NULL);
        }
    };

    if (needsUnsandbox) {
        [self runAsRoot:^{
            [self runUnsandboxed:updateBlock];
        }];
    }
    else {
        updateBlock();
    }
}

- (void)setIDownloadLoaded:(BOOL)loaded needsUnsandbox:(BOOL)needsUnsandbox
{
    if (loaded) {
        [self setIDownloadEnabled:loaded needsUnsandbox:needsUnsandbox];
    }
    
    void (^updateBlock)(void) = ^{
        if (loaded) {
            exec_cmd(JBROOT_PATH("/usr/bin/launchctl"), "load", JBROOT_PATH("/basebin/LaunchDaemons/dev.euphoria.Euphoria.idownloadd.plist"), NULL);
        }
        else {
            exec_cmd(JBROOT_PATH("/usr/bin/launchctl"), "unload", JBROOT_PATH("/basebin/LaunchDaemons/dev.euphoria.Euphoria.idownloadd.plist"), NULL);
        }
    };
    
    if (needsUnsandbox) {
        [self runAsRoot:^{
            [self runUnsandboxed:updateBlock];
        }];
    }
    else {
        updateBlock();
    }
    
    if (!loaded) {
        [self setIDownloadEnabled:loaded needsUnsandbox:needsUnsandbox];
    }
}

- (BOOL)isFakelibMounted
{
    struct statfs fsb;
    if (statfs("/usr/lib", &fsb) != 0) return NO;
    return strcmp(fsb.f_mntonname, "/usr/lib") == 0;
}

- (int)setFakelibMounted:(BOOL)mounted
{
    int r = 0;
    if (mounted != [self isFakelibMounted]) {
        NSString *arg = mounted ? @"mount" : @"unmount";
        r = [self spawnJbctlAsRootWithArgs:@[@"internal", @"fakelib", arg]];
    }
    return r;
}

- (int)setPrivatePrebootProtected:(BOOL)protected
{
    NSString *arg = protected ? @"activate" : @"deactivate";
    return [self spawnJbctlAsRootWithArgs:@[@"internal", @"protection", arg]];
}

- (BOOL)isJailbreakHidden
{
    return ![[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"];
}

- (void)setJailbreakHidden:(BOOL)hidden
{
    if (hidden && ![self isJailbroken] && geteuid() != 0) {
        [self runTrollStoreAction:@"hide-jailbreak"];
        return;
    }
    
    void (^actionBlock)(void) = ^{
        BOOL alreadyHidden = [self isJailbreakHidden];
        if (hidden != alreadyHidden) {
            if (hidden) {
                if ([self isJailbroken]) {
                    [self unregisterJailbreakApps];
                    [self setPrivatePrebootProtected:NO];
                    [self setFakelibMounted:NO];
                    jbclient_platform_set_systemwide_domain_enabled(false);
                }
                [[NSFileManager defaultManager] removeItemAtPath:@"/var/jb" error:nil];
            }
            else {
                [[NSFileManager defaultManager] createSymbolicLinkAtPath:@"/var/jb" withDestinationPath:JBROOT_PATH(@"/") error:nil];
                if ([self isJailbroken]) {
                    jbclient_platform_set_systemwide_domain_enabled(true);
                    [self setFakelibMounted:YES];
                    [self setPrivatePrebootProtected:YES];
                    [self refreshJailbreakApps];
                }
            }
        }
    };
    
    if ([self isJailbroken]) {
        [self runAsRoot:^{
            [self runUnsandboxed:actionBlock];
        }];
    }
    else {
        actionBlock();
    }
}

- (NSString *)accessibleKernelPath
{
    if ([self isInstalledThroughTrollStore] || getuid() == 0) {
        NSString *kernelcachePath = [[self activePrebootPath] stringByAppendingPathComponent:@"System/Library/Caches/com.apple.kernelcaches/kernelcache"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:kernelcachePath]) {
            return kernelcachePath;
        }
        return @"/System/Library/Caches/com.apple.kernelcaches/kernelcache";
    }
    else {
        NSString *kernelInApp = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"kernelcache"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:kernelInApp]) {
            return kernelInApp;
        }
        
        [[EUUIManager sharedInstance] sendLog:@"Downloading Kernel" debug:NO];
        NSString *kernelcachePath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/kernelcache"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:kernelcachePath]) {
            if (grab_images([NSHomeDirectory() stringByAppendingPathComponent:@"Documents"]) == false) return nil;
        }
        return kernelcachePath;
    }
}

- (NSString *)accessibleSPTMPath
{
    NSString *sptmInAppPath = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"sptm.img4"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:sptmInAppPath]) {
        return sptmInAppPath;
    }
    
    NSString *sptmInDocsPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/sptm.img4"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:sptmInDocsPath]) {
        return sptmInDocsPath;
    }
    
    sptmInDocsPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/sptm.im4p"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:sptmInDocsPath]) {
        return sptmInDocsPath;
    }

    if ([self isInstalledThroughTrollStore] || getuid() == 0) {
        NSString *sptmPath = [[self activePrebootPath] stringByAppendingPathComponent:@"/usr/standalone/firmware/FUD/Ap,SecurePageTableMonitor.img4"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:sptmPath]) {
            return sptmPath;
        }
    }

    return nil;
}

- (NSString *)accessibleTXMPath
{
    NSString *txmInAppPath = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"txm.img4"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:txmInAppPath]) {
        return txmInAppPath;
    }
    
    NSString *txmInDocsPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/txm.img4"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:txmInDocsPath]) {
        return txmInDocsPath;
    }
    
    txmInDocsPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/txm.im4p"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:txmInDocsPath]) {
        return txmInDocsPath;
    }

    if ([self isInstalledThroughTrollStore] || getuid() == 0) {
        NSString *txmPath = [[self activePrebootPath] stringByAppendingPathComponent:@"/usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:txmPath]) {
            return txmPath;
        }
    }

    return nil;
}


- (BOOL)isPACBypassRequired
{
    if (![self isArm64e]) return NO;
    
    if (@available(iOS 15.2, *)) {
        return NO;
    }
    return YES;
}

- (BOOL)isPPLBypassRequired
{
    return [self isArm64e];
}

- (BOOL)isSupported
{
    //cpu_subtype_t cpuFamily = 0;
    //size_t cpuFamilySize = sizeof(cpuFamily);
    //sysctlbyname("hw.cpufamily", &cpuFamily, &cpuFamilySize, NULL, 0);
    //if (cpuFamily == CPUFAMILY_ARM_TYPHOON) return false; // A8X is unsupported for now (due to 4k page size)
    
    EUExploitManager *exploitManager = [EUExploitManager sharedManager];
    if ([exploitManager availableExploitsForType:EXPLOIT_TYPE_KERNEL].count) {
        if (![self isPACBypassRequired] || [exploitManager availableExploitsForType:EXPLOIT_TYPE_PAC].count) {
            if (![self isPPLBypassRequired] || [exploitManager availableExploitsForType:EXPLOIT_TYPE_PPL].count) {
                return true;
            }
        }
    }
    
    return false;
}

- (BOOL)deviceSupportsFaceID
{
    if (![LAContext class]) return NO;

    LAContext *myContext = [[LAContext alloc] init];
    NSError *authError = nil;
    if (![myContext canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&authError]) {
        NSLog(@"%@", [authError localizedDescription]);
        return NO;
    }

    return myContext.biometryType == LABiometryTypeFaceID;
}

- (BOOL)deviceSupportsLandscapeBootLogo
{
    struct utsname u;
    uname(&u);
    const char *ipadString = "iPad";

    bool isPad = strncmp(u.machine, ipadString, strlen(ipadString)) == 0;
    return isPad && [self deviceSupportsFaceID];
}

- (NSError *)prepareBootstrap
{
    __block NSError *errOut;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [_bootstrapper prepareBootstrapWithCompletion:^(NSError *error) {
        errOut = error;
        dispatch_semaphore_signal(sema);
    }];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    return errOut;
}

- (NSError *)finalizeBootstrap
{
    return [_bootstrapper finalizeBootstrap];
}

- (NSError *)deleteBootstrap
{
    if (![self isJailbroken] && getuid() != 0) {
        int r = [self runTrollStoreAction:@"delete-bootstrap"];
        if (r != 0) {
            // TODO: maybe handle error
        }
        return nil;
    }
    else if ([self isJailbroken]) {
        __block NSError *error;
        [self runAsRoot:^{
            [self runUnsandboxed:^{
                error = [self->_bootstrapper deleteBootstrap];
            }];
        }];
        return error;
    }
    else {
        // Let's hope for the best
        return [_bootstrapper deleteBootstrap];
    }
}

- (NSError *)reinstallPackageManagers
{
    __block NSError *error;
    [self runAsRoot:^{
        [self runUnsandboxed:^{
            error = [self->_bootstrapper installPackageManagers];
        }];
    }];
    return error;
}

- (NSError *)updateBootLogo
{
    const char *bootLogoPath = JBROOT_PATH("/basebin/bootlogo.jp2");
    if ([[EUPreferenceManager sharedManager] boolPreferenceValueForKey:@"bootlogoEnabled" fallback:YES]) {
        UIImage *bootLogoImage;

        if ([[EUPreferenceManager sharedManager] boolPreferenceValueForKey:@"customBootlogoEnabled" fallback:NO]) {
            bootLogoImage = [NSClassFromString(@"UIImage") imageWithContentsOfFile:[EUUIManager sharedInstance].bootlogoPath];
        }

        if (!bootLogoImage) {
            bootLogoImage = [[EUUIManager sharedInstance] renderBootLogo];
        }

        [self runAsRoot:^{
            [self runUnsandboxed:^{
                unlink(bootLogoPath);
                [[bootLogoImage jp2DataWithCompressionQuality:0.9] writeToFile:[NSString stringWithUTF8String:bootLogoPath] atomically:NO];
            }];
        }];

        return nil;
    }
    else {
        [self runAsRoot:^{
            [self runUnsandboxed:^{
                unlink(bootLogoPath);
            }];
        }];
        return nil;
    }
}

@end
