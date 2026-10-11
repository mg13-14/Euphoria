#include <stdio.h>
#include <stdint.h>
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

// Returns 0 on success, -1 when the run was explicitly REJECTED (device
// outside the rootful support matrix — see D1 below).
int activate_rootful_and_cloak(void)
{
        // Fixed-rootful rewrite (2026-10-11, user decision: "固定 rootful，
        // 砍无根，保留隐藏"): this build is a rootful-ONLY build. The rootless
        // jailbreak path and the roothide (rootless+hiding) mode have been
        // removed by design. What survives:
        //   - rootful engine: fakefs primary / remount+overlay fallback,
        //     only on the A12/A13 @ iOS 16.6.1-18.7.1 support matrix;
        //   - the hidden environment (cloak + aegis) rides along ALWAYS
        //     (R4), with deny-by-default shielding (list = trust whitelist);
        //   - marker files stay as the operator escape hatches:
        //       /basebin/.rootful_disabled -> emergency rootless leg
        //       /basebin/.cloak_disabled   -> keep the environment visible
        //       /basebin/.aegis_disabled   -> disable per-app shielding
        //
        // D1 (decision, 2026-10-11): devices outside the matrix are REFUSED
        // with an explicit error. The rootless fallback ("silently degrade
        // to roothide") no longer exists, so "continue" would mean jail
        // breaking against the user's contract ("越狱就是有根"). The refusal
        // MUST happen here in the daemon — the App-side pre-check is only
        // UX and can be bypassed; this check cannot. Upstream precedent:
        // Dopamine errors out loudly on unsupported devices, roothide
        // Bootstrap refuses to install; no "silent downgrade" exists in
        // the ecosystem.
        bool supported = rootful_supported_configuration();
        bool rootfulToggle = true; // fixed-rootful build: the toggle is gone
        bool rootfulWanted = supported && rootfulToggle
                && (access(JBROOT_PATH("/basebin/.rootful_disabled"), F_OK) != 0);
        // Hiding (cloak + aegis) is wanted ALWAYS; only marker files opt out.
        bool cloakWanted = (access(JBROOT_PATH("/basebin/.cloak_disabled"), F_OK) != 0);
        bool aegisWanted = (access(JBROOT_PATH("/basebin/.aegis_disabled"), F_OK) != 0);

        if (!supported) {
                printf("Rootful: REJECTED — this device is outside the supported matrix (need A12/A13, iOS 16.6.1 - 18.7.1). This build is rootful-only by design: the rootless/roothide fallback has been removed, so there is no legal jailbreak path here. Aborting this jailbreak run.\n");
                fflush(stdout);
                return -1;
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
                        //
                        // Fixed-rootful build: there is exactly ONE form now —
                        // the deep one. stealthLevel is pinned to 3 (rootful
                        // mounts more (fakefs/overlay six dirs), so the
                        // detection surface is larger too: full hide +
                        // aggressive stealth (getfsstat: everything outside
                        // the mount whitelist is dropped)). Replayed on every
                        // jailbreak (idempotent); a manual set_options still
                        // overrides until the next replay.
                        cloak_policy_t cloakPolicy = { 0 };
                        cloak_get_policy(&cloakPolicy);
                        cloakPolicy.hideMounts      = true;
                        cloakPolicy.hideCredentials = true;
                        cloakPolicy.hideTrustcache  = true;
                        cloakPolicy.stealthLevel    = 3; // fixed (rootful/deep form is the only form)
                        // Flip #1 (2026-10-11): whitelist mode. The aegis list
                        // is a TRUST whitelist — processes on it see the full
                        // picture (file managers & co), everything else is
                        // shielded. See cloak_interpose.c Flip #2 for the
                        // matching semantics change.
                        cloakPolicy.blacklistMode   = false;
                        if (cloak_set_options(&cloakPolicy) == 0) {
                                printf("Cloak: enabled (rootful/deep form, stealth %llu, whitelist mode)\n",
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
                        // aegisd (loaded through the basebin LaunchDaemons
                        // directory) brings up the cover mount, restores the
                        // persisted trust whitelist (aegis.conf, P0-1) and
                        // keeps it in sync.
                        printf("Aegis: enabled (per-app shielding ready)\n");
                }
                else {
                        printf("Aegis: enable failed\n");
                }
        }

        return 0;
}

void install_euphoria(void)
{
        // D1 (fixed-rootful build): refuse up front, zero-destructive — do
        // not even stage basebin on a device that can never legally use it.
        if (!rootful_supported_configuration()) {
                printf("Rootful: REJECTED — device outside the A12/A13 @ iOS 16.6.1-18.7.1 matrix. This build is rootful-only; install aborted.\n");
                fflush(stdout);
                return;
        }

        activate_environment(false, true);

        install_basebin_gen();
        activate_basebin(JBROOT_PATH(@"/basebin"));

        // Now that fakelib is up, we want to make systemhook inject into any binary we spawn
        setenv("DYLD_INSERT_LIBRARIES", "/usr/lib/systemhook.dylib", 1);

        finalize_bootstrap_if_needed(NULL);
        load_var_jb_daemons();

        if (activate_rootful_and_cloak() != 0) {
                // D1 rejection at the activation gate: nothing was activated,
                // leave the marker absent so the run reads as "not jailbroken"
                // (R34 transactional marker) and can be re-run idempotently.
                printf("Euphoria: install aborted (rootful matrix rejection)\n");
                fflush(stdout);
                return;
        }

        printf("Euphoria installed!\n");
}

void install_euphoria_from_tarball(const char *tarballPath, const char *bootstrapPath)
{
        // D1: the tarball leg re-execs into "install", which carries the same
        // zero-destructive matrix pre-check — refuse before staging anything.
        if (!rootful_supported_configuration()) {
                printf("Rootful: REJECTED — device outside the A12/A13 @ iOS 16.6.1-18.7.1 matrix. This build is rootful-only; install aborted.\n");
                fflush(stdout);
                return;
        }

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
        // D1 (fixed-rootful build): refuse before touching anything. The
        // marker is not yet unlinked on this path, so a rejected re-run on an
        // already-jailbroken device changes nothing; on a fresh device
        // nothing is staged. Zero destructive either way.
        if (!rootful_supported_configuration()) {
                printf("Rootful: REJECTED — device outside the A12/A13 @ iOS 16.6.1-18.7.1 matrix. This build is rootful-only; activation aborted.\n");
                fflush(stdout);
                return;
        }

        // R34：事务式越狱标记——流程起点清标记（半程=未越狱，可幂等重跑）
        unlink(JBROOT_PATH("/basebin/.bootstrap_complete"));

        activate_environment(true, false);
        activate_basebin(JBROOT_PATH(@"/basebin"));

        // Now that fakelib is up, we want to make systemhook inject into any binary we spawn
        setenv("DYLD_INSERT_LIBRARIES", "/usr/lib/systemhook.dylib", 1);

        finalize_bootstrap_if_needed(NULL);
        load_var_jb_daemons();

        if (activate_rootful_and_cloak() != 0) {
                // D1 rejection mid-flow: the completion marker is NOT written,
                // so is_jailbroken keeps reading "not yet" (R34 transactional
                // marker) and the whole activation can be re-run idempotently.
                printf("Euphoria: activation aborted (rootful matrix rejection)\n");
                fflush(stdout);
                return;
        }

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