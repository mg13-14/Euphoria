#include <stdio.h>
#include <stdlib.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <mach-o/getsect.h>
#include <dlfcn.h>
#include <sys/stat.h>
#include <paths.h>
#include <util.h>
#include <ptrauth.h>
#include <pthread.h>
#include <sys/proc_info.h>
#include <libproc.h>
#include <copyfile.h>

#import "krw-corellium.h"

#import <EUJailbreaker.h>
#import <EUBootstrapper.h>
#import <EUEnvironmentManager.h>
#import <libjailbreak/libjailbreak.h>
#import <libjailbreak/basebin_gen.h>
#import <libjailbreak/kernel.h>
#import <libjailbreak/util.h>
#import <libjailbreak/primitives.h>
#import <libjailbreak/translation.h>
#import <libjailbreak/signatures.h>
#import <libjailbreak/trustcache.h>
#import <libjailbreak/primitives_IOSurface.h>
#import <libjailbreak/physrw.h>
#import <libjailbreak/physrw_pte.h>
#import <libjailbreak/info.h>
#import <libjailbreak/jbserver.h>
#import <libjailbreak/rootful.h>
#import <libjailbreak/cloak.h>
#import <libjailbreak/aegis.h>

void uart_printf(const char *format, ...)
{
        va_list args;
        va_start(args, format);
        vprintf(format, args);
        va_end(args);
}

int reboot3(uint64_t flags, ...);
#define RB2_USERREBOOT (0x2000000000000000llu)

EUJailbreaker *gJb;

@interface EUJailbreaker (Private)
- (NSError *)showNonDefaultSystemApps;
- (NSError *)ensureDevModeEnabled;
- (NSError *)gatherSystemInformation;
- (NSError *)loadBasebinTrustcache;
- (NSError *)injectLaunchdHook;
- (NSError *)applyProtection;
- (NSError *)createFakeLib;
@end

void init_libjailbreak(void)
{       
        int r = corellium_krw_init();
        if (r != 0) {
                printf("Failed initializing krw: %d\n", r);
                exit(-1);
        }

        jbinfo_initialize_boot_constants();
        libjailbreak_translation_init();

        printf("Transferring primitive... "); fflush(stdout); usleep(1000);
        r = libjailbreak_physrw_pte_init(false, 0);
        if (r == 0) {
                printf("OK\n"); fflush(stdout); usleep(1000);
        }
        else {
                printf("Failed!\n"); fflush(stdout); usleep(1000);
                exit(-1);
        }
        usleep(1000);

#if BUILD_STANDALONE
        signal_krw_done();
#endif

        libjailbreak_IOSurface_primitives_init();
}

void install_basebin_gen(void)
{
        printf("Installing basebin...\n"); fflush(stdout); usleep(1000);

        NSString *usrLibPath = @"/usr/lib";
        NSString *existingBasebin = JBROOT_PATH(@"/basebin");
        NSString *targetBasebin = existingBasebin;

        int r = basebin_generate_internal(usrLibPath, existingBasebin, targetBasebin, false);
        if (r != 0) {
                printf("Failed installing basebin: %d\n", r); fflush(stdout); usleep(1000);
                exit(-1);
        }
}

void activate_basebin(NSString *basebinPath)
{
        printf("Activating %s basebin...\n", basebinPath.fileSystemRepresentation); fflush(stdout); usleep(1000);

        NSString *fakelibDyldPath = [basebinPath stringByAppendingPathComponent:@".fakelib/dyld"];

        cdhash_t *cdhashes = NULL;
        uint32_t cdhashesCount = 0;
        file_collect_untrusted_cdhashes_by_path(fakelibDyldPath.fileSystemRepresentation, &cdhashes, &cdhashesCount);
        if (cdhashesCount != 1) {
                printf("Activating basebin failed: cdhashesCount != 1\n");
                exit(-1);
        }
        
        trustcache_file_v1 *dyldTCFile = NULL;
        int r = trustcache_file_build_from_cdhashes(cdhashes, cdhashesCount, &dyldTCFile);
        free(cdhashes);
        if (r == 0) {
                r = trustcache_file_upload_with_uuid(dyldTCFile, DYLD_TRUSTCACHE_UUID);
                free(dyldTCFile);
                if (r != 0) {
                        printf("Activating basebin failed: trustcache_file_upload_with_uuid returned %d\n", r);
                        exit(-1);
                }
        }
        else {
                printf("Activating basebin failed: trustcache_file_build_from_cdhashes returned %d\n", r);
                exit(-1);
        }

        r = [[EUEnvironmentManager sharedManager] setFakelibMounted:YES];
        if (r != 0) {
                printf("Activating basebin failed: setFakelibMounted returned %d\n", r);
                exit(-1);
        }

        printf("Activated %s basebin!\n", basebinPath.fileSystemRepresentation); fflush(stdout); usleep(1000);
}

void find_offsets(void)
{
        NSError *error = [gJb gatherSystemInformation];
        if (error) {
                printf("offset finding failed with %s\n", error.description.UTF8String);
                exit(-1);
        }
}

void fix_non_default_apps(void)
{
        printf("Making non default system apps visible... "); fflush(stdout); usleep(1000);
        NSError *error = [gJb showNonDefaultSystemApps];
        if (error) {
                printf("\nMaking non default system apps visible failed: %s\n", error.description.UTF8String); fflush(stdout); usleep(1000);
                exit(-1);
        }
        printf("OK\n"); fflush(stdout); usleep(1000);
}

void ensure_dev_mode_enabled(void)
{
        printf("Ensuring dev mode enabled... "); fflush(stdout); usleep(1000);
        NSError *error = [gJb ensureDevModeEnabled];
        if (error) {
                printf("\nEnsuring dev mode enabled failed: %s\n", error.description.UTF8String); fflush(stdout); usleep(1000);
                exit(-1);
        }
        printf("OK\n"); fflush(stdout); usleep(1000);
}

void ensure_jailbreak_root_exists(void)
{
        printf("Ensuring jailbreak root existance... "); fflush(stdout); usleep(1000);
        gSystemInfo.jailbreakInfo.rootPath = NULL;
        NSError *error = [[EUEnvironmentManager sharedManager] ensureJailbreakRootExists];
        if (error) {
                printf("\nEnsuring jailbreak root existance failed: %s\n", error.description.UTF8String); fflush(stdout); usleep(1000);
                exit(-1);
        }
        printf("OK\n"); fflush(stdout); usleep(1000);
}

void prepare_bootstrap(void)
{
        printf("Preparing bootstrap... "); fflush(stdout); usleep(1000);
        NSError *error = [[EUEnvironmentManager sharedManager] prepareBootstrap];
        if (error) {
                printf("\nPreparing bootstrap failed: %s\n", error.description.UTF8String); fflush(stdout); usleep(1000);
                exit(-1);
        }
        printf("OK\n"); fflush(stdout); usleep(1000);
}

void update_var_jb_symlink(void)
{
        printf("Updating /var/jb symlink... "); fflush(stdout); usleep(1000);
        EUBootstrapper *bootstrapper = [[EUBootstrapper alloc] init];
        NSError *error = [bootstrapper updateVarJbSymlink];
        if (error) {
                printf("\nUpdating /var/jb symlink failed: %s\n", error.description.UTF8String); fflush(stdout); usleep(1000);
                exit(-1);
        }
        printf("OK\n");
}

void load_basebin_trustcache(void)
{
        printf("Loading BaseBin Trustcache... "); fflush(stdout); usleep(1000);
        NSError *error = [gJb loadBasebinTrustcache];
        if (error) {
                printf("\nLoading basebin trustcache failed: %s\n", error.description.UTF8String); fflush(stdout); usleep(1000);
                exit(-1);
        }
        printf("OK\n"); fflush(stdout); usleep(1000);
}

void inject_launchd_hook(void)
{
        printf("Injecting launchd hook... "); fflush(stdout); usleep(1000);
        NSError *error = [gJb injectLaunchdHook];
        if (error) {
                printf("\nInjecting launchd hook failed: %s\n", error.description.UTF8String); fflush(stdout); usleep(1000);
                exit(-1);
        }
        printf("OK\n");
}

void apply_preboot_protection(void)
{
        printf("Applying protection... "); fflush(stdout); usleep(1000);
        NSError *error = [gJb applyProtection];
        if (error) {
                printf("\nApplying protection failed: %s\n", error.description.UTF8String); fflush(stdout); usleep(1000);
                exit(-1);
        }
        printf("OK\n");
}

int install_package(NSString *packagePath)
{
        return exec_cmd_trusted(JBROOT_PATH("/usr/bin/dpkg"), "-i", packagePath.UTF8String, NULL);
}

void load_var_jb_daemons(void)
{
        // For some reason, we cannot run 'launchctl load' from the stage2 dropbear environment
        // I spent a lot of time figuring out why and it's something related to us being considered the wrong session / domain
        // No clue how to fix that, but I also figured out that 'launchctl bootstrap system' works...
        // Supposedly because this command allows us to manually specifiy a session / domain (which in this case is 'system')
        exec_cmd_trusted("/var/jb/usr/bin/launchctl", "bootstrap", "system", "/var/jb/Library/LaunchDaemons", NULL);
}

void install_builtin_packages(void)
{
        NSURL *packageDirURL = [NSURL fileURLWithPath:JBROOT_PATH(@"/prep")];
        if (![packageDirURL checkResourceIsReachableAndReturnError:nil]) {
                packageDirURL = [NSURL fileURLWithPath:[[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"Packages"]];
        }
        if ([packageDirURL checkResourceIsReachableAndReturnError:nil]) {
                NSArray<NSURL *> *packageURLs = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:packageDirURL includingPropertiesForKeys:nil options:0 error:nil];
                for (NSURL *packageURL in packageURLs) {
                        int r = install_package(packageURL.path);
                        if (r != 0) {
                                printf("WARNING: Failed to install %s (%d)\n", packageURL.path.fileSystemRepresentation, r);
                        }
                }
                [[NSFileManager defaultManager] removeItemAtURL:packageDirURL error:nil];
                if (@available(iOS 19.0, *)) {
                        // If we just installed prep packages on iOS 26+, load daemons now
                        // This wasn't working before, since launchctl had to be updated first
                        load_var_jb_daemons();
                }
        }
}

void finalize_bootstrap_if_needed(bool *finalized)
{
        char *pathBackup = getenv("PATH") ? strdup(getenv("PATH")) : NULL;
        char *shellBackup = getenv("SHELL") ? strdup(getenv("SHELL")) : NULL;

        setenv("NO_PASSWORD_PROMPT", "1", 1);
        setenv("PATH", "/sbin:/bin:/usr/sbin:/usr/bin:/var/jb/sbin:/var/jb/bin:/var/jb/usr/sbin:/var/jb/usr/bin", 1);
        setenv("TERM", "xterm-256color", 1);
        setenv("SHELL", "/var/jb/bin/sh", 1);

        if ([[NSFileManager defaultManager] fileExistsAtPath:JBROOT_PATH(@"/prep_bootstrap.sh")]) {
                printf("Running prep_bootstrap script...\n");
                int r = exec_cmd_trusted(JBROOT_PATH("/bin/sh"), JBROOT_PATH("/prep_bootstrap.sh"), NULL);
                if (r != 0) {
                        printf("prep_bootstrap failed: %d\n", r);
                        exit(-1);
                }
                else {
                        if (finalized) *finalized = true;
                }
        }

        install_builtin_packages();

        unsetenv("NO_PASSWORD_PROMPT");
        unsetenv("TERM");
        if (pathBackup) {
                setenv("PATH", pathBackup, 1);
                free(pathBackup);
        }
        else {
                unsetenv("PATH");
        }
        if (shellBackup) {
                setenv("SHELL", shellBackup, 1);
                free(shellBackup);
        }
        else {
                unsetenv("SHELL");
        }
}

void print_existing_procs(void)
{
        int proccount = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
        if (proccount == 0) return;

        pid_t *pids = malloc(proccount * sizeof(pid_t));
        proc_listpids(PROC_ALL_PIDS, 0, pids, proccount);

        for (int i = 0; i < proccount; i++) {
                pid_t pid = pids[i];

                char pidPath[4*MAXPATHLEN];
                if (proc_pidpath(pid, pidPath, sizeof(pidPath)) <= 0) {
                        continue;
                }

                uint64_t proc = proc_find(pid);
                if (!proc) continue;
                uint64_t ucred = proc_ucred(proc);

                printf("%d: %s [proc=%#llx, ucred=%#llx]\n", pid, pidPath, proc, ucred);
        }
}

void activate_environment(bool applyProtection, bool prepareBootstrap)
{
        find_offsets();
        init_libjailbreak();

        fix_non_default_apps();

        ensure_dev_mode_enabled();

        ensure_jailbreak_root_exists();

        if (prepareBootstrap) {
                prepare_bootstrap();
        }
        else {
                update_var_jb_symlink();
        }

        load_basebin_trustcache();

        inject_launchd_hook();
        
        if (applyProtection) {
                apply_preboot_protection();
        }
}

// Forward bootstrapfs engine stage events to the App live log.
// The App's stdout reader parses "[STAGE] {json}" lines to drive the
// rootful progress page (docs/06, T14/T15 contract).
static void euphoria_rootful_progress(const char *jsonLine, void *ctx)
{
        (void)ctx;
        printf("[STAGE] %s\n", jsonLine);
        fflush(stdout);
}

void activate_rootful_and_cloak(void)
{
        // Euphoria extension: rootful mode (in-memory rootfs remount + overlay
        // fallback) followed by cloak activation (stealth).
        //
        // User hard requirement (2026-08-25 17:33 + 17:35): on A12/A13 @
        // iOS 15.0-18.7.1 rootful and the hidden environment are DEFAULT ON
        // (R4: cloak rides along everywhere rootful does);
        // explicit opt-out is possible through marker files:
        //   /basebin/.rootful_disabled  -> stay rootless even on the matrix
        //   /basebin/.cloak_disabled    -> keep the environment visible
        // Outside the matrix the default stays 1:1 with the upstream rootless
        // flow and hiding is left to the roothide default chain (App layer);
        // the old opt-in markers (.rootful_enabled / .cloak_enabled) still work
        // there for experimentation.

        // User toggle semantics (2026-08-26 17:27):
        //   rootfulUserEnabled = false (DEFAULT) -> roothide mode:
        //       rootless jailbreak + cloak/aegis hiding (self-developed
        //       roothide equivalent)
        //   rootfulUserEnabled = true  -> rootful + roothide:
        //       rootful engine (fakefs primary / remount+overlay fallback)
        //       AND the full hiding stack, only on A12/A13 @ 16.6.1-18.7.1
        // The App Settings UI flips rootfulUserEnabled through the
        // jbsettings XPC domain; the jailbreak flow below branches on it,
        // so the two modes run genuinely different code paths.

        bool supported = rootful_supported_configuration();
        bool rootfulToggle = jbclient_jbsettings_get_bool("rootfulUserEnabled");
        // R37（用户 2026-08-29 00:11 定案）：roothide 是 rootful 的前置——
        // "选了 rootful 自动选 roothide；关了 roothide 就不能开 rootful"。
        // 服务端 jbsettings 写入侧已兜底联动，这里对存量状态再校验一次。
        bool roothideToggle = jbclient_jbsettings_get_bool("roothideUserEnabled");
        if (rootfulToggle && !roothideToggle) {
                printf("Rootful: roothide toggle is off -> rootful force-disabled (user rule 2026-08-29)\n");
                rootfulToggle = false;
        }
        bool rootfulWanted = supported && rootfulToggle
                && (access(JBROOT_PATH("/basebin/.rootful_disabled"), F_OK) != 0);
        // Hiding (the "roothide" leg) is wanted in BOTH modes and on every
        // supported configuration; only explicit marker files can opt out.
        bool cloakWanted = (access(JBROOT_PATH("/basebin/.cloak_disabled"), F_OK) != 0);
        bool aegisWanted = (access(JBROOT_PATH("/basebin/.aegis_disabled"), F_OK) != 0);

        // If the user turned the rootful toggle on but this device is outside
        // the A12/A13 @ 16.6.1-18.7.1 matrix, say so explicitly and continue
        // in roothide mode (the App UI also greys the toggle out).
        if (rootfulToggle && !supported) {
                printf("Rootful: toggle is on but this device is outside the supported matrix (need A12/A13, iOS 16.6.1 - 18.7.1); continuing in roothide mode\n");
        }

        if (rootfulWanted) {
                {
                        rootful_status_t status = { 0 };
                        int r = rootful_enable_ex(true, euphoria_rootful_progress, NULL, &status);
                        if (r == 0) {
                                printf("Rootful: enabled (root RW: %s, overlays: %s)\n",
                                        status.rootMountedRW ? "yes" : "no",
                                        status.overlayActive ? "yes" : "no");
                        }
                        else {
                                printf("Rootful: enable failed (%s)\n", status.lastError[0] ? status.lastError : strerror(r));
                        }
                }
        }

        if (cloakWanted) {
                if (cloak_enable() == 0) {
                        // cloakd (loaded through the basebin LaunchDaemons directory)
                        // will bring up the cover mount within seconds and report back
                        // R38（用户 2026-08-29 11:41 定案）：屏蔽软件双形态——
                        //   深档（rootful 态）：stealthLevel=3+三 hide 全开。
                        //     rootful 挂载面更大（fakefs/overlay 六目录），检测面也更大，
                        //     全 hide+激进 stealth（getfsstat 白名单外的挂载全隐）。
                        //   基础档（普通 roothide）：stealthLevel=1+三 hide 全开。
                        //     jbroot/bind 隐藏足够，挂载白名单宽松（系统卷正常露出）。
                        // 形态由 rootfulWanted 决定（rootful 捆绑 roothide，R37 联动），
                        // 每次越狱重放（幂等），用户手动 set_options 仍可覆盖。
                        cloak_policy_t cloakPolicy = { 0 };
                        cloak_get_policy(&cloakPolicy);
                        cloakPolicy.hideMounts      = true;
                        cloakPolicy.hideCredentials = true;
                        cloakPolicy.hideTrustcache  = true;
                        cloakPolicy.stealthLevel    = rootfulWanted ? 3 : 1;
                        // R40（用户 2026-08-29 17:00）：黑名单制默认开——拉黑的 app
                        // 检测不到越狱；名单外（文件管理器等越狱生态工具）正常可见。
                        cloakPolicy.blacklistMode   = true;
                        if (cloak_set_options(&cloakPolicy) == 0) {
                                printf("Cloak: enabled (%s form, stealth %llu)\n",
                                        rootfulWanted ? "rootful/deep" : "roothide/basic",
                                        (unsigned long long)cloakPolicy.stealthLevel);
                        }
                        else {
                                printf("Cloak: enabled (form set failed, defaults)\n");
                        }
                }
                else {
                        printf("Cloak: enable failed\n");
                }
        }

        if (aegisWanted) {
                if (aegis_enable() == 0) {
                        // aegisd (loaded through the basebin LaunchDaemons directory)
                        // brings up the cover mount and owns the per-app policy file
                        printf("Aegis: enabled (per-app shielding ready)\n");
                }
                else {
                        printf("Aegis: enable failed\n");
                }
        }
}

void install_euphoria(void)
{
        activate_environment(false, true);

        install_basebin_gen();
        activate_basebin(JBROOT_PATH(@"/basebin"));

        // Now that fakelib is up, we want to make systemhook inject into any binary we spawn
        setenv("DYLD_INSERT_LIBRARIES", "/usr/lib/systemhook.dylib", 1);

        finalize_bootstrap_if_needed(NULL);
        load_var_jb_daemons();

        activate_rootful_and_cloak();

        printf("Euphoria installed!\n");
}

void install_euphoria_from_tarball(const char *tarballPath, const char *bootstrapPath)
{
        [[NSFileManager defaultManager] removeItemAtPath:@"/private/preboot/euphoria_tmp" error:nil];
        [[NSFileManager defaultManager] createDirectoryAtPath:@"/private/preboot/euphoria_tmp" withIntermediateDirectories:NO attributes:nil error:nil];
        libarchive_unarchive(tarballPath, "/private/preboot/euphoria_tmp");
        if (bootstrapPath) {
                [[NSFileManager defaultManager] copyItemAtPath:[NSString stringWithUTF8String:bootstrapPath] toPath:@"/private/preboot/euphoria_tmp/bootstrap_1900.tar.zst" error:nil];
        }

        const char *newPath = "/private/preboot/euphoria_tmp/euphoria";
        extern char **environ;
        char *argv[] = (char *[]){
                (char *)newPath,
                (char *)"install",
                NULL,
        };
        execve(newPath, argv, environ);
}

void activate_euphoria(void)
{
        // R34：事务式越狱标记——流程起点清标记（半程=未越狱，可幂等重跑）
        unlink(JBROOT_PATH("/basebin/.bootstrap_complete"));

        activate_environment(true, false);
        activate_basebin(JBROOT_PATH(@"/basebin"));

        // Now that fakelib is up, we want to make systemhook inject into any binary we spawn
        setenv("DYLD_INSERT_LIBRARIES", "/usr/lib/systemhook.dylib", 1);

        finalize_bootstrap_if_needed(NULL);
        load_var_jb_daemons();

        activate_rootful_and_cloak();

        // R34：全流程（bootstrap→守护进程→rootful/cloak）走完才打完成标记；
        // launchdhook 的 is_jailbroken 判定要求 .version + .bootstrap_complete 双证。
        // 卡死/半途退出的会话不会再显示"已越狱"假状态（用户 00:19 实锤修复）。
        {
                NSString *marker = @(JBROOT_PATH("/basebin/.bootstrap_complete"));
                if (![[NSFileManager defaultManager] createFileAtPath:marker
                                                             contents:[@"1" dataUsingEncoding:NSUTF8StringEncoding]
                                                           attributes:nil]) {
                        printf("WARNING: failed to write .bootstrap_complete marker\n");
                }
        }

        printf("Euphoria activated, see you on the other side!\n");
}

int main(int argc, char* argv[])
{
        gJb = [[EUJailbreaker alloc] init];

        if (argc >= 2) {
                if (!strcmp(argv[1], "install")) {
                        if (argc >= 3) {
                                const char *bootstrapPath = argc >= 4 ? argv[3] : NULL;
                                install_euphoria_from_tarball(argv[2], bootstrapPath);
                        }
                        else {
                                install_euphoria();
                        }
                }
                else if (!strcmp(argv[1], "activate")) {
                        activate_euphoria();
                }
        }

        return 0;
}