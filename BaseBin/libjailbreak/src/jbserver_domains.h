#ifndef JBSERVER_DOMAINS
#define JBSERVER_DOMAINS

// Domain: System-Wide
// Reachable from all processes
#define JBS_DOMAIN_SYSTEMWIDE 1
enum {
    JBS_SYSTEMWIDE_GET_JBROOT = 1,
    JBS_SYSTEMWIDE_GET_BOOT_UUID,
    JBS_SYSTEMWIDE_TRUST_FILE,
    JBS_SYSTEMWIDE_PROCESS_CHECKIN,
    JBS_SYSTEMWIDE_FORK_FIX,
    JBS_SYSTEMWIDE_CS_REVALIDATE,
    JBS_SYSTEMWIDE_JBSETTINGS_GET,
    JBS_SYSTEMWIDE_PERSONA_FIX,
};

// Domain: Platform
// Reachable from all processes that have CS_PLATFORMIZED or are entitled with platform-application or are the Euphoria app itself
#define JBS_DOMAIN_PLATFORM 2
enum {
    JBS_PLATFORM_SET_PROCESS_DEBUGGED = 1,
    JBS_PLATFORM_STAGE_JAILBREAK_UPDATE,
    JBS_PLATFORM_JBSETTINGS_SET,
    JBS_PLATFORM_SET_SYSTEMWIDE_DOMAIN_ENABLED,
};


// Domain: Watchdog
// Only reachable from watchdogd
#define JBS_DOMAIN_WATCHDOG 3
enum {
    JBS_WATCHDOG_INTERCEPT_USERSPACE_PANIC = 1,
    JBS_WATCHDOG_GET_LAST_USERSPACE_PANIC
};

// Domain: Root
// Only reachable from root processes
#define JBS_DOMAIN_ROOT 4
enum {
    JBS_ROOT_GET_PHYSRW = 1,
    JBS_ROOT_SIGN_THREAD,
    JBS_ROOT_GET_SYSINFO,
    JBS_ROOT_STEAL_UCRED,
    JBS_ROOT_SET_MAC_LABEL,
    JBS_ROOT_TRUSTCACHE_INFO,
    JBS_ROOT_TRUSTCACHE_ADD_CDHASH,
    JBS_ROOT_TRUSTCACHE_CLEAR,
};

// Domain: Euphoria
// Reachable exclusively from Euphoria app
#define JBS_DOMAIN_EUPHORIA 5
enum {
    JBS_EUPHORIA_IS_JAILBROKEN = 1,
    JBS_EUPHORIA_GET_ROOT,
    JBS_EUPHORIA_DROP_ROOT,
};

// Domain: Cloak
// Stealth subsystem that hides root privileges and jailbreak artefacts
// from untrusted processes while the jailbreak is active.
//
//   - GET_POLICY is reachable systemwide (systemhook needs it in every
//     process to know what has to be filtered)
//   - ENABLE / DISABLE / SET_OPTIONS / MOUNT_REPORT are restricted to
//     platform binaries (the Euphoria app, jbctl and cloakd itself)
#define JBS_DOMAIN_CLOAK 6
enum {
    JBS_CLOAK_GET_POLICY = 1,
    JBS_CLOAK_ENABLE,
    JBS_CLOAK_DISABLE,
    JBS_CLOAK_SET_OPTIONS,
    JBS_CLOAK_MOUNT_REPORT,
};

// Domain: Aegis
// Per-app shielding subsystem. Hides jailbreak-detection surface from
// designated applications (file-existence syscalls, spawn env scrubbing,
// mount enumeration). GET_POLICY is systemwide-reachable (systemhook
// needs it in each process); mutations are platform-binary restricted.
#define JBS_DOMAIN_AEGIS 7
enum {
    JBS_AEGIS_GET_POLICY = 1,
    JBS_AEGIS_ENABLE,
    JBS_AEGIS_DISABLE,
    JBS_AEGIS_SET_DEFAULT_LEVEL,
    JBS_AEGIS_ADD_APP,
    JBS_AEGIS_REMOVE_APP,
    JBS_AEGIS_CLEAR_APPS,
    JBS_AEGIS_MOUNT_REPORT,
};

#define JBS_BOOMERANG_DONE 42

#endif