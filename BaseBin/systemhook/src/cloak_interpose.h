#ifndef CLOAK_INTERPOSE_H
#define CLOAK_INTERPOSE_H

#include <stdbool.h>
#include <stdint.h>
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
 *
 * R40 blacklist mode (default on): the filtered view only applies to
 * processes on the aegis shield list (the "blacklist"); everything not
 * blacklisted — file managers, Sileo, the jailbreak ecosystem — sees the
 * full environment.  Root/system-prefix trust rules always apply on top.
 */

typedef struct {
	bool enabled;
	bool hideMounts;
	bool hideCredentials;
	bool hideTrustcache;
	uint64_t stealthLevel;
	// R40（用户 2026-08-29 17:00 定案）：黑名单制——true 时过滤只对 aegis
	// 名单内进程生效（名单外=信任态：文件管理器等越狱生态工具正常可见可管）。
	// 读路径=jbsettings cloakBlacklistMode（GET_POLICY 表满 8 参，走独立键）。
	bool blacklistMode;
} cloak_policy_cache_t;

extern cloak_policy_cache_t gCloakPolicy;

void cloak_interpose_init(void);
bool cloak_process_is_trusted(void);

#endif
