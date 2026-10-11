//
//  apfs_probe.h
//  Euphoria bootstrapfs — APFS layout probing + volume primitives
//
//  Hardening over the ghh-jb original (C7 risks #1/#2/#10):
//   * The container device is DISCOVERED (statfs("/") -> live system volume
//     -> IOKit parent walk), never hardcoded as "disk0s1"/"disk1" by OS
//     version guess.  Both known layouts are merely fallback candidates that
//     get verified against IOKit before use.
//   * APFS.framework SPIs (APFSVolumeCreate/Delete) are dlopen'ed and their
//     presence REPORTED through probe events instead of aborting blindly.
//   * Volume identity comes from the state file + IOKit FullName matching;
//     no globally fixed marker path is used for discovery.
//

#ifndef EUFS_APFS_PROBE_H
#define EUFS_APFS_PROBE_H

#import <stdint.h>

typedef struct {
	char root_mount_from[64];  // e.g. /dev/disk0s1s1 (sealed snapshot)
	char system_volume[32];    // e.g. disk0s1  (live system volume)
	char container[32];        // e.g. disk0s1 (15.x layout) / disk1 (16+ layout)
	char container_method[96]; // how container was determined (for probe log)
	int  spi_volume_create;    // 1 if APFSVolumeCreate symbol resolved
	int  spi_volume_delete;    // 1 if APFSVolumeDelete symbol resolved
} eufs_probe_t;

// Fill `out` with the discovered layout.  Returns 0 on success, -1 with
// out->container[0]=='\0' when the container could not be determined safely.
int eufs_probe_layout(eufs_probe_t *out);

// Resolve the /dev node of an APFS volume by its FullName via IOKit.
// Returns a malloc'ed "/dev/diskXsY" string or NULL.
char *eufs_volume_device(const char *volumeName);

// Mount `device` (live FS, not a snapshot) at `mntPoint` with the kernel-cred
// dance.  flags is usually 0 for staging mounts and MNT_FORCE for commit
// mounts over live directories.  Returns 0 on success.
int eufs_mount_volume(const char *mntPoint, const char *device, int flags);

// Unmount with the kernel-cred dance.  Returns 0 on success.
int eufs_unmount_path(const char *mntPoint);

// Create / destroy a plain volume in the given container device
// (e.g. "disk0s1").  Must be called AFTER eufs_probe_layout succeeded so the
// SPI handles are initialised.  Return 0 on success.
int eufs_create_volume(const char *containerDevice, const char *volumeName);
int eufs_destroy_volume(const char *deviceNode);

// Wait up to `timeoutMs` for /dev/<node> to appear after volume creation.
int eufs_wait_for_device(const char *deviceNode, int timeoutMs);

#endif // EUFS_APFS_PROBE_H
