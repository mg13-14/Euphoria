#include "jbserver_global.h"
#include "jbsettings.h"

#include <libjailbreak/codesign.h>
#include <libjailbreak/aegis.h>
#include <libjailbreak/libjailbreak.h>
#include <libjailbreak/info.h>
#include <libproc.h>
#include <paths.h>
#include <string.h>
#include <stdlib.h>
#include <sys/param.h>

/*
 * Euphoria aegis domain (JBS_DOMAIN_AEGIS)
 *
 * Mirror of the cloak domain's permission model: GET_POLICY is reachable
 * from every process (systemhook needs it in each process to decide
 * whether to apply per-app shielding), while every mutating action
 * re-verifies that the caller is a platform binary via csops_audittoken.
 *
 * Runtime state lives in launchdhook's address space.  The enabled flag
 * and the default shield level are persisted through the jbinfo mechanism
 * (JAILBREAK_SETTINGS_ITERATE); the per-app list is owned by aegisd and
 * mirrored to JBROOT_PATH("/basebin/aegis.conf") for human editing.
 */

static aegis_policy_t gAegisPolicy = { 0 };
static bool gAegisMountActive = false;
static char gAegisMountPoint[MAXPATHLEN] = { 0 };
static char gAegisLastError[MAXPATHLEN] = { 0 };

static bool aegis_caller_is_platform(audit_token_t *callerToken)
{
	if (!callerToken) return false;
	pid_t pid = audit_token_to_pid(*callerToken);
	uint32_t csflags = 0;
	if (csops_audittoken(pid, CS_OPS_STATUS, &csflags, sizeof(csflags), callerToken) != 0) return false;
	return (csflags & CS_PLATFORM_BINARY);
}

static int aegis_server_get_policy(void *a1, void *a2, void *a3, void *a4, void *a5, void *a6, void *a7, void *a8)
{
	/* out args: policy(dict), mountActive(bool), mountPoint(string), error(string) */
	if (a1) *(xpc_object_t *)a1 = aegis_policy_serialize(&gAegisPolicy);
	if (a2) *(bool *)a2 = gAegisMountActive;
	if (a3) *(char **)a3 = strdup(gAegisMountPoint[0] ? gAegisMountPoint : "");
	if (a4) *(char **)a4 = strdup(gAegisLastError[0] ? gAegisLastError : "");
	return 0;
}

static int aegis_server_enable(void *a1, void *a2, void *a3, void *a4, void *a5, void *a6, void *a7, void *a8)
{
	audit_token_t *callerToken = (audit_token_t *)a1;
	if (!aegis_caller_is_platform(callerToken)) return -2;
	gAegisPolicy.enabled = true;
	return 0;
}

static int aegis_server_disable(void *a1, void *a2, void *a3, void *a4, void *a5, void *a6, void *a7, void *a8)
{
	audit_token_t *callerToken = (audit_token_t *)a1;
	if (!aegis_caller_is_platform(callerToken)) return -2;
	gAegisPolicy.enabled = false;
	return 0;
}

static int aegis_server_set_default_level(void *a1, void *a2, void *a3, void *a4, void *a5, void *a6, void *a7, void *a8)
{
	audit_token_t *callerToken = (audit_token_t *)a1;
	if (!aegis_caller_is_platform(callerToken)) return -2;
	if (!a2) return -1;
	uint64_t level = *(uint64_t *)a2;
	if (level > AEGIS_LEVEL_PARANOID) return -1;
	gAegisPolicy.defaultLevel = level;
	return 0;
}

static int aegis_server_add_app(void *a1, void *a2, void *a3, void *a4, void *a5, void *a6, void *a7, void *a8)
{
	audit_token_t *callerToken = (audit_token_t *)a1;
	if (!aegis_caller_is_platform(callerToken)) return -2;
	const char *bundleId = (const char *)a2;
	if (!bundleId || !bundleId[0]) return -1;
	uint64_t level = a3 ? *(uint64_t *)a3 : AEGIS_LEVEL_FULL;

	/* Update existing entry in place if present */
	for (uint32_t i = 0; i < gAegisPolicy.appCount; i++) {
		if (strncmp(gAegisPolicy.appBundleIds[i], bundleId, AEGIS_BUNDLE_ID_MAX) == 0) {
			gAegisPolicy.appLevels[i] = level;
			return 0;
		}
	}
	if (gAegisPolicy.appCount >= AEGIS_MAX_APPS) return -1;
	strlcpy(gAegisPolicy.appBundleIds[gAegisPolicy.appCount], bundleId, AEGIS_BUNDLE_ID_MAX);
	gAegisPolicy.appLevels[gAegisPolicy.appCount] = level;
	gAegisPolicy.appCount++;
	return 0;
}

static int aegis_server_remove_app(void *a1, void *a2, void *a3, void *a4, void *a5, void *a6, void *a7, void *a8)
{
	audit_token_t *callerToken = (audit_token_t *)a1;
	if (!aegis_caller_is_platform(callerToken)) return -2;
	const char *bundleId = (const char *)a2;
	if (!bundleId) return -1;

	for (uint32_t i = 0; i < gAegisPolicy.appCount; i++) {
		if (strncmp(gAegisPolicy.appBundleIds[i], bundleId, AEGIS_BUNDLE_ID_MAX) == 0) {
			/* shift down */
			for (uint32_t j = i; j + 1 < gAegisPolicy.appCount; j++) {
				strlcpy(gAegisPolicy.appBundleIds[j], gAegisPolicy.appBundleIds[j+1], AEGIS_BUNDLE_ID_MAX);
				gAegisPolicy.appLevels[j] = gAegisPolicy.appLevels[j+1];
			}
			gAegisPolicy.appCount--;
			memset(gAegisPolicy.appBundleIds[gAegisPolicy.appCount], 0, AEGIS_BUNDLE_ID_MAX);
			gAegisPolicy.appLevels[gAegisPolicy.appCount] = 0;
			return 0;
		}
	}
	return 0; /* not found is not an error */
}

static int aegis_server_clear_apps(void *a1, void *a2, void *a3, void *a4, void *a5, void *a6, void *a7, void *a8)
{
	audit_token_t *callerToken = (audit_token_t *)a1;
	if (!aegis_caller_is_platform(callerToken)) return -2;
	gAegisPolicy.appCount = 0;
	memset(gAegisPolicy.appBundleIds, 0, sizeof(gAegisPolicy.appBundleIds));
	memset(gAegisPolicy.appLevels, 0, sizeof(gAegisPolicy.appLevels));
	return 0;
}

static int aegis_mount_report(void *a1, void *a2, void *a3, void *a4, void *a5, void *a6, void *a7, void *a8)
{
	audit_token_t *callerToken = (audit_token_t *)a1;
	if (!aegis_caller_is_platform(callerToken)) return -2;
	const char *mountPoint = (const char *)a2;
	const char *error = (const char *)a3;

	if (mountPoint && mountPoint[0]) {
		strlcpy(gAegisMountPoint, mountPoint, sizeof(gAegisMountPoint));
		gAegisMountActive = true;
	}
	else {
		gAegisMountPoint[0] = '\0';
		gAegisMountActive = false;
	}
	if (error) strlcpy(gAegisLastError, error, sizeof(gAegisLastError));
	else      gAegisLastError[0] = '\0';
	return 0;
}

struct jbserver_domain gAegisDomain = {
	.permissionHandler = NULL, // GET_POLICY systemwide; mutations check per-action
	.actions = {
		// JBS_AEGIS_GET_POLICY
		{
			.handler = aegis_server_get_policy,
			.args = (jbserver_arg[]){
				{ .name = "policy",     .type = JBS_TYPE_DICTIONARY, .out = true },
				{ .name = "mountActive", .type = JBS_TYPE_BOOL,      .out = true },
				{ .name = "mountPoint",  .type = JBS_TYPE_STRING,     .out = true },
				{ .name = "error",       .type = JBS_TYPE_STRING,     .out = true },
				{ 0 },
			},
		},
		// JBS_AEGIS_ENABLE
		{
			.handler = aegis_server_enable,
			.args = (jbserver_arg[]){
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ 0 },
			},
		},
		// JBS_AEGIS_DISABLE
		{
			.handler = aegis_server_disable,
			.args = (jbserver_arg[]){
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ 0 },
			},
		},
		// JBS_AEGIS_SET_DEFAULT_LEVEL
		{
			.handler = aegis_server_set_default_level,
			.args = (jbserver_arg[]){
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ .name = "level",        .type = JBS_TYPE_UINT64,        .out = false },
				{ 0 },
			},
		},
		// JBS_AEGIS_ADD_APP
		{
			.handler = aegis_server_add_app,
			.args = (jbserver_arg[]){
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ .name = "bundleId",     .type = JBS_TYPE_STRING,       .out = false },
				{ .name = "level",        .type = JBS_TYPE_UINT64,       .out = false },
				{ 0 },
			},
		},
		// JBS_AEGIS_REMOVE_APP
		{
			.handler = aegis_server_remove_app,
			.args = (jbserver_arg[]){
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ .name = "bundleId",     .type = JBS_TYPE_STRING,       .out = false },
				{ 0 },
			},
		},
		// JBS_AEGIS_CLEAR_APPS
		{
			.handler = aegis_server_clear_apps,
			.args = (jbserver_arg[]){
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ 0 },
			},
		},
		// JBS_AEGIS_MOUNT_REPORT
		{
			.handler = aegis_mount_report,
			.args = (jbserver_arg[]){
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ .name = "mountPoint",   .type = JBS_TYPE_STRING,       .out = false },
				{ .name = "error",        .type = JBS_TYPE_STRING,       .out = false },
				{ 0 },
			},
		},
		{ 0 },
	},
};
