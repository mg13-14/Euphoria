#include "cloak_interpose.h"
#include "common/common.h"
#include "common/private.h"

#include <libjailbreak/cloak.h>
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

#include "litehook.h"

// 构建修复：iOS SDK 的 sys/sysctl.h 未定义以下两个 KERN_PROC 选择器，补 fallback 值
#ifndef KERN_PROC_PIDINFO
#define KERN_PROC_PIDINFO 17
#endif
#ifndef KERN_PROC_TBSDINFO
#define KERN_PROC_TBSDINFO 18
#endif

cloak_policy_cache_t gCloakPolicy = { 0 };

static bool gCloakPathInitialized = false;
static char gJbrootMountPoint[MAXPATHLEN] = { 0 };
static char gBindMountPoint[MAXPATHLEN] = { 0 };

/* ------------------------------------------------------------------------ */
/* Policy                                                                    */
/* ------------------------------------------------------------------------ */

// R40：本进程是否在 aegis 屏蔽名单（黑名单）内。
// 匹配逻辑与 systemhook/src/aegis_interpose.c 的 aegis_process_matches_list
// 保持一致（弹性匹配：二进制名/.app 目录名/bundle id/路径子串）——该文件由
// root 属主维护，此处内联一份以解耦，改匹配规则时两处同步。
static bool cloak_process_on_aegis_list(void)
{
        aegis_policy_t aegisPolicy = { 0 };
        if (aegis_get_policy(&aegisPolicy) != 0) return false;
        if (!aegisPolicy.enabled || aegisPolicy.appCount == 0) return false;

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

        for (uint32_t i = 0; i < aegisPolicy.appCount; i++) {
                const char *entry = aegisPolicy.appBundleIds[i];
                if (!entry || !entry[0]) continue;
                if (strcmp(entry, base) == 0) return true;
                if (bundleDir && strcmp(entry, bundleDir) == 0) return true;
                if (strstr(execPath, entry) != NULL) return true;
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

        // R40（用户 2026-08-29 17:00 定案）黑名单制：不在 aegis 名单上的进程
        // 一律信任——文件管理器等越狱生态工具靠越狱/巨魔提权工作（用户原话
        // "他就是靠越狱和巨魔来提升管理器权限"），屏蔽它们等于废掉它们；
        // 只有被拉黑的 app（检测越狱的那些）才吃过滤视图。
        // blacklistMode=false 时维持 R40 前旧语义（非受信全隐藏，兜底开关）。
        if (gCloakPolicy.blacklistMode && !cloak_process_on_aegis_list()) {
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
        int r = getfsstat(buf, bufsize, flags);
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

// On arm64 iOS, statfs/getfsstat are already 64-bit and no separate
// statfs64/getfsstat64 symbols exist in libSystem, so the 64-bit variants
// are intentionally not hooked here.

static int statfs_common(const char *path, int origRv, int *errnoOut)
{
        if (origRv == 0 &&
                gCloakPolicy.hideMounts &&
                !cloak_process_is_trusted() &&
                cloak_mount_is_hidden(path)) {
                *errnoOut = ENOENT;
                return -1;
        }
        return origRv;
}

int statfs_hook(const char *path, struct statfs *buf)
{
        int r = statfs(path, buf);
        int e = errno;
        int filtered = statfs_common(path, r, &e);
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
                        kproc->kp_eproc.e_ucred.cr_uid  = 501;
                        kproc->kp_eproc.e_ucred.cr_gid  = 501;
                        // 构建修复：用户态 struct _ucred 无 cr_ruid/cr_rgid/cr_svuid/cr_svgid
                        // 成员（内核私有），删去这四行赋值；真实/保存 uid 由下方 p_ruid 覆盖。
                        kproc->kp_eproc.e_pcred.p_ruid  = 501;
                        kproc->kp_eproc.e_pcred.p_rgid  = 501;
                        // A stock system process never carries all-zero groups.
                        kproc->kp_eproc.e_ucred.cr_ngroups = 1;
                        for (int g = 1; g < NGROUPS; g++) {
                                kproc->kp_eproc.e_ucred.cr_groups[g] = 0;
                        }
                        kproc->kp_eproc.e_ucred.cr_groups[0] = 501;
                }
        }
}


int sysctl_hook(const char *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen)
{
        int r = sysctl(name, namelen, oldp, oldlenp, newp, newlen);
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

        litehook_hook_function(getfsstat,   getfsstat_hook);
        litehook_hook_function(statfs,      statfs_hook);
        if (gCloakPolicy.hideCredentials) {
                litehook_hook_function(sysctl, sysctl_hook);
        }
}
