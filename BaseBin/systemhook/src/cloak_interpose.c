#include "cloak_interpose.h"
#include "common/common.h"
#include "common/private.h"

#include <libjailbreak/cloak.h>
#include <libjailbreak/jbroot.h>
#include <libjailbreak/util.h>

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

cloak_policy_cache_t gCloakPolicy = { 0 };

static bool gCloakPathInitialized = false;
static char gJbrootMountPoint[MAXPATHLEN] = { 0 };
static char gBindMountPoint[MAXPATHLEN] = { 0 };

/* ------------------------------------------------------------------------ */
/* Policy                                                                    */
/* ------------------------------------------------------------------------ */

static void cloak_reload_policy(void)
{
        cloak_policy_t policy = { 0 };
        if (cloak_get_policy(&policy) == 0) {
                gCloakPolicy.enabled         = policy.enabled;
                gCloakPolicy.hideMounts      = policy.enabled && policy.hideMounts;
                gCloakPolicy.hideCredentials = policy.enabled && policy.hideCredentials;
                gCloakPolicy.hideTrustcache  = policy.enabled && policy.hideTrustcache;
                gCloakPolicy.stealthLevel    = policy.stealthLevel;
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
                        kproc->kp_eproc.e_ucred.cr_ruid = 501;
                        kproc->kp_eproc.e_ucred.cr_rgid = 501;
                        kproc->kp_eproc.e_pcred.p_ruid  = 501;
                        kproc->kp_eproc.e_pcred.p_rgid  = 501;
                        kproc->kp_eproc.e_ucred.cr_svuid = 501;
                        kproc->kp_eproc.e_ucred.cr_svgid = 501;
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
