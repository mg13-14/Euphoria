#ifndef __CLOAK_H
#define __CLOAK_H

#include <stdint.h>
#include <stdbool.h>
#include <xpc/xpc.h>

/*
 * Euphoria cloak subsystem
 *
 * "Cloak" is the stealth layer of Euphoria.  It hides the fact that the
 * device is jailbroken *and rootful* from untrusted processes while the
 * jailbreak is active:
 *
 *   - the jbroot and cloak mounts disappear from getfsstat()/statfs()
 *     results,
 *   - processes that were elevated to real uid 0 by launchdhook present
 *     stock credentials in response to sysctl(KERN_PROC...) and csops(),
 *   - the cloak mount itself is an unremarkable bindfs mount that carries
 *     no jailbreak-relevant names.
 *
 * The authoritative state lives inside launchdhook (JBS_DOMAIN_CLOAK).
 * systemhook pulls the policy once per process at injection time, cloakd
 * owns the mount lifecycle and pushes mount reports back into launchdhook.
 */

typedef struct {
	bool enabled;
	bool hideMounts;        // filter jailbreak mounts from getfsstat/statfs
	bool hideCredentials;   // mask elevated ucred/kinfo_proc/csops results
	bool hideTrustcache;    // hide CS_DEBUGGED & friends from csops STATUS
	// R38（用户 2026-08-29 11:41 定案）屏蔽软件双形态档位：
	//   0 = 仅 jbroot/bind 隐藏（未启用形态时的兜底）
	//   1 = 基础档（普通 roothide）：三 hide 全开，挂载白名单宽松
	//   2 = 深档-过渡（getfsstat 白名单外挂载全隐，对齐 interpose 实现）
	//   3 = 深档（rootful 态）：白名单外全隐（rootful 的 fakefs/overlay 六目录
	//       挂载面大，检测面大，需最激进过滤）
	// 语义=等级越高隐藏越深（原注释"0=paranoid"与 interpose 实现相反，已订正）
	uint64_t stealthLevel;
	// R40（用户 2026-08-29 17:00 定案）：黑名单制——屏蔽软件有黑名单，拉黑的 app
	// 检测不到越狱环境；不在名单的 app（文件管理器等越狱生态工具）正常可见可管。
	// true（默认）：cloak 过滤只对 aegis 名单内进程生效（名单外=信任态）；
	// false：旧语义（除 root/受信外全隐藏，R40 前的行为，留作兜底开关）。
	bool blacklistMode;
} cloak_policy_t;

typedef struct {
	bool active;            // cloakd running, mounts up
	char mountPoint[256];   // where the cloak overlay is mounted
	char error[256];        // last error reported by cloakd, if any
} cloak_mount_status_t;

// Policy access ---------------------------------------------------------------

// Client-side call into launchdhook.  Returns 0 on success.
int cloak_get_policy(cloak_policy_t *policyOut);

// Serialize / deserialize (used on the wire and by systemhook caching).
xpc_object_t cloak_policy_serialize(const cloak_policy_t *policy);
void cloak_policy_deserialize(xpc_object_t xdict, cloak_policy_t *policy);

// State mutation (requires platform privileges) -------------------------------

int cloak_enable(void);
int cloak_disable(void);
int cloak_set_options(const cloak_policy_t *policy);
int cloak_report_mount(const char *mountPoint, const char *error);

// Mount status ----------------------------------------------------------------

// Combined view for jbctl / the app UI.
int cloak_get_mount_status(cloak_mount_status_t *statusOut);

#endif
