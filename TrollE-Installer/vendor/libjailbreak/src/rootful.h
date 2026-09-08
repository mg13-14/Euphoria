#ifndef __ROOTFUL_H
#define __ROOTFUL_H

#include <stdint.h>
#include <stdbool.h>
#include <sys/errno.h>

/*
 * Euphoria rootful engine
 *
 * Dopamine (upstream) is strictly rootless: the system volume stays sealed and
 * read-only, everything lives under the jbroot (/var/jb).
 *
 * Euphoria adds an optional rootful mode for the supported configuration
 * (A12/A13, iOS 16.6.1 - 18.7.1, user requirement of 2026-08-26 17:27):
 *
 *   1. In-memory remount of the root filesystem (clears MNT_RDONLY on the
 *      root mount after the seal has already been evaluated at boot time).
 *      This yields a *true* uid 0, read-write "/" experience for the running
 *      boot session.  Changes are page-cache backed and MUST NOT be expected
 *      to survive a reboot; the on-disk seal remains untouched unless
 *      persistence is explicitly requested (dangerous, off by default).
 *
 *   2. Overlay fallback: bindfs overlays for well-known system paths so that
 *      a writable view of "/", "/usr", "/etc" ... is presented even when the
 *      in-memory remount cannot be validated for the running kernel build.
 *
 * Every kernel write performed here is preceded by content validation
 * (mount entry sanity checks). If validation fails, the engine refuses to
 * touch kernel memory and reports ENOTSUP instead of corrupting anything.
 */

// Overall state of the rootful subsystem
typedef struct {
        bool supportedConfig;    // device is in the supported A12/A13 window (iOS 16.6.1 - 18.7.1)
        bool fakefsActive;       // fakefs non-sealed volume + remount succeeded (primary path)
        bool rootMountedRW;      // in-memory MNT_RDONLY clear succeeded (fallback path)
        bool overlayActive;      // bindfs overlays are up
        bool sealDisabled;       // runtime seal enforcement patches applied
        char lastError[256];
} rootful_status_t;

// Returns true when the running device is inside the officially supported
// window of this tool: A12/A13 (arm64e, no jitbox) on iOS 16.6.1 - 18.7.1.
bool rootful_supported_configuration(void);

// Populate *status with the current rootful state (safe to call anytime).
int rootful_get_status(rootful_status_t *status);

// Enable rootful for the current boot session:
//   - attempt in-memory root remount (validated)
//   - on failure (or additionally, when overlays_requested) bring up bindfs
//     overlays for the classic system directories
// Returns 0 on success, an errno otherwise. status is always refreshed.
int rootful_enable(bool overlays_requested, rootful_status_t *status);

// Progress callback: receives one JSON stage-event line per call from the
// bootstrapfs engine (schema: BaseBin/bootstrapfs/src/progress.h; consumer
// spec: docs/06-rootful开关与进度视觉交付包_T15.md).
typedef void (*rootful_progress_fn)(const char *jsonLine, void *ctx);

// rootful_enable with engine progress streaming (rootful_enable == _ex with
// NULL progress).  The callback fires from the same thread, while the engine
// child is running; keep it fast (printf/log-forward level).
int rootful_enable_ex(bool overlays_requested, rootful_progress_fn progress, void *ctx, rootful_status_t *status);

// Bring everything back to rootless-only (unmount overlays; the in-memory
// mount flag clear cannot be meaningfully reverted and is simply dropped).
int rootful_disable(void);

// Internal: walk the kernel mount list and locate the mount whose
// f_mntonname is "/". Returns the kernel address of the mount struct or 0.
uint64_t rootful_find_root_mount(void);

#endif
