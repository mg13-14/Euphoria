#ifndef LJB_AEGIS_H
#define LJB_AEGIS_H

#include <stdbool.h>
#include <stdint.h>
#include <xpc/xpc.h>

/*
 * Euphoria aegis — dedicated per-app shielding subsystem
 *
 * While cloak hides the *existence* of the jailbreak at the system level
 * (mounts, credentials, trustcache), aegis shields specific *applications*
 * from detecting it: for every process whose bundle id is on the shield
 * list, the aegis systemhook interposer intercepts the jailbreak-detection
 * surface (file-existence syscalls, dyld enumeration, spawn env scrubbing,
 * sysctl credential queries, sandbox checks) and returns innocuous results.
 *
 * The component mirrors cloakd's lifecycle: aegisd brings up a cover mount
 * during bootstrap (the "treat it as a mount" persistence requirement),
 * keeps the shield policy synchronised across the running system through
 * the JBS_DOMAIN_AEGIS XPC domain, and stays resident after jailbreak.
 *
 * Shield levels (escalating aggressiveness):
 *   AEGIS_LEVEL_OFF     = 0  (no shielding — process sees everything)
 *   AEGIS_LEVEL_LITE    = 1  (hide jailbreak file paths + spawn env scrub)
 *   AEGIS_LEVEL_FULL    = 2  (lite + dyld enumeration filter + sandbox spoof)
 *   AEGIS_LEVEL_PARANOID = 3 (full + credential scrub + mount enumeration hide)
 */

#define AEGIS_LEVEL_OFF       0
#define AEGIS_LEVEL_LITE      1
#define AEGIS_LEVEL_FULL     2
#define AEGIS_LEVEL_PARANOID 3

#define AEGIS_MAX_APPS         256
#define AEGIS_BUNDLE_ID_MAX   256

typedef struct {
	bool     enabled;
	uint64_t defaultLevel;
	/* Fixed-size app list (the full list is also mirrored to
	 * JBROOT_PATH("/basebin/aegis.conf") for human editing). The in-jbinfo
	 * copy is the authoritative serialised state. */
	uint32_t appCount;
	char     appBundleIds[AEGIS_MAX_APPS][AEGIS_BUNDLE_ID_MAX];
	uint64_t appLevels[AEGIS_MAX_APPS];
} aegis_policy_t;

typedef struct {
	bool active;
	char mountPoint[1024];
	char error[1024];
} aegis_mount_status_t;

/* Client API (libjailbreak consumers — aegisd, systemhook, jbctl, app) */
int  aegis_get_policy(aegis_policy_t *policyOut);
int  aegis_enable(void);
int  aegis_disable(void);
int  aegis_set_default_level(uint64_t level);
int  aegis_add_app(const char *bundleId, uint64_t level);
int  aegis_remove_app(const char *bundleId);
int  aegis_clear_apps(void);
int  aegis_report_mount(const char *mountPoint, const char *error);
int  aegis_get_mount_status(aegis_mount_status_t *statusOut);

xpc_object_t aegis_policy_serialize(const aegis_policy_t *policy);
void         aegis_policy_deserialize(xpc_object_t xdict, aegis_policy_t *policy);

/* Path classification — shared between the server and the interposer so
 * both sides agree on what counts as a "jailbreak artefact path" for the
 * purposes of file-existence syscall suppression. */
bool aegis_path_is_jailbreak_artefact(const char *path);

#endif
