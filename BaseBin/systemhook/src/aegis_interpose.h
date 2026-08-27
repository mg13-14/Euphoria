#ifndef AEGIS_INTERPOSE_H
#define AEGIS_INTERPOSE_H

#include <stdbool.h>

/*
 * Euphoria aegis interposition (systemhook side)
 *
 * Whereas cloak hides the jailbreak *system-wide* (mounts, credentials,
 * trustcache), aegis shields *specific applications* from detecting it:
 * for every process whose executable matches the aegis shield list, the
 * interposer suppresses jailbreak-detection syscalls and scrubs the spawn
 * environment so the app (and its children) cannot see injection.
 *
 *   - stat / lstat / stat64 / lstat64 / fstatat / access / faccessat /
 *     open / openat: return ENOENT for paths classified as jailbreak
 *     artefacts by aegis_path_is_jailbreak_artefact()
 *   - posix_spawn / posix_spawnp: strip DYLD_INSERT_LIBRARIES and the
 *     other injection env vars from the child environment
 *   - getfsent / getmntinfo / getfsstat64: hide jailbreak-related mounts
 *     (complementary to cloak, applied only to shielded apps)
 *
 * Credential scrubbing (sysctl KERN_PROC) is intentionally NOT done here:
 * cloak already hides credentials system-wide when cloakHideCredentials
 * is on, and double-hooking sysctl would just create a conflict.
 */

void aegis_interpose_init(void);

#endif
