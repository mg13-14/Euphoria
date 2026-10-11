#include "cloak_interpose.h"
#include "common/common.h"
#include "common/private.h"

#include <libjailbreak/cloak.h>
#include <stdint.h>
#include <libjailbreak/aegis.h>       // R40: aegis_get_policy（黑名单匹配）
#include <libjailbreak/jbroot.h>
#include <libjailbreak/util.h>
#include <libjailbreak/jbclient_xpc.h> // R40: jbclient_jbsettings_get_bool
#include <libproc.h>                    // R40: proc_pidpath

#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/mount.h>
#include <sys/param.h>
#include <sys/sysctl.h>
#include <sys/proc_info.h>
#include <sys/syscall.h>
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <ptrauth.h>

#include "litehook.h"

// 构建修复：iOS SDK 的 sys/sysctl.h 未定义以下两个 KERN_PROC 选择器，补 fallback 值
#ifndef KERN_PROC_PIDINFO
#define KERN_PROC_PIDINFO 17
#endif
#ifndef KERN_PROC_TBSDINFO
#define KERN_PROC_TBSDINFO 18
#endif

// XNU 完整 _ucred 前缀布局：SDK 公开 struct _ucred 只到 cr_groups，
// cr_ruid/cr_svuid/cr_rgid/cr_svgid 为 KERNEL_PRIVATE。sysctl 返回的
// kinfo_proc 来自内核，内存布局即完整 _ucred——按 XNU bsd/sys/ucred.h
// 前缀（到 cr_svgid）本地定义并强转访问，避免依赖私有头。
struct _ucred_xnu_prefix {
        u_long  cr_version;
        uid_t   cr_uid;
        short   cr_ngroups;
        gid_t   cr_groups[NGROUPS];
        uid_t   cr_ruid;
        uid_t   cr_svuid;
        uid_t   cr_rgid;
        gid_t   cr_svgid;
};

cloak_policy_cache_t gCloakPolicy = { 0 };

static bool gCloakPathInitialized = false;
static char gJbrootMountPoint[MAXPATHLEN] = { 0 };
static char gBindMountPoint[MAXPATHLEN] = { 0 };

/* ------------------------------------------------------------------------ */
/* "orig" trampolines (B25-5 fix)                                            */
/*                                                                          */
/* litehook entry patches are absolute x16 jumps with no built-in            */
/* trampoline, therefore a hook that calls the patched libc symbol           */
/* directly recurses forever (hook -> patch -> hook ...).  The original      */
/* implementation of the four mount/credential hooks did exactly that.      */
/*                                                                          */
/* This mirrors the proven orig-trampoline pattern from                      */
/* common/hookd_external.c (frida _pthread_create orig):                    */
/*   - copy the target's first 5 instructions (assumed PC-independent,      */
/*     same assumption the in-tree frida orig makes) into executable        */
/*     storage,                                                                  */
/*   - patch storage[5] to jump to target+20 (hooking storage[5] has the    */
/*     side effect of flipping the whole page RX on both the iOS 15         */
/*     default litehook path and the iOS 16+ hookd path),                    */
/*   - hand the storage pointer out as the "orig" to call from the hook.    */
/*                                                                          */
/* The storage lives in a dedicated __TEXT section so it is executable from */
/* load time; all writes go through litehook_hook_memory so both patch      */
/* paths handle the unprotect/write/protect cycle.                          */
/* Nested hooking (cloak + aegis hooking the same function) chains          */
/* correctly because the entry patch jumps through an absolute x16 address  */
/* that executes from any location.                                         */
/* ------------------------------------------------------------------------ */

#define CLOAK_MAX_TRAMPOLINES 4
static uint32_t gCloakTrampolines[CLOAK_MAX_TRAMPOLINES][16] __attribute__((used, section("__TEXT,__cloaktramp")));
static int gCloakTrampolineCount = 0;

static void *cloak_make_orig_trampoline(void *fn)
{
        if (gCloakTrampolineCount >= CLOAK_MAX_TRAMPOLINES) return NULL;
        uint32_t *tramp = gCloakTrampolines[gCloakTrampolineCount++];
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

static int (*cloak_getfsstat_orig)(struct statfs *, int, int) = NULL;
static int (*cloak_statfs_orig)(const char *, struct statfs *) = NULL;
static int (*cloak_sysctl_orig)(const char *, u_int, void *, size_t *, void *, size_t) = NULL;

/* ------------------------------------------------------------------------ */
/* Policy                                                                    */
/* ------------------------------------------------------------------------ */

// Is this process on the aegis list? Since the deny-by-default flip the list
// is a *trust whitelist*: returning true means "this process may see the
// unfiltered view". Matching logic must stay in sync with
// systemhook/src/aegis_interpose.c:aegis_process_matches_list (P2-5: exact
// basename / .app bundle-dir match only — substring matching would grant
// trust too liberally on a whitelist).
//
// Flip #7 (fail-closed + TTL cache): this used to do a full XPC round-trip
// on every hooked syscall and treated XPC failure as "not on the list"
// (fail-open). Two changes:
//   1. A 30s cache in front of the XPC: a syscall-heavy detection loop must
//      not be able to measure XPC timing either.
//   2. XPC failure now keeps the last good snapshot (or an empty policy when
//      there has never been one). An empty snapshot reads as "not on the
//      list" — which after the flip means "filtered", i.e. failure fails
//      closed, never open.
static bool cloak_process_on_aegis_list(void)
{
        static aegis_policy_t sListCache = { 0 };
        static bool sListValid = false;
        static time_t sListStamp = 0;

        time_t now = time(NULL);
        if (!sListValid || (now - sListStamp) >= 30) {
                aegis_policy_t fresh = { 0 };
                if (aegis_get_policy(&fresh) == 0) {
                        sListCache = fresh;
                        sListValid = true;
                        sListStamp = now;
                }
                /* On failure deliberately keep the old snapshot (or none):
                 * fail-closed by construction — see header comment. */
        }
        if (!sListValid) return false;
        if (!sListCache.enabled || sListCache.appCount == 0) return false;

        char execPath[MAXPATHLEN] = { 0 };
        if (proc_pidpath(getpid(), execPath, sizeof(execPath)) <= 0) return false;

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

        for (uint32_t i = 0; i < sListCache.appCount; i++) {
                const char *entry = sListCache.appBundleIds[i];
                if (!entry || !entry[0]) continue;
                /* P2-5: exact channels only — sync with aegis_process_matches_list */
                if (strcmp(entry, base) == 0) return true;
                if (bundleDir && strcmp(entry, bundleDir) == 0) return true;
        }
        return false;
}

static void cloak_reload_policy(void)
{
        cloak_policy_t policy = { 0 };
        if (cloak_get_policy(&policy) == 0) {
                gCloakPolicy.enabled         = policy.enabled;
                gCloakPolicy.hideMounts      = policy.enabled && policy.hideMounts;
                gCloakPolicy.hideCredentials = policy.enabled && policy.hideCredentials;
                gCloakPolicy.hideTrustcache  = policy.enabled && policy.hideTrustcache;
                gCloakPolicy.stealthLevel    = policy.stealthLevel;
                // R40：GET_POLICY 表满 8 参装不下 blacklistMode——走 jbsettings 独立键。
                // 未越狱/读取失败=false（旧语义兜底，不阻断既有隐藏）。
                gCloakPolicy.blacklistMode   = jbclient_jbsettings_get_bool("cloakBlacklistMode");
        }
}

bool cloak_process_is_trusted(void)
{
        // Root processes (interactive shells, jbctl, cloakd, ...) always see the
        // full picture, otherwise maintaining the jailbreak would be impossible.
        if (geteuid() == 0) return true;

        char execPath[MAXPATHLEN] = { 0 };
        uint32_t execPathLen = sizeof(execPath);
        if (_NSGetExecutablePath(execPath, &execPathLen) != 0) return false;

        // Flip #2 (2026-10-11, user decision "hide from third parties after
        // jailbreak"): the aegis list is now a TRUST whitelist, not a block
        // list. Processes on the list (file managers and other jailbreak
        // ecosystem tools that need the unfiltered view to work) are trusted;
        // everything else — every ordinary app — gets the filtered view.
        // Default policy value is whitelist mode (blacklistMode == false):
        // unlisted untrusted apps are hidden from, which is the entire point
        // of the hidden environment. The old R40 blacklist branch is kept
        // only as the opt-out marker path (see daemon main.m).
        if (!gCloakPolicy.blacklistMode && cloak_process_on_aegis_list()) {
                return true;
        }

        // System daemons and binaries are trusted.
        static const char *trustedPrefixes[] = {
                "/usr/", "/bin/", "/sbin/", "/System/", "/usr/libexec/", NULL,
        };
        for (int i = 0; trustedPrefixes[i]; i++) {
                if (string_has_prefix(execPath, trustedPrefixes[i])) return true;
        }
        return false;
}

/* ------------------------------------------------------------------------ */
/* Mount hiding                                                              */
/* ------------------------------------------------------------------------ */

static bool cloak_mount_is_hidden(const char *mntonname)
{
        if (!gCloakPathInitialized) {
                strlcpy(gJbrootMountPoint, JBROOT_PATH(""), sizeof(gJbrootMountPoint));
                strlcpy(gBindMountPoint, "/var/jb", sizeof(gBindMountPoint));
                gCloakPathInitialized = true;
        }
        if (!mntonname) return false;

        // The jbroot itself, the /var/jb convenience bind mount and every path
        // nested below either of them.
        if (string_has_prefix(mntonname, gJbrootMountPoint)) return true;
        if (string_has_prefix(mntonname, gBindMountPoint)) return true;

        // At stealth level >= 2, anything that is not APFS/systemfs is hidden
        // (covers the cloak cover mount and any future bind mounts).
        if (gCloakPolicy.stealthLevel >= 2) {
                if (strcmp(mntonname, "/") &&
                        strncmp(mntonname, "/System", 7) &&
                        strncmp(mntonname, "/private/var", 12) &&
                        strncmp(mntonname, "/private/tmp", 12) &&
                        strncmp(mntonname, "/dev", 4)) {
                        return true;
                }
        }
        return false;
}

int getfsstat_hook(struct statfs *buf, int bufsize, int flags)
{
        // B25-5 fix: call the saved orig trampoline instead of the patched
        // libc symbol (direct call = infinite recursion).
        if (!cloak_getfsstat_orig) return -1;
        int r = cloak_getfsstat_orig(buf, bufsize, flags);
        if (r <= 0) return r;

        bool filter = gCloakPolicy.hideMounts && !cloak_process_is_trusted();
        if (!filter || !buf) return r;

        // Rewrite the buffer in place, dropping every hidden entry.
        int out = 0;
        for (int i = 0; i < r; i++) {
                if (!cloak_mount_is_hidden(buf[i].f_mntonname)) {
                        if (out != i) memcpy(&buf[out], &buf[i], sizeof(struct statfs));
                        out++;
                }
        }
        return out;
}

// B25-5 fix: getfsstat64/statfs64 hooks removed. On arm64/arm64e iOS the SDK
// marks the *64 statfs family __IPHONE_NA (struct statfs already IS the
// 64-bit layout via __DARWIN_STRUCT_STATFS64) and the arm64 dyld shared
// cache does not export the *64 symbols, so hooking them can neither
// compile nor link for this target. Apps on iOS use getfsstat/statfs,
// which stay hooked.

// P0-3 (2026-10-11): statfs on a hidden mount used to return ENOENT — but on
// a STOCK device every one of these paths (they sit on the sealed system
// volume or are plain directories) statfs()s successfully, so an error was
// itself a jailbreak fingerprint ("an error is a fingerprint", B-line rule).
// With rootful fixed + the deny-by-default flip every untrusted app eats
// this filter, so the fingerprint would fire for every detection probe on
// day one. New contract (A-line dual-track fix):
//   - statfs(path) on a hidden mount: fabricate the underlying system-volume
//     entry — template from a real orig statfs("/") call, f_mntonname pinned
//     to "/" — and return 0. The four comparison fields the detectors hash
//     (f_type/f_flags/f_fstypename/f_bsize) then match stock byte-for-byte,
//     because they come from the real system volume.
//   - getfsstat enumeration: keep DROPPING the entries (a stock mount table
//     simply does not contain them — dropping is the stock-faithful answer).
// ENOENT survives only as the last-resort fallback when the template query
// itself fails (better a stale fingerprint than a crash or a lie).
static int statfs_common(const char *path, struct statfs *buf, int origRv, int *errnoOut)
{
        if (origRv == 0 &&
                gCloakPolicy.hideMounts &&
                !cloak_process_is_trusted() &&
                cloak_mount_is_hidden(path)) {
                if (buf && cloak_statfs_orig) {
                        struct statfs systemVolume = { 0 };
                        if (cloak_statfs_orig("/", &systemVolume) == 0) {
                                memcpy(buf, &systemVolume, sizeof(struct statfs));
                                strlcpy(buf->f_mntonname, "/", sizeof(buf->f_mntonname));
                                *errnoOut = 0;
                                return 0;
                        }
                        // Template query failed — fall through to ENOENT below
                        // (documented last-resort, see header comment).
                }
                *errnoOut = ENOENT;
                return -1;
        }
        return origRv;
}

int statfs_hook(const char *path, struct statfs *buf)
{
        // B25-5 fix: call the saved orig trampoline (direct call recurses).
        if (!cloak_statfs_orig) { errno = ENOENT; return -1; }
        int r = cloak_statfs_orig(path, buf);
        int e = errno;
        int filtered = statfs_common(path, buf, r, &e);
        errno = e;
        return filtered;
}

/* ------------------------------------------------------------------------ */
/* Credential hiding (sysctl KERN_PROC)                                      */
/* ------------------------------------------------------------------------ */

static void cloak_scrub_kinfo_proc(struct kinfo_proc *kproc)
{
        if (!kproc) return;

        // Processes elevated by launchdhook run as uid 0.  Untrusted observers
        // get to see the stock mobile identity instead.
        if (kproc->kp_proc.p_pid != getpid() && kproc->kp_eproc.e_ucred.cr_uid == 0) {
                bool hide = gCloakPolicy.hideCredentials && !cloak_process_is_trusted();
                if (hide) {
                        const struct _ucred_xnu_prefix *uc = (const struct _ucred_xnu_prefix *)&kproc->kp_eproc.e_ucred;
                        struct _ucred_xnu_prefix *ucw = (struct _ucred_xnu_prefix *)&kproc->kp_eproc.e_ucred;
                        (void)uc;
                        ucw->cr_uid  = 501;
                        ucw->cr_ruid = 501;
                        ucw->cr_svuid = 501;
                        ucw->cr_rgid = 501;
                        ucw->cr_svgid = 501;
                        kproc->kp_eproc.e_pcred.p_ruid  = 501;
                        kproc->kp_eproc.e_pcred.p_rgid  = 501;
                        // A stock system process never carries all-zero groups.
                        ucw->cr_ngroups = 1;
                        for (int g = 1; g < NGROUPS; g++) {
                                ucw->cr_groups[g] = 0;
                        }
                        ucw->cr_groups[0] = 501;
                }
        }
}


int sysctl_hook(const char *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen)
{
        // B25-5 fix: call the saved orig trampoline (direct call recurses).
        if (!cloak_sysctl_orig) return -1;
        int r = cloak_sysctl_orig(name, namelen, oldp, oldlenp, newp, newlen);
        if (r != 0) return r;

        if (!gCloakPolicy.hideCredentials) return r;
        if (cloak_process_is_trusted()) return r;
        if (namelen < 2 || !oldp) return r;

        if (name[0] == CTL_KERN && name[1] == KERN_PROC) {
                int entrySize = 0;
                switch (name[2]) {
                        case KERN_PROC_PID:
                        case KERN_PROC_PIDINFO:
                        case KERN_PROC_TBSDINFO:
                                entrySize = (int)sizeof(struct kinfo_proc);
                                break;
                        case KERN_PROC_ALL:
                        case KERN_PROC_UID:
                                entrySize = (int)sizeof(struct kinfo_proc);
                                break;
                        default:
                                return r;
                }

                if (entrySize > 0 && oldlenp && *oldlenp >= (size_t)entrySize) {
                        size_t count = *oldlenp / (size_t)entrySize;
                        for (size_t i = 0; i < count; i++) {
                                cloak_scrub_kinfo_proc(&((struct kinfo_proc *)oldp)[i]);
                        }
                }
        }
        return r;
}

/* ------------------------------------------------------------------------ */
/* Installation                                                              */
/* ------------------------------------------------------------------------ */

void cloak_interpose_init(void)
{
        cloak_reload_policy();
        if (!gCloakPolicy.enabled) return;

        // B25-5 fix: build all orig trampolines BEFORE hooking (the prologue
        // copy must see the unpatched instructions). If a trampoline cannot
        // be built, skip that hook rather than install a recursing one.
        cloak_getfsstat_orig = cloak_make_orig_trampoline((void *)getfsstat);
        cloak_statfs_orig = cloak_make_orig_trampoline((void *)statfs);

        if (cloak_getfsstat_orig) {
                litehook_hook_function(getfsstat, getfsstat_hook);
        }
        if (cloak_statfs_orig) {
                litehook_hook_function(statfs, statfs_hook);
        }
        if (gCloakPolicy.hideCredentials) {
                cloak_sysctl_orig = cloak_make_orig_trampoline((void *)sysctl);
                if (cloak_sysctl_orig) {
                        litehook_hook_function(sysctl, sysctl_hook);
                }
        }
}
