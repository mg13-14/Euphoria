//
//  eufs_common.h
//  Euphoria bootstrapfs — shared role table
//
//  Directory <-> writable-volume role mapping used by every stage of the
//  mount-over rootful engine (probe / enable / recover / disable / purge).
//
//  Mount-over model (credits: untether's ghh-jb/Dopamine_Rootful bootstrapfs):
//  the sealed system snapshot is never touched; for each role a plain
//  (non-sealed) APFS volume is created inside the data container, populated
//  with a full copy of the original directory, and finally mounted OVER the
//  original path with mount(MNT_FORCE).  SSV only validates the seal at boot;
//  runtime mount-table operations do not re-verify it.
//

#ifndef EUFS_COMMON_H
#define EUFS_COMMON_H

#define EUFS_ROLE_COUNT 6

// Canonical mount/commit order: /private/etc first (config consumed by later
// mounts is already in place), then the big trees, then sbin/bin.
extern const char *eufs_role_dirs[EUFS_ROLE_COUNT];   // mount-over targets
extern const char *eufs_role_ids[EUFS_ROLE_COUNT];    // stable state-file keys

// Default innocuous volume-name prefix.  Full volume names are
// "<prefix><role>" (e.g. "com.apple.storage.usr").  cloakd additionally
// filters these names out of IOKit/system enumerations (see docs/03).
#define EUFS_DEFAULT_VOL_PREFIX "com.apple.storage."

// Staging area used while filling a volume BEFORE it is committed over the
// real directory.  Never mount-over the system path during staging: an abort
// anywhere before commit must leave the live system 100% untouched.
#define EUFS_STAGING_ROOT "/var/mnt/.eufs-staging"

// Marker placed inside each staged volume once its content copy completed
// and verified.  Used by recover to distinguish a fully staged volume from
// an interrupted one.  Dot-file, hidden from casual listings; the volumes
// themselves are name-filtered by cloakd anyway.
#define EUFS_READY_MARKER ".com.apple.storage.ready"

#endif // EUFS_COMMON_H
