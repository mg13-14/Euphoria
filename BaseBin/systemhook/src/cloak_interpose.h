#ifndef CLOAK_INTERPOSE_H
#define CLOAK_INTERPOSE_H

#include <stdbool.h>
#include <sys/param.h>

/*
 * Euphoria cloak interposition (systemhook side)
 *
 * These hooks are installed into every process that has systemhook loaded.
 * Their purpose is to hide jailbreak evidence from processes that should not
 * see it:
 *
 *   - getfsstat/getfsstat64: remove mount points that belong to the
 *     jailbreak (jbroot, /var/jb bind mount, cloak cover mount)
 *   - statfs/statfs64: report ENOENT when asked about hidden mount points
 *   - sysctl(KERN_PROC*): rewrite the credentials of processes that were
 *     elevated to uid 0 back to their original mobile (501) identity
 *
 * A process counts as *trusted* (sees everything) when it either
 *   - runs with euid 0 (root shell, cloakd, jbctl, ...), or
 *   - resides at a system location (/usr, /bin, /sbin, /System, /usr/libexec).
 *
 * Everything else (App Store apps, third party daemons) gets the filtered
 * view.  The policy itself is pulled from launchdhook once per process.
 */

typedef struct {
	bool enabled;
	bool hideMounts;
	bool hideCredentials;
	bool hideTrustcache;
	uint64_t stealthLevel;
} cloak_policy_cache_t;

extern cloak_policy_cache_t gCloakPolicy;

void cloak_interpose_init(void);
bool cloak_process_is_trusted(void);

#endif
