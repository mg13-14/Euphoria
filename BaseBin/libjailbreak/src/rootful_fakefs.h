//
//  rootful_fakefs.h
//  libjailbreak — bootstrapfs engine orchestration
//
//  Spawns $JBROOT/basebin/bootstrapfs with a progress pipe and streams its
//  JSON stage events line-by-line to an optional callback.  Used by
//  BaseBin/euphoria (jailbreak flow, T14 flow-forking) and jbctl
//  (maintenance commands from the App).
//

#ifndef __ROOTFUL_FAKEFS_H
#define __ROOTFUL_FAKEFS_H

#include <stddef.h>

// Called once per JSON stage-event line (line does NOT contain '\n').
typedef void (*rootful_fakefs_progress_fn)(const char *jsonLine, void *ctx);

// action: "enable" | "recover" | "disable" | "purge" | "status" | "rollback"
// extraArg: appended verbatim after the action (e.g. "--confirm"), may be NULL
// Returns the engine exit code; -1 = spawn failure (engine missing/unsupported).
// lastError (>= 192 bytes, may be NULL) receives a human summary on failure.
int rootful_fakefs_run(const char *action, const char *extraArg,
                       rootful_fakefs_progress_fn cb, void *ctx,
                       char *lastError, size_t lastErrorLen);

// Convenience: is the engine binary present in the active basebin?
int rootful_fakefs_available(void);

#endif // __ROOTFUL_FAKEFS_H
