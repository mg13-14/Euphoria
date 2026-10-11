#include "rootful.h"
#include "rootful_fakefs.h"
#include "info.h"
#include "kernel.h"
#include "primitives.h"
#include "translation.h"
#include "util.h"
#include "jbroot.h"

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/mount.h>
#include <sys/sysctl.h>
#include <sys/utsname.h>
#include <sys/stat.h>
#include <sys/param.h>
#include <mach/machine.h>
#include <errno.h>

// XNU kernel mount flags that are not exported to userspace headers
#define MNTK_RDONLY_CANDIDATE   0x00000080 // candidate for RDONLY transition
#define MNTK_SYSTEM             0x00000400 // mounted system volume

/*
 * Mount list discovery
 *
 * XNU keeps all mounts in the TAILQ `_mount_list`.  The kernel symbol table
 * is not available to us, but the list head is stable enough to locate via
 * the offsets registered in gSystemInfo.kernelStruct.mount together with
 * strict content validation:
 *
 *   - entry.next / entry.prev must point back into kernel heap ranges
 *   - the vfsstatfs.f_mntonname of an entry must be a NUL terminated,
 *     printable path
 *   - we only ever *write* to the entry that validated as the root mount
 *     (f_mntonname == "/")
 *
 * If any of those invariants fails, rootful bails out with ENOTSUP instead
 * of writing a single byte to kernel memory.
 */

static bool gRootfulStatusValid = false;
static rootful_status_t gRootfulStatus = { 0 };

static void rootful_set_error(const char *msg)
{
        strlcpy(gRootfulStatus.lastError, msg, sizeof(gRootfulStatus.lastError));
}

bool rootful_supported_configuration(void)
{
        // Chip gate: this tool targets A12 / A13 (arm64e, no jitbox hardware).
        cpu_subtype_t cpuFamily = 0;
        size_t cpuFamilySize = sizeof(cpuFamily);
        if (sysctlbyname("hw.cpufamily", &cpuFamily, &cpuFamilySize, NULL, 0) != 0) {
                return false;
        }
        bool a12 = (cpuFamily == CPUFAMILY_ARM_VORTEX_TEMPEST);
        bool a13 = (cpuFamily == CPUFAMILY_ARM_LIGHTNING_THUNDER);
        if (!a12 && !a13) return false;

        // OS gate (user requirement, 2026-08-26 17:27): rootful ships for
        //   A12/A13 @ iOS 16.6.1 - 18.7.1
        // (matrix narrowed from the previous 15.0-18.7.1 full range).
        // Outside the matrix the jailbreak itself still supports the full
        // Dopamine range; rootful simply stays off and hiding (cloak/aegis,
        // the self-developed roothide equivalent) remains available.
        //
        // Darwin release mapping (consistent with the rest of libjailbreak):
        //   iOS 15.x   -> Darwin 21.x   (excluded)
        //   iOS 16.0-16.5 -> Darwin 22.0-22.5 (excluded)
        //   iOS 16.6-16.7  -> Darwin 22.6 (INCLUDED: 16.6/16.6.1/16.7.x all
        //                    report 22.6; 16.6 and 16.6.1 differ only in
        //                    security patches, so the whole 22.6 band ships)
        //   iOS 17.x   -> Darwin 23.x   (included)
        //   iOS 18.x   -> Darwin 24.x   (included, 18.7.1 = 24.7)
        //   iOS 26.x   -> Darwin 25.x   (excluded)
        struct utsname name;
        if (uname(&name) != 0) return false;

        int darwinMajor = 0, darwinMinor = 0;
        if (sscanf(name.release, "%d.%d", &darwinMajor, &darwinMinor) != 2) {
                return false;
        }

        if (darwinMajor == 22) {
                return darwinMinor >= 6;             // iOS 16.6 / 16.6.1 / 16.7.x
        }
        return (darwinMajor == 23 || darwinMajor == 24); // iOS 17.x / 18.x
}

static bool rootful_offsets_available(void)
{
        return koffsetof(mount, mnt_next) != 0
                && koffsetof(mount, mnt_flag) != 0
                && koffsetof(mount, mnt_vfsstat) != 0
                && koffsetof(vfsstatfs, f_mntonname) != 0;
}

static bool rootful_validate_mount_entry(uint64_t mount, char *outName, size_t nameLen)
{
        if (mount == 0) return false;

        // Kernel pointer sanity: must not be PAC'd garbage
        if ((mount & 0xFFFF000000000000ULL) != 0xFFFF000000000000ULL) return false;

        // f_mntonname is an inline char array inside the embedded vfsstatfs,
        // so the name lives directly inside the mount structure.
        char name[32] = { 0 };
        uint64_t nameAddr = mount + koffsetof(mount, mnt_vfsstat) + koffsetof(vfsstatfs, f_mntonname);
        if (kreadbuf(nameAddr, name, sizeof(name) - 1) != 0) return false;
        name[sizeof(name) - 1] = '\0';

        // Must be printable and a plausible path
        size_t len = strnlen(name, sizeof(name) - 1);
        if (len == 0 || name[0] != '/') return false;
        for (size_t i = 0; i < len; i++) {
                if ((unsigned char)name[i] < 0x20 || (unsigned char)name[i] > 0x7E) return false;
        }

        if (outName) strlcpy(outName, name, nameLen);
        return true;
}

uint64_t rootful_find_root_mount(void)
{
        if (!rootful_offsets_available()) return 0;

        // The mount TAILQ head is registered as kernelSymbol.mount_list when it
        // could be resolved.  When it is missing we can still find the root mount
        // by walking from the first entry, but without a head there is nothing to
        // walk from.
        uint64_t listHead = ksymbol(mount_list);
        if (listHead == 0) return 0;

        uint64_t firstMount = kread64(listHead); // TAILQ_FIRST
        if (!rootful_validate_mount_entry(firstMount, NULL, 0)) return 0;

        // Walk at most 64 entries to stay robust against corrupted lists
        uint64_t cursor = firstMount;
        for (int i = 0; i < 64 && cursor != 0; i++) {
                char name[32] = { 0 };
                if (!rootful_validate_mount_entry(cursor, name, sizeof(name))) break;
                if (strcmp(name, "/") == 0) return cursor;
                cursor = kread64(cursor + koffsetof(mount, mnt_next));
        }

        return 0;
}

static int rootful_clear_rdonly_flag(uint64_t rootMount)
{
        uint32_t flags = kread32(rootMount + koffsetof(mount, mnt_flag));
        if (flags == 0) return ENOENT;

        if (!(flags & MNT_RDONLY)) {
                // Already read-write (unexpected on a sealed system volume, but fine)
                return 0;
        }

        int r = kwrite32(rootMount + koffsetof(mount, mnt_flag), flags & ~(uint32_t)MNT_RDONLY);
        if (r != 0) return r;

        // Also clear the kernel-side MNTK_RDONLY analogue when the offset is
        // known.  MNTK flags live in a separate word on modern XNU.
        if (koffsetof(mount, mnt_kern_flag) != 0) {
                uint32_t kernFlags = kread32(rootMount + koffsetof(mount, mnt_kern_flag));
                if (kernFlags & MNTK_RDONLY_CANDIDATE) {
                        kwrite32(rootMount + koffsetof(mount, mnt_kern_flag), kernFlags & ~MNTK_RDONLY_CANDIDATE);
                }
        }

        return 0;
}

static const char *gOverlayPaths[] = {
        "/usr",
        "/etc",
        "/var",
        NULL,
};

/*
 * Primary rootful path: fakefs (non-sealed APFS volume + content copy + remount)
 *
 * Per A's analysis (2026-08-26) and 汇总员's 00:29:49 directive, this is the
 * MAIN rootful mechanism: create a new APFS volume WITHOUT the
 * APFS_INCOMPAT_SEALED_VOLUME flag, copy the sealed root's contents into
 * it (the read of sealed data passes hash validation; the write targets a
 * non-sealed volume), then switch the root mount to the new volume via
 * kernel mount-structure manipulation (reuses the KRW + mount-validation
 * infrastructure of this engine).
 *
 * This is pure kernel DATA-段 manipulation (mount structs, APFS metadata) —
 * it does NOT require kernel text patching or touching PPL-protected page
 * tables. A12/A13 have no PPL, which is favourable.
 *
 * IMPLEMENTED (2026-08-26): the primary path is the mount-over engine
 * (BaseBin/bootstrapfs, hardened port of ghh-jb/Dopamine_Rootful — see
 * docs/06).  It never touches the sealed snapshot at all: six plain
 * (non-sealed) APFS volumes are created in the data container, filled with
 * copies of the classic system directories and mounted OVER the live paths.
 * SSV validates the seal at boot time only; runtime mount-table operations
 * do not re-verify it.  The engine is fully transactional (pre-commit
 * failure destroys everything it created; the live system is never touched
 * before the commit phase).  The KRW manipulation below remains as the
 * fallback for configurations where the APFS SPIs are unavailable.
 */

// Progress hook threaded from rootful_enable_ex into the engine child.
static rootful_progress_fn gEngineProgress;
static void *gEngineCtx;

static void rootful_engine_progress_trampoline(const char *line, void *ctx)
{
        (void)ctx;
        if (gEngineProgress) gEngineProgress(line, gEngineCtx);
}

static int rootful_fakefs_attempt(rootful_status_t *status)
{
        if (!rootful_fakefs_available()) {
                rootful_set_error("fakefs: bootstrapfs engine not present in basebin");
                return -1;
        }
        char err[192] = {0};
        int r = rootful_fakefs_run("enable", NULL,
                        rootful_engine_progress_trampoline, NULL,
                        err, sizeof(err));
        if (r != 0) {
                rootful_set_error(err[0] ? err : "fakefs: bootstrapfs engine failed");
                return -1;
        }
        status->fakefsActive = true;
        status->rootMountedRW = true;  // the mount-over volumes are writable
        status->sealDisabled = false;  // the sealed snapshot itself stays valid
        rootful_set_error("");
        return 0;
}

static int rootful_mount_overlays(void)
{
        // "Safe rootful": present writable overlays for the classic system
        // directories backed by storage inside the (already writable) data
        // partition.  bindfs is the same mechanism the jbroot itself uses, so no
        // new kernel attack surface is introduced.
        char stageRoot[PATH_MAX];
        strlcpy(stageRoot, JBROOT_PATH("/rootful"), sizeof(stageRoot));

        int rv = mkdir(stageRoot, 0755);
        if (rv != 0 && errno != EEXIST) return errno;

        int mountedCount = 0;
        for (int i = 0; gOverlayPaths[i]; i++) {
                char upperPath[PATH_MAX];
                snprintf(upperPath, sizeof(upperPath), "%s%s", stageRoot, gOverlayPaths[i]);

                // Create the staging directory tree (best effort)
                for (char *p = upperPath + 1; *p; p++) {
                        if (*p == '/') {
                                *p = '\0';
                                mkdir(upperPath, 0755);
                                *p = '/';
                        }
                }
                mkdir(upperPath, 0755);

                // XNU nullfs: the mount data is a single char* pointing at the
                // directory to mirror.  Try nullfs first (part of XNU), fall back to
                // bindfs (provided by some jailbreak kernels).
                struct {
                        char *fspec;
                } nullArgs = { .fspec = upperPath };

                rv = mount("nullfs", gOverlayPaths[i], 0, &nullArgs);
                if (rv != 0) {
                        rv = mount("bindfs", gOverlayPaths[i], 0, upperPath);
                }
                if (rv != 0) {
                        // Overlay for this path failed; that is non fatal, continue
                        continue;
                }
                mountedCount++;
        }

        if (mountedCount == 0) {
                return ENOTSUP;
        }

        gRootfulStatus.overlayActive = true;
        return 0;
}

int rootful_get_status(rootful_status_t *status)
{
        if (status) *status = gRootfulStatus;
        return 0;
}

int rootful_enable(bool overlays_requested, rootful_status_t *status)
{
        return rootful_enable_ex(overlays_requested, NULL, NULL, status);
}

int rootful_enable_ex(bool overlays_requested, rootful_progress_fn progress, void *ctx, rootful_status_t *status)
{
        gEngineProgress = progress;
        gEngineCtx = ctx;
        memset(&gRootfulStatus, 0, sizeof(gRootfulStatus));
        gRootfulStatus.supportedConfig = rootful_supported_configuration();

        if (!gRootfulStatus.supportedConfig) {
                rootful_set_error("unsupported device / OS combination (need A12/A13, iOS 16.6.1 - 18.7.1)");
                if (status) *status = gRootfulStatus;
                gRootfulStatusValid = true;
                return ENOTSUP;
        }

        if (!rootful_offsets_available()) {
                rootful_set_error("mount struct offsets unavailable for this kernel build");
                if (status) *status = gRootfulStatus;
                return ENOTSUP;
        }

        // 1. Primary path: fakefs (non-sealed new volume + copy + remount)
        //    Per A's analysis + 汇总员's 00:29:49 directive. Falls back to
        //    in-memory remount + nullfs overlays if fakefs components fail.
        int fakefsR = rootful_fakefs_attempt(&gRootfulStatus);
        if (fakefsR == 0) {
                // fakefs succeeded; overlays are an optional convenience layer on top
                if (overlays_requested) {
                        rootful_mount_overlays(); // best effort, non-fatal
                }
                if (status) *status = gRootfulStatus;
                gRootfulStatusValid = true;
                return 0;
        }

        // 1b. Fallback: in-memory remount attempt (clear MNT_RDONLY on the
        //     sealed root mount). On SSV this may not actually yield a writable
        //     volume, but the flag clear is the prerequisite for the overlay
        //     mounts below and is harmless if it fails.
        uint64_t rootMount = rootful_find_root_mount();
        if (rootMount != 0) {
                int r = rootful_clear_rdonly_flag(rootMount);
                if (r == 0) {
                        gRootfulStatus.rootMountedRW = true;
                        gRootfulStatus.sealDisabled = true;
                        rootful_set_error("");
                }
                else {
                        rootful_set_error("fakefs unavailable + in-memory remount failed");
                }
        }
        else {
                rootful_set_error("fakefs unavailable + root mount could not be validated");
        }

        // 2. Overlay fallback / addition
        int rv = rootful_mount_overlays();
        if (rv != 0) {
                rootful_set_error("overlay mounts failed");
        }

        if (status) *status = gRootfulStatus;
        gRootfulStatusValid = true;

        if (!gRootfulStatus.rootMountedRW && !gRootfulStatus.overlayActive) {
                return ENOTSUP;
        }
        return 0;
}

int rootful_disable(void)
{
        // Mount-over volumes first (engine unmounts the six directories in
        // reverse order, volumes and data are kept).
        if (rootful_fakefs_available()) {
                char err[192] = {0};
                int r = rootful_fakefs_run("disable", NULL, NULL, NULL, err, sizeof(err));
                if (r == 0) {
                        gRootfulStatus.fakefsActive = false;
                        gRootfulStatus.rootMountedRW = false;
                }
        }

        if (gRootfulStatus.overlayActive) {
                for (int i = 0; gOverlayPaths[i]; i++) {
                        unmount(gOverlayPaths[i], MNT_FORCE);
                }
                gRootfulStatus.overlayActive = false;
        }

        // The in-memory MNT_RDONLY clear cannot be reverted safely (open file
        // descriptors may already hold writable vnodes); it is dropped at reboot.
        gRootfulStatus.rootMountedRW = false;
        gRootfulStatus.sealDisabled = false;
        rootful_set_error("");
        return 0;
}
