#include "jbsettings.h"
#include <libjailbreak/rootful.h>
#include <libjailbreak/info.h>

int jbsettings_get(const char *key, xpc_object_t *valueOut)
{
	if (!key)	return -1;

	if (!strcmp(key, "markAppsAsDebugged")) {
		*valueOut = xpc_bool_create(jbsetting(markAppsAsDebugged));
		return 0;
	}
	else if (!strcmp(key, "jetsamMultiplier")) {
		*valueOut = xpc_double_create(jbsetting(jetsamMultiplier));
		return 0;
	}
	// Euphoria cloak (stealth) settings
	else if (!strcmp(key, "cloakEnabled")) {
		*valueOut = xpc_bool_create(jbsetting(cloakEnabled));
		return 0;
	}
	else if (!strcmp(key, "cloakHideMounts")) {
		*valueOut = xpc_bool_create(jbsetting(cloakHideMounts));
		return 0;
	}
	else if (!strcmp(key, "cloakHideCredentials")) {
		*valueOut = xpc_bool_create(jbsetting(cloakHideCredentials));
		return 0;
	}
	else if (!strcmp(key, "cloakHideTrustcache")) {
		*valueOut = xpc_bool_create(jbsetting(cloakHideTrustcache));
		return 0;
	}
	else if (!strcmp(key, "cloakStealthLevel")) {
		*valueOut = xpc_uint64_create(jbsetting(cloakStealthLevel));
		return 0;
	}
	// Euphoria aegis (per-app shielding) settings
	else if (!strcmp(key, "aegisEnabled")) {
		*valueOut = xpc_bool_create(jbsetting(aegisEnabled));
		return 0;
	}
	else if (!strcmp(key, "aegisDefaultLevel")) {
		*valueOut = xpc_uint64_create(jbsetting(aegisDefaultLevel));
		return 0;
	}
	// Euphoria rootful user toggle (App Settings UI)
	else if (!strcmp(key, "rootfulUserEnabled")) {
		*valueOut = xpc_bool_create(jbsetting(rootfulUserEnabled));
		return 0;
	}
	// Read-only: whether this device sits inside the rootful matrix
	// (A12/A13 @ iOS 16.6.1-18.7.1). The App greys the toggle out when
	// this is false. Computed server-side; the set branch rejects it.
	else if (!strcmp(key, "rootfulSupported")) {
		*valueOut = xpc_bool_create(rootful_supported_configuration());
		return 0;
	}
	return -1;
}

int jbsettings_set(const char *key, xpc_object_t value)
{
	if (!strcmp(key, "markAppsAsDebugged") && xpc_get_type(value) == XPC_TYPE_BOOL) {
		gSystemInfo.jailbreakSettings.markAppsAsDebugged = xpc_bool_get_value(value);
		return 0;
	}
	else if (!strcmp(key, "jetsamMultiplier") && xpc_get_type(value) == XPC_TYPE_DOUBLE) {
		gSystemInfo.jailbreakSettings.jetsamMultiplier = xpc_double_get_value(value);
		return 0;
	}
	// Euphoria cloak (stealth) settings
	else if (!strcmp(key, "cloakEnabled") && xpc_get_type(value) == XPC_TYPE_BOOL) {
		gSystemInfo.jailbreakSettings.cloakEnabled = xpc_bool_get_value(value);
		return 0;
	}
	else if (!strcmp(key, "cloakHideMounts") && xpc_get_type(value) == XPC_TYPE_BOOL) {
		gSystemInfo.jailbreakSettings.cloakHideMounts = xpc_bool_get_value(value);
		return 0;
	}
	else if (!strcmp(key, "cloakHideCredentials") && xpc_get_type(value) == XPC_TYPE_BOOL) {
		gSystemInfo.jailbreakSettings.cloakHideCredentials = xpc_bool_get_value(value);
		return 0;
	}
	else if (!strcmp(key, "cloakHideTrustcache") && xpc_get_type(value) == XPC_TYPE_BOOL) {
		gSystemInfo.jailbreakSettings.cloakHideTrustcache = xpc_bool_get_value(value);
		return 0;
	}
	else if (!strcmp(key, "cloakStealthLevel") && xpc_get_type(value) == XPC_TYPE_UINT64) {
		gSystemInfo.jailbreakSettings.cloakStealthLevel = xpc_uint64_get_value(value);
		return 0;
	}
	// Euphoria aegis (per-app shielding) settings
	else if (!strcmp(key, "aegisEnabled") && xpc_get_type(value) == XPC_TYPE_BOOL) {
		gSystemInfo.jailbreakSettings.aegisEnabled = xpc_bool_get_value(value);
		return 0;
	}
	else if (!strcmp(key, "aegisDefaultLevel") && xpc_get_type(value) == XPC_TYPE_UINT64) {
		gSystemInfo.jailbreakSettings.aegisDefaultLevel = xpc_uint64_get_value(value);
		return 0;
	}
	// Euphoria rootful user toggle (App Settings UI)
	else if (!strcmp(key, "rootfulUserEnabled") && xpc_get_type(value) == XPC_TYPE_BOOL) {
		gSystemInfo.jailbreakSettings.rootfulUserEnabled = xpc_bool_get_value(value);
		return 0;
	}
	return -1;
}