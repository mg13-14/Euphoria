#include "aegis.h"
#include "jbclient_xpc.h"
#include "jbserver_domains.h"
#include "jbroot.h"
#include "util.h"

#include <string.h>
#include <stdlib.h>

// 构建修复：string_has_prefix 在树中无定义，此处补最小实现
static bool string_has_prefix(const char *str, const char *prefix)
{
        if (!str || !prefix) return false;
        size_t plen = strlen(prefix);
        return strncmp(str, prefix, plen) == 0;
}

xpc_object_t aegis_policy_serialize(const aegis_policy_t *policy)
{
        xpc_object_t xdict = xpc_dictionary_create_empty();
        xpc_dictionary_set_bool(xdict, "enabled", policy->enabled);
        xpc_dictionary_set_uint64(xdict, "defaultLevel", policy->defaultLevel);

        xpc_object_t apps = xpc_array_create(NULL, 0);
        for (uint32_t i = 0; i < policy->appCount && i < AEGIS_MAX_APPS; i++) {
                xpc_object_t entry = xpc_dictionary_create(NULL, NULL, 0);
                xpc_dictionary_set_string(entry, "id", policy->appBundleIds[i]);
                xpc_dictionary_set_uint64(entry, "level", policy->appLevels[i]);
                xpc_array_append_value(apps, entry);
        }
        xpc_dictionary_set_value(xdict, "apps", apps);
        xpc_release(apps);
        return xdict;
}

void aegis_policy_deserialize(xpc_object_t xdict, aegis_policy_t *policy)
{
        if (!xdict || xpc_get_type(xdict) != XPC_TYPE_DICTIONARY) return;
        memset(policy, 0, sizeof(*policy));
        policy->enabled      = xpc_dictionary_get_bool(xdict, "enabled");
        policy->defaultLevel = xpc_dictionary_get_uint64(xdict, "defaultLevel");

        xpc_object_t apps = xpc_dictionary_get_array(xdict, "apps");
        if (apps) {
                size_t count = xpc_array_get_count(apps);
                policy->appCount = (uint32_t)((count < AEGIS_MAX_APPS) ? count : AEGIS_MAX_APPS);
                for (uint32_t i = 0; i < policy->appCount; i++) {
                        xpc_object_t entry = xpc_array_get_value(apps, i);
                        const char *id = xpc_dictionary_get_string(entry, "id");
                        if (id) strlcpy(policy->appBundleIds[i], id, AEGIS_BUNDLE_ID_MAX);
                        policy->appLevels[i] = xpc_dictionary_get_uint64(entry, "level");
                }
        }
}

int aegis_get_policy(aegis_policy_t *policyOut)
{
        if (policyOut) memset(policyOut, 0, sizeof(*policyOut));

        xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_AEGIS, JBS_AEGIS_GET_POLICY, NULL);
        if (!xreply) return -1;

        int result = (int)xpc_dictionary_get_int64(xreply, "result");
        if (result == 0 && policyOut) {
                xpc_object_t xpolicy = xpc_dictionary_get_value(xreply, "policy");
                aegis_policy_deserialize(xpolicy, policyOut);
        }
        xpc_release(xreply);
        return result;
}

int aegis_enable(void)
{
        xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_AEGIS, JBS_AEGIS_ENABLE, NULL);
        if (!xreply) return -1;
        int r = (int)xpc_dictionary_get_int64(xreply, "result");
        xpc_release(xreply);
        return r;
}

int aegis_disable(void)
{
        xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_AEGIS, JBS_AEGIS_DISABLE, NULL);
        if (!xreply) return -1;
        int r = (int)xpc_dictionary_get_int64(xreply, "result");
        xpc_release(xreply);
        return r;
}

int aegis_set_default_level(uint64_t level)
{
        xpc_object_t xargs = xpc_dictionary_create_empty();
        xpc_dictionary_set_uint64(xargs, "level", level);
        xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_AEGIS, JBS_AEGIS_SET_DEFAULT_LEVEL, xargs);
        xpc_release(xargs);
        if (!xreply) return -1;
        int r = (int)xpc_dictionary_get_int64(xreply, "result");
        xpc_release(xreply);
        return r;
}

int aegis_add_app(const char *bundleId, uint64_t level)
{
        xpc_object_t xargs = xpc_dictionary_create_empty();
        xpc_dictionary_set_string(xargs, "bundleId", bundleId);
        xpc_dictionary_set_uint64(xargs, "level", level);
        xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_AEGIS, JBS_AEGIS_ADD_APP, xargs);
        xpc_release(xargs);
        if (!xreply) return -1;
        int r = (int)xpc_dictionary_get_int64(xreply, "result");
        xpc_release(xreply);
        return r;
}

int aegis_remove_app(const char *bundleId)
{
        xpc_object_t xargs = xpc_dictionary_create_empty();
        xpc_dictionary_set_string(xargs, "bundleId", bundleId);
        xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_AEGIS, JBS_AEGIS_REMOVE_APP, xargs);
        xpc_release(xargs);
        if (!xreply) return -1;
        int r = (int)xpc_dictionary_get_int64(xreply, "result");
        xpc_release(xreply);
        return r;
}

int aegis_clear_apps(void)
{
        xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_AEGIS, JBS_AEGIS_CLEAR_APPS, NULL);
        if (!xreply) return -1;
        int r = (int)xpc_dictionary_get_int64(xreply, "result");
        xpc_release(xreply);
        return r;
}

int aegis_report_mount(const char *mountPoint, const char *error)
{
        xpc_object_t xargs = xpc_dictionary_create_empty();
        if (mountPoint) xpc_dictionary_set_string(xargs, "mountPoint", mountPoint);
        if (error)      xpc_dictionary_set_string(xargs, "error", error);
        xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_AEGIS, JBS_AEGIS_MOUNT_REPORT, xargs);
        xpc_release(xargs);
        if (!xreply) return -1;
        int r = (int)xpc_dictionary_get_int64(xreply, "result");
        xpc_release(xreply);
        return r;
}

/* Jailbreak artefact path classifier.
 *
 * Conservative: only returns true for paths whose existence is *always* a
 * jailbreak tell. Generic system paths (/, /var, /usr) are never classified
 * as artefacts here — apps probing those are not detecting a jailbreak. */
bool aegis_path_is_jailbreak_artefact(const char *path)
{
        if (!path || path[0] != '/') return false;

        /* jbroot and its standard subdirs (the canonical rootless tell) */
        static const char *jb_paths[] = {
                "/var/jb",
                "/var/jb/basebin",
                "/var/jb/usr/lib",
                "/var/jb/usr/bin",
                "/var/jb/etc",
                "/var/jb/Library",
                "/var/jb/.basebin",       /* cloak marker */
                /* classic jailbreak binaries still present in the rootless era */
                "/usr/bin/ssh",
                "/usr/bin/scp",
                "/usr/sbin/sshd",
                "/usr/libexec/ssh-keysign",
                /* common tweak loader path (rootless) */
                "/var/jb/usr/lib/TweakLoader.dylib",
                "/var/jb/usr/lib/substrate",
                "/var/jb/usr/lib/ellekit",
                /* Sileo / Zebra bootstrap markers */
                "/var/jb/.sileo_installed",
                "/var/jb/.zebra_installed",
                /* /basebin is the persistent basebin dir */
                "/private/preboot",       /* preboot where jbroot usually lives */
        };
        for (size_t i = 0; i < sizeof(jb_paths)/sizeof(jb_paths[0]); i++) {
                if (string_has_prefix(path, jb_paths[i])) return true;
        }

        /* Cydia Substrate legacy paths (rootful era) — still tell-tale */
        static const char *legacy_paths[] = {
                "/Applications/Cydia.app",
                "/Applications/Sileo.app",
                "/Applications/Zebra.app",
                "/Library/MobileSubstrate",
                "/Library/MobileSubstrate/DynamicLibraries",
                "/usr/lib/substrate",
                "/usr/lib/substrate-substitute",
                "/usr/lib/libsubstitute.dylib",
                "/.bootstrapped",
                "/etc/apt",
        };
        for (size_t i = 0; i < sizeof(legacy_paths)/sizeof(legacy_paths[0]); i++) {
                if (string_has_prefix(path, legacy_paths[i])) return true;
        }

        return false;
}
