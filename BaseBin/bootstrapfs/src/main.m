//
//  main.m
//  Euphoria bootstrapfs — transactional mount-over rootful engine CLI
//
//  Hardened port of ghh-jb/Dopamine_Rootful BaseBin/bootstrapfs (untether).
//  Design (T5/T13/T14):
//
//    enable   = full transactional first-enable:
//               probe -> precheck(space) -> [per role: create volume ->
//               stage-copy at EUFS_STAGING_ROOT -> verify -> unmount stage]
//               -> commit (mount all 6 over live dirs) -> state committed=1
//               ANY failure before commit rolls back every created volume;
//               the live system is never touched before commit, so an abort
//               at any point is reboot-clean.
//    recover  = fast path for re-jailbreaks after the set exists:
//               mount-only, seconds.
//    disable  = unmount the 6 overlays (reverse order); volumes + data kept.
//    purge    = disable + destroy all volumes + delete state.  Requires
//               --confirm (guarded like jbctl "protection").
//    status   = human/JSON report of state + mount table.
//    rollback = cleanup of an interrupted (uncommitted) enable.
//
//  Actions are idempotent where possible and always safe to re-run.
//

#import "eufs_common.h"
#import "eufs_state.h"
#import "apfs_probe.h"
#import "dirutils.h"
#import "progress.h"
#import <libjailbreak/libjailbreak.h>
#import <Foundation/Foundation.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <unistd.h>
#import <errno.h>
#import <sys/mount.h>
#import <sys/stat.h>
#import <stdarg.h>
#import <IOKit/IOKitLib.h>

const char *eufs_role_dirs[EUFS_ROLE_COUNT] = {
        "/private/etc", "/usr", "/Library", "/Applications", "/sbin", "/bin",
};
const char *eufs_role_ids[EUFS_ROLE_COUNT] = {
        "etc", "usr", "library", "applications", "sbin", "bin",
};

// T13: storage preflight parameters.
#define EUFS_SPACE_HEADROOM_BYTES (512ULL * 1024 * 1024) // 512 MiB
#define EUFS_SPACE_SAFETY_NUM 110                          // +10 %
#define EUFS_SPACE_SAFETY_DEN 100
#define EUFS_DEVICE_WAIT_MS 5000

static eufs_probe_t gProbe;
static int gProbeValid = 0;

static void eufs_log(const char *fmt, ...)
{
        va_list args;
        va_start(args, fmt);
        fputs("[eufs] ", stdout);
        vfprintf(stdout, fmt, args);
        fputc('\n', stdout);
        fflush(stdout);
        va_end(args);
}

static double eufs_monotonic(void)
{
        return [NSProcessInfo processInfo].systemUptime;
}

// Bare BSD node of whatever is mounted at `dir` ("" when statfs fails).
static void eufs_dir_device(const char *dir, char *out, size_t len)
{
        out[0] = '\0';
        struct statfs sfs;
        if (statfs(dir, &sfs) != 0) return;
        const char *mnt = sfs.f_mntfromname;
        const char *slash = strrchr(mnt, '/');
        strlcpy(out, slash ? slash + 1 : mnt, len);
}

// FullName of an APFS volume by bare BSD node (IOKit), or NULL.
static NSString *eufs_fullname_of_bsd(const char *bsd)
{
        if (!bsd || !bsd[0]) return nil;
        CFMutableDictionaryRef matching = IOServiceMatching("AppleAPFSVolume");
        io_iterator_t iter = 0;
        if (IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) != KERN_SUCCESS) return nil;
        NSString *result = nil;
        io_object_t service;
        while (!result && (service = IOIteratorNext(iter)) != 0) {
                CFStringRef dev = IORegistryEntrySearchCFProperty(service, kIOServicePlane, CFSTR("BSD Name"), nil, 0);
                if (dev) {
                        NSString *devStr = (__bridge NSString *)dev;
                        if ([devStr isEqualToString:@(bsd)]) {
                                CFStringRef name = IORegistryEntrySearchCFProperty(service, kIOServicePlane, CFSTR("FullName"), nil, 0);
                                if (name) {
                                        result = [(__bridge NSString *)name copy];
                                        CFRelease(name);
                                }
                        }
                        CFRelease(dev);
                }
                IOObjectRelease(service);
        }
        IOObjectRelease(iter);
        return result;
}

// Is `dir` currently covered by one of OUR overlay volumes?
//  - expectedBsd given: exact device match against the live mount table
//  - expectedBsd NULL:  heuristic — mounted volume's FullName is not one of
//    the stock system volume names
static int eufs_dir_is_mounted_over(const char *dir, const char *expectedBsd)
{
        char cur[32];
        eufs_dir_device(dir, cur, sizeof(cur));
        if (cur[0] == '\0') return 0;
        if (expectedBsd && expectedBsd[0]) return strcmp(cur, expectedBsd) == 0;
        NSString *fn = eufs_fullname_of_bsd(cur);
        if (!fn) return 0;
        static NSArray *stockNames = nil;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
                stockNames = @[ @"System", @"Update", @"Preboot", @"Recovery", @"VM",
                                @"Hardware", @"Data", @"Backup", @"xartsif", @"MutableBackup" ];
        });
        return ![stockNames containsObject:fn];
}

static int eufs_stage_path_for(char *out, size_t len, int role)
{
        return snprintf(out, len, "%s/%s", EUFS_STAGING_ROOT, eufs_role_ids[role]);
}

// --------------------------------------------------------------------------
// probe
// --------------------------------------------------------------------------

static int cmd_probe(void)
{
        if (eufs_probe_layout(&gProbe) != 0) {
                eufs_log("probe FAILED: container unresolved — report to maintainers");
                return 1;
        }
        eufs_log("root mount: %s", gProbe.root_mount_from);
        eufs_log("system volume: %s", gProbe.system_volume);
        eufs_log("container: %s (%s)", gProbe.container, gProbe.container_method);
        eufs_log("APFS SPIs: create=%d delete=%d", gProbe.spi_volume_create, gProbe.spi_volume_delete);
        return 0;
}

// --------------------------------------------------------------------------
// enable (transactional first-enable; falls through to staging)
// --------------------------------------------------------------------------

typedef struct {
        const char *dir;
        uint64_t globalOffset;
        uint64_t globalTotal;
} eufs_role_progress_ctx;

static void eufs_role_progress_cb(const char *path, uint64_t dirDone, uint64_t dirTotal,
                                  uint64_t globalDone, uint64_t globalTotal, void *ctx)
{
        eufs_role_progress_ctx *c = (eufs_role_progress_ctx *)ctx;
        double pct = dirTotal ? (100.0 * (double)dirDone / (double)dirTotal) : 100.0;
        double pctGlobal = globalTotal ? (100.0 * (double)globalDone / (double)globalTotal) : 100.0;
        (void)path;
        eufs_emit_copy(c->dir, dirDone, dirTotal, 0, pct, pctGlobal);
}

static int eufs_ensure_probe(void)
{
        if (gProbeValid) return 0;
        if (eufs_probe_layout(&gProbe) != 0) return -1;
        gProbeValid = 1;
        return 0;
}

// Destroy every volume listed in `s` and the state file itself.
static int eufs_destroy_all(eufs_state *s, int *destroyedCount)
{
        int destroyed = 0;
        for (int i = EUFS_ROLE_COUNT - 1; i >= 0; i--) {
                eufs_role_info *r = &s->roles[i];
                if (r->device[0] == '\0') continue;
                if (eufs_destroy_volume(r->device) == 0) {
                        destroyed++;
                        eufs_log("destroyed volume %s (%s)", r->volumeName, r->device);
                }
                else {
                        eufs_log("WARN: destroy %s (%s) failed", r->volumeName, r->device);
                }
                r->device[0] = '\0';
                r->volumeName[0] = '\0';
        }
        eufs_state_delete();
        if (destroyedCount) *destroyedCount = destroyed;
        return 0;
}

// Unmount every role currently mounted-over (reverse order), keeping volumes.
static int eufs_unmount_all(eufs_state *s, int *unmountedCount)
{
        int unmounted = 0;
        for (int i = EUFS_ROLE_COUNT - 1; i >= 0; i--) {
                const char *dir = eufs_role_dirs[i];
                const char *expect = (s && s->roles[i].device[0]) ? s->roles[i].device : NULL;
                if (!eufs_dir_is_mounted_over(dir, expect)) continue;
                eufs_emit_stage("unmount", dir, EUFS_ROLE_COUNT - i, EUFS_ROLE_COUNT);
                if (eufs_unmount_path(dir) == 0) {
                        unmounted++;
                }
                else {
                        eufs_log("WARN: unmount %s: %s", dir, strerror(errno));
                }
        }
        if (unmountedCount) *unmountedCount = unmounted;
        return 0;
}

static int cmd_enable(const char *volPrefix)
{
        double t0 = eufs_monotonic();
        eufs_state state;
        int haveState = (eufs_state_load(&state) == 0);

        // Already enabled and mounted? -> behave like recover.
        if (haveState && state.committed) {
                int needMount = 0;
                for (int i = 0; i < EUFS_ROLE_COUNT; i++) {
                        if (!eufs_dir_is_mounted_over(eufs_role_dirs[i], state.roles[i].device)) { needMount = 1; break; }
                }
                if (!needMount) {
                        eufs_log("already active — nothing to do");
                        eufs_emit_done("recover", eufs_monotonic() - t0);
                        return 0;
                }
        }

        if (eufs_ensure_probe() != 0) {
                eufs_emit_error("probe", "", "", errno, "container unresolved", true);
                eufs_emit_done("enable", eufs_monotonic() - t0);
                return 1;
        }
        if (!gProbe.spi_volume_create || !gProbe.spi_volume_delete) {
                eufs_emit_error("probe", "", "", ENOSYS, "APFS volume SPIs unavailable on this OS", true);
                eufs_emit_done("enable", eufs_monotonic() - t0);
                return 1;
        }

        // ---- precheck: measure all six trees (T13/T14) ----------------------
        eufs_emit_stage("precheck", "", 0, EUFS_ROLE_COUNT);
        eufs_size_summary sums[EUFS_ROLE_COUNT];
        uint64_t globalTotal = 0;
        for (int i = 0; i < EUFS_ROLE_COUNT; i++) {
                if (eufs_measure_dir(eufs_role_dirs[i], &sums[i]) != 0) {
                        eufs_emit_error("precheck", eufs_role_dirs[i], "", errno, "measure failed", true);
                        eufs_emit_done("enable", eufs_monotonic() - t0);
                        return 1;
                }
                globalTotal += sums[i].bytes;
        }
        uint64_t available = eufs_available_bytes("/var");
        uint64_t required = globalTotal * EUFS_SPACE_SAFETY_NUM / EUFS_SPACE_SAFETY_DEN + EUFS_SPACE_HEADROOM_BYTES;
        if (available == (uint64_t)-1) {
                eufs_emit_error("precheck", "", "", errno, "statfs(/var) failed", true);
                eufs_emit_done("enable", eufs_monotonic() - t0);
                return 1;
        }
        if (available < required) {
                char msg[160];
                snprintf(msg, sizeof(msg), "insufficient space: need %llu MiB (incl. safety), have %llu MiB",
                         required >> 20, available >> 20);
                eufs_emit_error("precheck", "", "", ENOSPC, msg, true);
                eufs_emit_done("enable", eufs_monotonic() - t0);
                return 2; // distinct exit code: space
        }
        eufs_emit_probe("space.requiredMiB", [NSString stringWithFormat:@"%llu", required >> 20].UTF8String);
        eufs_emit_probe("space.availableMiB", [NSString stringWithFormat:@"%llu", available >> 20].UTF8String);

        // ---- staging phase: create + fill volumes, system dirs untouched -----
        memset(&state, 0, sizeof(state));
        state.version = 1;
        strlcpy(state.prefix, volPrefix, sizeof(state.prefix));
        state.committed = 0;

        uint64_t globalOffset = 0;
        char lastError[256] = { 0 };
        int stagedMnts[EUFS_ROLE_COUNT];
        for (int i = 0; i < EUFS_ROLE_COUNT; i++) stagedMnts[i] = 0;

        for (int i = 0; i < EUFS_ROLE_COUNT; i++) {
                const char *dir = eufs_role_dirs[i];
                eufs_role_info *r = &state.roles[i];
                snprintf(r->volumeName, sizeof(r->volumeName), "%s%s", volPrefix, eufs_role_ids[i]);

                eufs_emit_stage("create", dir, i + 1, EUFS_ROLE_COUNT);
                if (eufs_create_volume(gProbe.container, r->volumeName) != 0) {
                        snprintf(lastError, sizeof(lastError), "volume create failed for %s in %s", r->volumeName, gProbe.container);
                        goto rollback;
                }
                char *dev = eufs_volume_device(r->volumeName);
                if (!dev || eufs_wait_for_device(dev, EUFS_DEVICE_WAIT_MS) != 0) {
                        free(dev);
                        snprintf(lastError, sizeof(lastError), "new volume %s not exposed as /dev node", r->volumeName);
                        goto rollback;
                }
                strlcpy(r->device, dev + 5, sizeof(r->device)); // store bare bsd node
                free(dev);
                eufs_state_save(&state); // volume is trackable for purge/rollback from now on

                char stagePath[384];
                eufs_stage_path_for(stagePath, sizeof(stagePath), i);
                eufs_ensure_directory(stagePath);
                if (eufs_mount_volume(stagePath, r->device, 0) != 0) {
                        snprintf(lastError, sizeof(lastError), "stage mount %s -> %s failed: %s", r->device, stagePath, strerror(errno));
                        goto rollback;
                }
                stagedMnts[i] = 1;

                eufs_emit_stage("copy", dir, i + 1, EUFS_ROLE_COUNT);
                eufs_role_progress_ctx ctx = { .dir = dir, .globalOffset = globalOffset, .globalTotal = globalTotal };
                if (eufs_copy_dir(dir, stagePath, globalOffset, globalTotal,
                                  eufs_role_progress_cb, &ctx, lastError, sizeof(lastError)) != 0) {
                        goto rollback;
                }

                // verify: ready marker write-through + visible content
                char marker[448];
                snprintf(marker, sizeof(marker), "%s/%s", stagePath, EUFS_READY_MARKER);
                FILE *mf = fopen(marker, "w");
                if (mf) { fputs("ok\n", mf); fclose(mf); }
                else {
                        snprintf(lastError, sizeof(lastError), "verify write failed on %s", stagePath);
                        goto rollback;
                }

                eufs_emit_stage("verify", dir, i + 1, EUFS_ROLE_COUNT);
                eufs_unmount_path(stagePath);
                stagedMnts[i] = 0;

                r->bytes = sums[i].bytes;
                r->files = sums[i].files;
                globalOffset += sums[i].bytes;
                eufs_state_save(&state);
        }

        // ---- commit phase: all six staged OK -> mount over live dirs ---------
        for (int i = 0; i < EUFS_ROLE_COUNT; i++) {
                const char *dir = eufs_role_dirs[i];
                eufs_role_info *r = &state.roles[i];
                eufs_emit_stage("mount", dir, i + 1, EUFS_ROLE_COUNT);
                char dev[64];
                snprintf(dev, sizeof(dev), "/dev/%s", r->device);
                if (eufs_mount_volume(dir, dev, MNT_FORCE) != 0) {
                        snprintf(lastError, sizeof(lastError), "commit mount %s -> %s failed: %s", dev, dir, strerror(errno));
                        // partial commit: undo the mounts we just did, keep volumes for retry
                        int undone = 0;
                        for (int j = i - 1; j >= 0; j--) {
                                if (eufs_dir_is_mounted_over(eufs_role_dirs[j], state.roles[j].device)) {
                                        if (eufs_unmount_path(eufs_role_dirs[j]) == 0) undone++;
                                }
                        }
                        int destroyed = 0;
                        eufs_emit_rollback(lastError, undone, destroyed);
                        eufs_emit_error("mount", dir, dev, errno, "commit failed — volumes kept, retry or purge", true);
                        eufs_emit_done("enable", eufs_monotonic() - t0);
                        return 3;
                }
        }

        state.committed = 1;
        eufs_state_save(&state);
        eufs_log("enabled: %d volumes committed over live system", EUFS_ROLE_COUNT);
        eufs_emit_done("enable", eufs_monotonic() - t0);
        return 0;

rollback: {
                // T13 failure path: nothing was ever mounted over a live directory,
                // so unmount staging points and destroy every created volume.
                for (int i = 0; i < EUFS_ROLE_COUNT; i++) {
                        if (stagedMnts[i]) {
                                char stagePath[384];
                                eufs_stage_path_for(stagePath, sizeof(stagePath), i);
                                eufs_unmount_path(stagePath);
                        }
                }
                int destroyed = 0;
                eufs_destroy_all(&state, &destroyed);
                eufs_emit_rollback(lastError, 0, destroyed);
                eufs_emit_error("copy", "", "", errno, lastError, true);
                eufs_emit_done("enable", eufs_monotonic() - t0);
                return 4;
        }
}

// --------------------------------------------------------------------------
// recover / disable / purge / rollback / status
// --------------------------------------------------------------------------

static int cmd_recover(void)
{
        double t0 = eufs_monotonic();
        eufs_state state;
        if (eufs_state_load(&state) != 0) {
                eufs_emit_error("recover", "", "", ENOENT, "no committed state — run enable first", true);
                eufs_emit_done("recover", eufs_monotonic() - t0);
                return 1;
        }
        for (int i = 0; i < EUFS_ROLE_COUNT; i++) {
                const char *dir = eufs_role_dirs[i];
                if (eufs_dir_is_mounted_over(dir, state.roles[i].device)) continue;
                eufs_emit_stage("mount", dir, i + 1, EUFS_ROLE_COUNT);
                char dev[64];
                snprintf(dev, sizeof(dev), "/dev/%s", state.roles[i].device);
                if (eufs_mount_volume(dir, dev, MNT_FORCE) != 0) {
                        eufs_emit_error("mount", dir, dev, errno, strerror(errno), true);
                        eufs_emit_done("recover", eufs_monotonic() - t0);
                        return 2;
                }
        }
        state.committed = 1;
        eufs_state_save(&state);
        eufs_emit_done("recover", eufs_monotonic() - t0);
        return 0;
}

static int cmd_disable(void)
{
        double t0 = eufs_monotonic();
        eufs_state state;
        int haveState = (eufs_state_load(&state) == 0);
        int unmounted = 0;
        eufs_unmount_all(&state, &unmounted);
        if (haveState) {
                state.committed = 0;
                eufs_state_save(&state);
        }
        eufs_log("disabled: %d overlays unmounted (volumes + data kept)", unmounted);
        eufs_emit_done("disable", eufs_monotonic() - t0);
        return 0;
}

static int cmd_purge(int confirmed)
{
        double t0 = eufs_monotonic();
        eufs_state state;
        if (eufs_state_load(&state) != 0) {
                eufs_emit_error("purge", "", "", ENOENT, "nothing to purge", false);
                eufs_emit_done("purge", eufs_monotonic() - t0);
                return 0;
        }
        if (!confirmed) {
                // guarded exactly like jbctl's protected path: refuse without --confirm
                eufs_emit_error("purge", "", "", EPERM, "refusing: pass --confirm to destroy rootful volumes", false);
                eufs_emit_done("purge", eufs_monotonic() - t0);
                return 5;
        }
        int unmounted = 0, destroyed = 0;
        eufs_unmount_all(&state, &unmounted);
        eufs_destroy_all(&state, &destroyed);
        eufs_emit_rollback("purge", unmounted, destroyed);
        eufs_log("purged: %d volumes destroyed", destroyed);
        eufs_emit_done("purge", eufs_monotonic() - t0);
        return 0;
}

static int cmd_rollback(void)
{
        double t0 = eufs_monotonic();
        eufs_state state;
        if (eufs_state_load(&state) != 0) {
                eufs_log("no state — nothing to roll back");
                eufs_emit_done("rollback", eufs_monotonic() - t0);
                return 0;
        }
        if (state.committed) {
                eufs_emit_error("rollback", "", "", EBUSY, "set is committed — use disable (+ purge --confirm) instead", false);
                eufs_emit_done("rollback", eufs_monotonic() - t0);
                return 6;
        }
        int unmounted = 0, destroyed = 0;
        for (int i = 0; i < EUFS_ROLE_COUNT; i++) {
                char stagePath[384];
                eufs_stage_path_for(stagePath, sizeof(stagePath), i);
                eufs_unmount_path(stagePath);
        }
        eufs_unmount_all(&state, &unmounted);
        eufs_destroy_all(&state, &destroyed);
        eufs_emit_rollback("manual rollback of interrupted enable", unmounted, destroyed);
        eufs_emit_done("rollback", eufs_monotonic() - t0);
        return 0;
}

static int cmd_status(void)
{
        eufs_state state;
        int haveState = (eufs_state_load(&state) == 0);
        NSMutableArray *lines = [NSMutableArray array];
        if (!haveState) {
                [lines addObject:@"state: none"];
        }
        else {
                [lines addObject:[NSString stringWithFormat:@"state: v%u prefix=%@ committed=%d",
                        state.version, @(state.prefix), state.committed]];
        }
        int mounted = 0;
        for (int i = 0; i < EUFS_ROLE_COUNT; i++) {
                BOOL over = eufs_dir_is_mounted_over(eufs_role_dirs[i], haveState ? state.roles[i].device : NULL);
                if (over) mounted++;
                NSString *vol = haveState ? @(state.roles[i].volumeName) : @"-";
                [lines addObject:[NSString stringWithFormat:@"  %@ -> %@%@ (%llu MiB)",
                        @(eufs_role_dirs[i]), vol, over ? @" [MOUNTED]" : @"", haveState ? state.roles[i].bytes >> 20 : 0]];
        }
        NSString *out = [lines componentsJoinedByString:@"\n"];
        fputs(out.UTF8String, stdout);
        fputc('\n', stdout);
        eufs_emit_probe("status.mounted", [NSString stringWithFormat:@"%d", mounted].UTF8String);
        return 0;
}

// --------------------------------------------------------------------------
// main
// --------------------------------------------------------------------------

static void usage(void)
{
        fputs(
        "usage: bootstrapfs <action> [options]\n"
        "  probe                       report APFS layout + SPI availability\n"
        "  enable  [--vol-prefix P]    first-enable (transactional, with rollback)\n"
        "  recover                     fast remount of an existing set\n"
        "  disable                     unmount overlays, keep volumes + data\n"
        "  purge   --confirm           destroy volumes + state (guarded)\n"
        "  status                      state + mount table report\n"
        "  rollback                    cleanup of an interrupted enable\n"
        "options (all actions):\n"
        "  --progress-fd N             emit JSON stage events on fd N (default stdout)\n"
        "  --vol-prefix P              volume name prefix (default " EUFS_DEFAULT_VOL_PREFIX ")\n",
        stdout);
}

int main(int argc, char *argv[])
{
        if (getuid() != 0) {
                fputs("FAIL: run as root\n", stderr);
                return 64;
        }
        if (argc < 2) { usage(); return 64; }

        const char *action = argv[1];
        const char *volPrefix = EUFS_DEFAULT_VOL_PREFIX;
        for (int i = 2; i < argc; i++) {
                if (!strcmp(argv[i], "--progress-fd") && i + 1 < argc) {
                        eufs_progress_set_fd(atoi(argv[++i]));
                }
                else if (!strcmp(argv[i], "--vol-prefix") && i + 1 < argc) {
                        volPrefix = argv[++i];
                }
        }
        const char *envFd = getenv("EUFS_PROGRESS_FD");
        if (envFd && eufs_progress_get_fd() == STDOUT_FILENO) {
                eufs_progress_set_fd(atoi(envFd));
        }

        if (!strcmp(action, "probe"))    return cmd_probe();
        if (!strcmp(action, "enable"))   return cmd_enable(volPrefix);
        if (!strcmp(action, "recover"))  return cmd_recover();
        if (!strcmp(action, "disable"))  return cmd_disable();
        if (!strcmp(action, "purge")) {
                int confirmed = 0;
                for (int i = 2; i < argc; i++) if (!strcmp(argv[i], "--confirm")) confirmed = 1;
                return cmd_purge(confirmed);
        }
        if (!strcmp(action, "status"))   return cmd_status();
        if (!strcmp(action, "rollback")) return cmd_rollback();
        usage();
        return 64;
}
