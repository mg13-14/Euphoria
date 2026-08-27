#include "cloak.h"
#include "jbclient_xpc.h"
#include "jbserver_domains.h"

#include <string.h>

xpc_object_t cloak_policy_serialize(const cloak_policy_t *policy)
{
	xpc_object_t xdict = xpc_dictionary_create_empty();
	xpc_dictionary_set_bool(xdict, "enabled", policy->enabled);
	xpc_dictionary_set_bool(xdict, "hideMounts", policy->hideMounts);
	xpc_dictionary_set_bool(xdict, "hideCredentials", policy->hideCredentials);
	xpc_dictionary_set_bool(xdict, "hideTrustcache", policy->hideTrustcache);
	xpc_dictionary_set_uint64(xdict, "stealthLevel", policy->stealthLevel);
	return xdict;
}

void cloak_policy_deserialize(xpc_object_t xdict, cloak_policy_t *policy)
{
	if (!xdict || xpc_get_type(xdict) != XPC_TYPE_DICTIONARY) return;
	memset(policy, 0, sizeof(*policy));
	policy->enabled          = xpc_dictionary_get_bool(xdict, "enabled");
	policy->hideMounts       = xpc_dictionary_get_bool(xdict, "hideMounts");
	policy->hideCredentials  = xpc_dictionary_get_bool(xdict, "hideCredentials");
	policy->hideTrustcache   = xpc_dictionary_get_bool(xdict, "hideTrustcache");
	policy->stealthLevel     = xpc_dictionary_get_uint64(xdict, "stealthLevel");
}

int cloak_get_policy(cloak_policy_t *policyOut)
{
	if (policyOut) memset(policyOut, 0, sizeof(*policyOut));

	xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_CLOAK, JBS_CLOAK_GET_POLICY, NULL);
	if (!xreply) return -1;

	int result = (int)xpc_dictionary_get_int64(xreply, "result");
	if (result == 0 && policyOut) {
		policyOut->enabled         = xpc_dictionary_get_bool(xreply, "enabled");
		policyOut->hideMounts      = xpc_dictionary_get_bool(xreply, "hideMounts");
		policyOut->hideCredentials = xpc_dictionary_get_bool(xreply, "hideCredentials");
		policyOut->hideTrustcache  = xpc_dictionary_get_bool(xreply, "hideTrustcache");
		policyOut->stealthLevel    = xpc_dictionary_get_uint64(xreply, "stealthLevel");
	}
	xpc_release(xreply);
	return result;
}

int cloak_enable(void)
{
	xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_CLOAK, JBS_CLOAK_ENABLE, NULL);
	if (!xreply) return -1;
	int result = (int)xpc_dictionary_get_int64(xreply, "result");
	xpc_release(xreply);
	return result;
}

int cloak_disable(void)
{
	xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_CLOAK, JBS_CLOAK_DISABLE, NULL);
	if (!xreply) return -1;
	int result = (int)xpc_dictionary_get_int64(xreply, "result");
	xpc_release(xreply);
	return result;
}

int cloak_set_options(const cloak_policy_t *policy)
{
	xpc_object_t xargs = cloak_policy_serialize(policy);
	xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_CLOAK, JBS_CLOAK_SET_OPTIONS, xargs);
	xpc_release(xargs);
	if (!xreply) return -1;
	int result = (int)xpc_dictionary_get_int64(xreply, "result");
	xpc_release(xreply);
	return result;
}

int cloak_report_mount(const char *mountPoint, const char *error)
{
	xpc_object_t xargs = xpc_dictionary_create_empty();
	if (mountPoint) xpc_dictionary_set_string(xargs, "mountPoint", mountPoint);
	if (error) xpc_dictionary_set_string(xargs, "error", error);

	xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_CLOAK, JBS_CLOAK_MOUNT_REPORT, xargs);
	xpc_release(xargs);
	if (!xreply) return -1;
	int result = (int)xpc_dictionary_get_int64(xreply, "result");
	xpc_release(xreply);
	return result;
}

int cloak_get_mount_status(cloak_mount_status_t *statusOut)
{
	if (statusOut) memset(statusOut, 0, sizeof(*statusOut));

	xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_CLOAK, JBS_CLOAK_GET_POLICY, NULL);
	if (!xreply) return -1;

	int result = (int)xpc_dictionary_get_int64(xreply, "result");
	if (result == 0 && statusOut) {
		statusOut->active = xpc_dictionary_get_bool(xreply, "mountActive");
		const char *mountPoint = xpc_dictionary_get_string(xreply, "mountPoint");
		if (mountPoint) {
			strlcpy(statusOut->mountPoint, mountPoint, sizeof(statusOut->mountPoint));
		}
		const char *error = xpc_dictionary_get_string(xreply, "error");
		if (error) {
			strlcpy(statusOut->error, error, sizeof(statusOut->error));
		}
	}
	xpc_release(xreply);
	return result;
}
