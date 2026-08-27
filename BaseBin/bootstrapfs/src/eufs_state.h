//
//  eufs_state.h
//  Euphoria bootstrapfs — persistent engine state (plist)
//
//  The state file records which volumes belong to the rootful overlay, their
//  per-role device nodes and sizes, and whether the set was ever committed.
//  It is the single source of truth shared by enable/recover/disable/purge
//  AND by cloakd (volume-name filtering, docs/03) — no fixed on-volume
//  marker paths are used for discovery (the ready marker inside a volume is
//  only a content-integrity hint, never an identity check).
//

#ifndef EUFS_STATE_H
#define EUFS_STATE_H

#import "eufs_common.h"
#import <stdint.h>

typedef struct {
	char volumeName[64]; // APFS volume name (FullName), e.g. com.apple.storage.usr
	char device[32];     // BSD node, e.g. disk0s1s9
	uint64_t bytes;      // measured source size at staging time
	uint64_t files;      // measured file count at staging time
} eufs_role_info;

typedef struct {
	uint32_t version;
	char prefix[48];
	int committed;                    // 1 once the whole set was mounted-over
	eufs_role_info roles[EUFS_ROLE_COUNT];
} eufs_state;

// Path of the state plist inside the jailbreak root.
const char *eufs_state_path(void);

int eufs_state_load(eufs_state *s);   // 0 = present & parsed; -1 = absent/corrupt
int eufs_state_save(const eufs_state *s);
int eufs_state_delete(void);

#endif // EUFS_STATE_H
