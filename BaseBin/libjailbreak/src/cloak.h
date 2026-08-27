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
	uint64_t stealthLevel;  // 0 = paranoid (default), >0 = relaxed filters
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
