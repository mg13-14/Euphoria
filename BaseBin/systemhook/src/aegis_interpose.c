#include "aegis_interpose.h"
#include "common/common.h"
#include "common/private.h"

#include <libjailbreak/aegis.h>
#include <libjailbreak/jbroot.h>
#include <libjailbreak/util.h>

#include <errno.h>
#include <stdarg.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mount.h>
#include <sys/param.h>
#include <sys/stat.h>
#include <spawn.h>
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <ptrauth.h>
#include <libproc.h>

#include "litehook.h"

/* ------------------------------------------------------------------------ */
/* "orig" trampolines (B25-5 fix)                                            */
/*                                                                          */
/* litehook entry patches are absolute x16 jumps with no built-in            */
/* trampoline.  The original implementation declared aegis_*_orig function  */
/* pointers but never assigned them, so every hook called NULL and crashed  */
/* on the first intercepted syscall.                                        */
/*                                                                          */
/* This mirrors the proven orig-trampoline pattern from                     */
/* common/hookd_external.c (frida _pthread_create orig):                    */
/*   - copy the target's first 5 instructions (assumed PC-independent,      */
/*     same assumption the in-tree frida orig makes) into executable        */
/*     storage in a dedicated __TEXT section,                               */
/*   - patch storage[5] to jump to target+20 (this also flips the whole     */
/*     page RX on both the iOS 15 default litehook path and the iOS 16+     */
/*     hookd path),                                                         */
/*   - hand the storage pointer out as the "orig" to call from the hook.    */
/* Nested hooking (aegis patching a function systemhook already patched,   */
/* e.g. __posix_spawn) chains correctly because the entry patch jumps      */
/* through an absolute x16 address that executes from any location.         */
/* ------------------------------------------------------------------------ */

#define AEGIS_MAX_TRAMPOLINES 9
static uint32_t gAegisTrampolines[AEGIS_MAX_TRAMPOLINES][16] __attribute__((used, section("__TEXT,__aegistramp")));
static int gAegisTrampolineCount = 0;

static void *aegis_make_orig_trampoline(void *fn)
{
        if (gAegisTrampolineCount >= AEGIS_MAX_TRAMPOLINES) return NULL;
        uint32_t *tramp = gAegisTrampolines[gAegisTrampolineCount++];
        void *fnUnsigned = ptrauth_strip(fn, ptrauth_key_function_pointer);

        // Copy the original first 5 instructions into the trampoline via
        // litehook (handles page protection on both patch paths).
        kern_return_t kr = litehook_hook_memory(tramp, fnUnsigned, sizeof(uint32_t) * 5);
        if (kr != KERN_SUCCESS) return NULL;

        // Patch trampoline instruction 6 to jump back into the original
        // function at instruction 6 (target + 20 bytes).
        kr = litehook_hook_function(
                ptrauth_sign_unauthenticated(&tramp[5], ptrauth_key_function_pointer, 0),
                ptrauth_sign_unauthenticated((void *)((uintptr_t)fnUnsigned + sizeof(uint32_t) * 5), ptrauth_key_function_pointer, 0));
        if (kr != KERN_SUCCESS) return NULL;

        return ptrauth_sign_unauthenticated((void *)tramp, ptrauth_key_function_pointer, 0);
}

/* ------------------------------------------------------------------------ */
/* Policy cache                                                              */
/* ------------------------------------------------------------------------ */

static aegis_policy_t gAegisPolicy = { 0 };
static bool gAegisActive = false;       // aegis enabled systemwide
static uint64_t gAegisLevel = AEGIS_LEVEL_OFF; // shield level for THIS process

/* ------------------------------------------------------------------------ */
/* Process matching                                                          */
/* ------------------------------------------------------------------------ */

static bool aegis_process_matches_list(const char *execPath)
{
        if (!execPath || !execPath[0]) return false;
        /* Extract the executable basename and the .app bundle dir name.
         * Policy entries may be either a binary name ("MyApp"), a bundle
         * directory ("MyApp.app"), a bundle id ("com.example.MyApp"), or a
         * path prefix. We do a flexible match: if the entry appears anywhere
         * in the executable path OR equals the basename, it matches. */
        char pathCopy[MAXPATHLEN];
        strlcpy(pathCopy, execPath, sizeof(pathCopy));

        const char *base = strrchr(pathCopy, '/');
        base = base ? base + 1 : pathCopy;

        /* Walk back to the .app bundle dir name if present */
        char *appMarker = strstr(pathCopy, ".app/");
        const char *bundleDir = NULL;
        if (appMarker) {
                *appMarker = '\0'; // truncate at ".app/"
                const char *slash = strrchr(pathCopy, '/');
                bundleDir = slash ? slash + 1 : pathCopy;
                *appMarker = '.'; // restore
        }

        for (uint32_t i = 0; i < gAegisPolicy.appCount; i++) {
                const char *entry = gAegisPolicy.appBundleIds[i];
                if (!entry || !entry[0]) continue;
                /* exact basename match */
                if (strcmp(entry, base) == 0) return true;
                /* bundle dir match */
                if (bundleDir && strcmp(entry, bundleDir) == 0) return true;
                /* substring / bundle-id match */
                if (strstr(execPath, entry) != NULL) return true;
        }
        return false;
}

static void aegis_determine_level(void)
{
        char execPath[MAXPATHLEN] = { 0 };
        if (proc_pidpath(getpid(), execPath, sizeof(execPath)) <= 0) return;

        if (aegis_process_matches_list(execPath)) {
                /* explicit per-app entry — find its level */
                char pathCopy[MAXPATHLEN];
                strlcpy(pathCopy, execPath, sizeof(pathCopy));
                const char *base = strrchr(pathCopy, '/');
                base = base ? base + 1 : pathCopy;
                char *appMarker = strstr(pathCopy, ".app/");
                const char *bundleDir = NULL;
                if (appMarker) {
                        *appMarker = '\0';
                        const char *slash = strrchr(pathCopy, '/');
                        bundleDir = slash ? slash + 1 : pathCopy;
                }
                for (uint32_t i = 0; i < gAegisPolicy.appCount; i++) {
                        const char *entry = gAegisPolicy.appBundleIds[i];
                        if (!entry) continue;
                        if (strcmp(entry, base) == 0 ||
                                (bundleDir && strcmp(entry, bundleDir) == 0) ||
                                strstr(execPath, entry) != NULL) {
                                gAegisLevel = gAegisPolicy.appLevels[i];
                                return;
                        }
                }
        }
        /* Not on the list: fall back to the default level only for processes
         * that look like user apps (path contains .app); system daemons are
         * never shielded by default. */
        if (strstr(execPath, ".app/") != NULL) {
                gAegisLevel = gAegisPolicy.defaultLevel;
        }
        else {
                gAegisLevel = AEGIS_LEVEL_OFF;
        }
}

/* ------------------------------------------------------------------------ */
/* File-existence syscall interposition                                      */
/* ------------------------------------------------------------------------ */

static bool aegis_should_suppress_path(const char *path)
{
        if (gAegisLevel < AEGIS_LEVEL_LITE) return false;
        if (!path) return false;
        return aegis_path_is_jailbreak_artefact(path);
}

/* stat family */
static int (*aegis_stat_orig)(const char *restrict, struct stat *restrict) = NULL;
static int aegis_stat_hook(const char *restrict path, struct stat *restrict buf)
{
        if (aegis_should_suppress_path(path)) { errno = ENOENT; return -1; }
        return aegis_stat_orig(path, buf);
}

static int (*aegis_lstat_orig)(const char *restrict, struct stat *restrict) = NULL;
static int aegis_lstat_hook(const char *restrict path, struct stat *restrict buf)
{
        if (aegis_should_suppress_path(path)) { errno = ENOENT; return -1; }
        return aegis_lstat_orig(path, buf);
}

static int (*aegis_access_orig)(const char *, int) = NULL;
static int aegis_access_hook(const char *path, int mode)
{
        if (aegis_should_suppress_path(path)) { errno = ENOENT; return -1; }
        return aegis_access_orig(path, mode);
}

static int (*aegis_open_orig)(const char *, int, ...) = NULL;
static int aegis_open_hook(const char *path, int flags, ...)
{
        if (aegis_should_suppress_path(path)) { errno = ENOENT; return -1; }
        /* forward varargs (mode) when O_CREAT was requested */
        if (flags & O_CREAT) {
                va_list ap; va_start(ap, flags);
                mode_t mode = (mode_t)va_arg(ap, int);
                va_end(ap);
                return aegis_open_orig(path, flags, mode);
        }
        return aegis_open_orig(path, flags);
}

static int (*aegis_openat_orig)(int, const char *, int, ...) = NULL;
static int aegis_openat_hook(int fd, const char *path, int flags, ...)
{
        if (aegis_should_suppress_path(path)) { errno = ENOENT; return -1; }
        if (flags & O_CREAT) {
                va_list ap; va_start(ap, flags);
                mode_t mode = (mode_t)va_arg(ap, int);
                va_end(ap);
                return aegis_openat_orig(fd, path, flags, mode);
        }
        return aegis_openat_orig(fd, path, flags);
}

static int (*aegis_faccessat_orig)(int, const char *, int, int) = NULL;
static int aegis_faccessat_hook(int fd, const char *path, int mode, int flag)
{
        if (aegis_should_suppress_path(path)) { errno = ENOENT; return -1; }
        return aegis_faccessat_orig(fd, path, mode, flag);
}

/* ------------------------------------------------------------------------ */
/* posix_spawn env scrubbing                                                 */
/* ------------------------------------------------------------------------ */

static bool aegis_env_var_is_injection(const char *env)
{
        if (!env) return false;
        static const char *strip_prefixes[] = {
                "DYLD_INSERT_LIBRARIES=",
                "DYLD_LIBRARY_PATH=",
                "DYLD_FRAMEWORK_PATH=",
                "_MSSAFEWORD=",            // MobileSubstrate secret
                "OBJC_DISABLE_INITIALIZE_FORK_SAFETY=",
        };
        for (size_t i = 0; i < sizeof(strip_prefixes)/sizeof(strip_prefixes[0]); i++) {
                if (strncmp(env, strip_prefixes[i], strlen(strip_prefixes[i])) == 0) return true;
        }
        return false;
}

/* Build a filtered envp (caller frees). Returns NULL on failure or when
 * nothing needs stripping (in which case the original envp is safe to use). */
static char **aegis_scrub_env(char *const *envp)
{
        if (!envp) return NULL;
        size_t count = 0, kept = 0;
        while (envp[count]) count++;

        char **out = calloc(count + 1, sizeof(char *));
        if (!out) return NULL;

        for (size_t i = 0; i < count; i++) {
                if (!aegis_env_var_is_injection(envp[i])) {
                        out[kept++] = envp[i];
                }
        }
        out[kept] = NULL;
        return out;
}

extern int __posix_spawn(pid_t *restrict, const char *restrict, struct _posix_spawn_args_desc *restrict, char *const argv[restrict], char *const envp[restrict]);
extern int __posix_spawnp(pid_t *restrict, const char *restrict, struct _posix_spawn_args_desc *restrict, char *const argv[restrict], char *const envp[restrict]);

static int (*aegis_posix_spawn_orig)(pid_t *restrict, const char *restrict, struct _posix_spawn_args_desc *restrict, char *const argv[restrict], char *const envp[restrict]) = NULL;
static int aegis_posix_spawn_hook(pid_t *restrict pid, const char *restrict path, struct _posix_spawn_args_desc *restrict desc, char *const argv[restrict], char *const envp[restrict])
{
        char **scrubbed = NULL;
        if (gAegisLevel >= AEGIS_LEVEL_LITE) {
                scrubbed = aegis_scrub_env(envp);
        }
        char *const *useEnvp = scrubbed ? scrubbed : envp;
        int r = aegis_posix_spawn_orig(pid, path, desc, argv, useEnvp);
        if (scrubbed) free(scrubbed);
        return r;
}

/* ------------------------------------------------------------------------ */
/* Mount enumeration hiding (complement to cloak; per-app)                  */
/* ------------------------------------------------------------------------ */

/* B25-5 fix: the original implementation hooked "getfsent", but no
 * int(struct statfs *) getfsent exists on Darwin at all — the BSD
 * getfsent(3) is the fstab family and returns struct fstab *, so the
 * identifier was undeclared for the iOS SDK (hard compile error) and the
 * skip-once loop leaked consecutive artefact entries anyway.
 *
 * Hide mounts via getfsstat in-place compaction instead, mirroring the
 * proven cloak_interpose.c pattern: every artefact entry is dropped from
 * the buffer, which handles arbitrarily many consecutive artefacts. */

static int (*aegis_getfsstat_orig)(struct statfs *, int, int) = NULL;
static bool aegis_mount_is_hidden(const char *mntonname)
{
        if (!mntonname || !mntonname[0]) return false;
        return aegis_path_is_jailbreak_artefact(mntonname);
}

static int aegis_getfsstat_hook(struct statfs *buf, int bufsize, int flags)
{
        if (!aegis_getfsstat_orig) return -1;
        int r = aegis_getfsstat_orig(buf, bufsize, flags);
        if (r <= 0) return r;
        if (!buf) return r;

        /* Rewrite the buffer in place, dropping every hidden entry. */
        int out = 0;
        for (int i = 0; i < r; i++) {
                if (!aegis_mount_is_hidden(buf[i].f_mntonname)) {
                        if (out != i) memcpy(&buf[out], &buf[i], sizeof(struct statfs));
                        out++;
                }
        }
        return out;
}

/* ------------------------------------------------------------------------ */
/* Installation                                                              */
/* ------------------------------------------------------------------------ */

void aegis_interpose_init(void)
{
        if (aegis_get_policy(&gAegisPolicy) != 0) return;
        if (!gAegisPolicy.enabled) return;
        gAegisActive = true;

        aegis_determine_level();
        if (gAegisLevel == AEGIS_LEVEL_OFF) return;

        /* B25-5 fix: build all orig trampolines BEFORE hooking (the prologue
         * copy must see the unpatched instructions — note __posix_spawn may
         * already carry systemhook's own patch, which the trampoline then
         * chains through). If a trampoline cannot be built, skip that hook
         * rather than install one that calls NULL. */
        if (gAegisLevel >= AEGIS_LEVEL_LITE) {
                aegis_stat_orig = aegis_make_orig_trampoline((void *)stat);
                aegis_lstat_orig = aegis_make_orig_trampoline((void *)lstat);
                aegis_access_orig = aegis_make_orig_trampoline((void *)access);
                aegis_open_orig = aegis_make_orig_trampoline((void *)open);
                aegis_openat_orig = aegis_make_orig_trampoline((void *)openat);
                aegis_faccessat_orig = aegis_make_orig_trampoline((void *)faccessat);
                aegis_posix_spawn_orig = aegis_make_orig_trampoline((void *)__posix_spawn);

                if (aegis_stat_orig)       litehook_hook_function(stat,           aegis_stat_hook);
                if (aegis_lstat_orig)      litehook_hook_function(lstat,          aegis_lstat_hook);
                if (aegis_access_orig)     litehook_hook_function(access,         aegis_access_hook);
                if (aegis_open_orig)       litehook_hook_function(open,           aegis_open_hook);
                if (aegis_openat_orig)     litehook_hook_function(openat,         aegis_openat_hook);
                if (aegis_faccessat_orig)  litehook_hook_function(faccessat,      aegis_faccessat_hook);
                if (aegis_posix_spawn_orig) litehook_hook_function(__posix_spawn, aegis_posix_spawn_hook);
        }
        /* PARANOID: also hide mount enumeration entries */
        if (gAegisLevel >= AEGIS_LEVEL_PARANOID) {
                aegis_getfsstat_orig = aegis_make_orig_trampoline((void *)getfsstat);
                if (aegis_getfsstat_orig) {
                        litehook_hook_function(getfsstat, aegis_getfsstat_hook);
                }
        }
}
