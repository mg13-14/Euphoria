//
//  progress.h
//  Euphoria bootstrapfs — stage-event emitter (T14 progress contract)
//
//  Every long-running action emits single-line JSON objects ("events") on a
//  dedicated progress fd (default: stdout).  The jailbreak orchestrator
//  (BaseBin/euphoria) re-emits them as "[STAGE] {...}" lines on its own
//  stdout, which the App parses live to drive the rootful progress page
//  (docs/06-rootful开关与进度视觉交付包_T15.md is the consumer spec).
//
//  Event schema (v1):
//    {"v":1,"ev":"probe",  "key":"container","value":"disk0s1"}
//    {"v":1,"ev":"stage",  "stage":"precheck|probe|create|copy|verify|mount|unmount|commit|rollback|done","dir":"/usr","index":1,"total":6}
//    {"v":1,"ev":"copy",   "dir":"/usr","bytes":123,"bytesTotal":4567,"files":12,"pct":34.5,"pctGlobal":7.8}
//    {"v":1,"ev":"done",   "mode":"enable|recover|disable|purge|rollback","elapsed":123.4}
//    {"v":1,"ev":"error",  "stage":"copy","dir":"/usr","path":"/usr/lib/x","errno":28,"msg":"...","fatal":true}
//    {"v":1,"ev":"rollback","reason":"...","unmounted":2,"destroyed":6}
//

#ifndef EUFS_PROGRESS_H
#define EUFS_PROGRESS_H

#include <stdint.h>
#include <stdbool.h>

void eufs_progress_set_fd(int fd);
int  eufs_progress_get_fd(void);

void eufs_emit_probe(const char *key, const char *value);
void eufs_emit_stage(const char *stage, const char *dir, int index, int total);
void eufs_emit_copy(const char *dir, uint64_t bytes, uint64_t bytesTotal,
                    uint64_t files, double pct, double pctGlobal);
void eufs_emit_done(const char *mode, double elapsedSeconds);
void eufs_emit_error(const char *stage, const char *dir, const char *path,
                     int err, const char *msg, bool fatal);
void eufs_emit_rollback(const char *reason, int unmounted, int destroyed);

#endif // EUFS_PROGRESS_H
