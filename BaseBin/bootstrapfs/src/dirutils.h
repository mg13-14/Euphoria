//
//  dirutils.h
//  Euphoria bootstrapfs — measurement, preflight and hardened copy
//
//  Fixes over the ghh-jb original (C7 risks #3/#4/#5/#6):
//   * relative AND absolute symlinks are copied VERBATIM (readlink+symlink),
//     never resolved through realpath — the ghh TODO is closed here
//   * per-file retry with exponential backoff and a hard bound, instead of
//     aborting the whole copy on a single transient copyfile failure
//   * preflight: directory sizes are measured up-front (drives both the
//     space precheck and the global progress scale)
//   * .fseventsd / .DS_Store / Spotlight noise skipped
//

#ifndef EUFS_DIRUTILS_H
#define EUFS_DIRUTILS_H

#import <stdint.h>

typedef struct {
	uint64_t bytes; // apparent bytes of all regular files
	uint64_t files; // regular files
	uint64_t dirs;  // directories
	uint64_t links; // symlinks
} eufs_size_summary;

// Walk `src` (lstat, no follow) and summarize.  Returns 0 on success.
int eufs_measure_dir(const char *src, eufs_size_summary *out);

// Copy `src` -> `dst` recursively, preserving symlinks verbatim, modes,
// owners and extended attributes (copyfile COPYFILE_ALL).
//
// `dirBytes`/`globalOffset`/`globalTotal` drive progress reporting:
//   cb(path, dirBytesDone, dirBytesTotal, globalBytesDone, globalTotal, ctx)
// `lastError` (may be NULL, >= 256 bytes) receives a description of the
// final fatal failure.
typedef void (*eufs_copy_progress_cb)(const char *path, uint64_t dirBytesDone,
                                      uint64_t dirBytesTotal, uint64_t globalDone,
                                      uint64_t globalTotal, void *ctx);
int eufs_copy_dir(const char *src, const char *dst,
                  uint64_t globalOffset, uint64_t globalTotal,
                  eufs_copy_progress_cb cb, void *ctx,
                  char *lastError, size_t lastErrorLen);

// Preflight: available bytes on the filesystem mounted at `mountPoint`
// (use the data volume, e.g. "/var").  Returns available bytes, or
// (uint64_t)-1 on statfs failure.
uint64_t eufs_available_bytes(const char *mountPoint);

// Ensure every path component of `path` exists (mode 0755).
int eufs_ensure_directory(const char *path);

#endif // EUFS_DIRUTILS_H
