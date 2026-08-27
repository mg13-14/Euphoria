//
//  dirutils.m
//  Euphoria bootstrapfs — measurement, preflight and hardened copy
//

#import "dirutils.h"
#import <Foundation/Foundation.h>
#import <copyfile.h>
#import <dirent.h>
#import <errno.h>
#import <fcntl.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <sys/mount.h>
#import <sys/stat.h>
#import <sys/syslimits.h>
#import <unistd.h>

#define EUFS_COPY_ATTEMPTS 3
static const uint32_t eufs_retry_delay_ms[EUFS_COPY_ATTEMPTS] = { 250, 1000, 4000 };

static BOOL eufs_skip_entry(const char *name)
{
        return strcmp(name, ".") == 0 || strcmp(name, "..") == 0 ||
               strcmp(name, ".DS_Store") == 0 || strcmp(name, ".fseventsd") == 0 ||
               strcmp(name, ".Spotlight-V100") == 0 || strcmp(name, ".TemporaryItems") == 0;
}

// ---- measurement ----------------------------------------------------------

static int eufs_measure_rec(const char *src, eufs_size_summary *sum)
{
        DIR *d = opendir(src);
        if (!d) return -1;
        char child[PATH_MAX];
        struct dirent *de;
        while ((de = readdir(d)) != NULL) {
                if (eufs_skip_entry(de->d_name)) continue;
                snprintf(child, sizeof(child), "%s/%s", src, de->d_name);
                struct stat st;
                if (lstat(child, &st) != 0) continue; // racing deletions: skip, not fail
                if (S_ISDIR(st.st_mode)) {
                        sum->dirs++;
                        eufs_measure_rec(child, sum);
                }
                else if (S_ISLNK(st.st_mode)) {
                        sum->links++;
                }
                else if (S_ISREG(st.st_mode)) {
                        sum->files++;
                        sum->bytes += (uint64_t)st.st_size;
                }
        }
        closedir(d);
        return 0;
}

int eufs_measure_dir(const char *src, eufs_size_summary *out)
{
        if (!src || !out) return -1;
        memset(out, 0, sizeof(*out));
        struct stat st;
        if (lstat(src, &st) != 0 || !S_ISDIR(st.st_mode)) return -1;
        if (eufs_measure_rec(src, out) != 0) return -1;
        return 0;
}

uint64_t eufs_available_bytes(const char *mountPoint)
{
        struct statfs sfs;
        if (statfs(mountPoint, &sfs) != 0) return (uint64_t)-1;
        return (uint64_t)sfs.f_bavail * (uint64_t)sfs.f_bsize;
}

int eufs_ensure_directory(const char *path)
{
        char tmp[PATH_MAX];
        strlcpy(tmp, path, sizeof(tmp));
        size_t len = strlen(tmp);
        if (len == 0) return -1;
        for (char *p = tmp + 1; *p; p++) {
                if (*p == '/') {
                        *p = '\0';
                        mkdir(tmp, 0755);
                        *p = '/';
                }
        }
        return mkdir(tmp, 0755) == 0 || errno == EEXIST ? 0 : -1;
}

// ---- hardened copy --------------------------------------------------------

typedef struct {
        uint64_t dirBytesTotal;
        uint64_t dirBytesDone;
        uint64_t globalOffset;
        uint64_t globalTotal;
        eufs_copy_progress_cb cb;
        void *ctx;
        uint64_t lastEmit;
        uint64_t emitInterval;
        uint64_t filesCopied;
} eufs_copy_ctx;

static uint64_t eufs_now_ms(void)
{
        struct timeval tv;
        gettimeofday(&tv, NULL);
        return (uint64_t)(tv.tv_sec * 1000 + tv.tv_usec / 1000);
}

static void eufs_maybe_emit(eufs_copy_ctx *c, const char *path)
{
        uint64_t now = eufs_now_ms();
        if (c->cb && (now - c->lastEmit >= c->emitInterval)) {
                c->lastEmit = now;
                c->cb(path, c->dirBytesDone, c->dirBytesTotal,
                      c->globalOffset + c->dirBytesDone, c->globalTotal, c->ctx);
        }
}

static int eufs_copy_one_file(const char *src, const char *dst,
                              eufs_copy_ctx *c, char *lastError, size_t lastErrorLen)
{
        int attempt;
        for (attempt = 0; attempt < EUFS_COPY_ATTEMPTS; attempt++) {
                if (attempt > 0) usleep(eufs_retry_delay_ms[attempt] * 1000);

                copyfile_state_t st = copyfile_state_alloc();
                int r = copyfile(src, dst, st, COPYFILE_ALL | COPYFILE_EXCL);
                copyfile_state_free(st);

                if (r == 0) return 0;
                if (errno == ENOENT && attempt + 1 < EUFS_COPY_ATTEMPTS) continue; // transient
                if (lastError) {
                        snprintf(lastError, lastErrorLen, "copyfile(%s): %s (attempt %d/%d)",
                                 src, strerror(errno), attempt + 1, EUFS_COPY_ATTEMPTS);
                }
                return -1;
        }
        if (lastError) snprintf(lastError, lastErrorLen, "copyfile(%s): retries exhausted", src);
        return -1;
}

static int eufs_copy_rec(const char *src, const char *dst, eufs_copy_ctx *c,
                         char *lastError, size_t lastErrorLen)
{
        DIR *d = opendir(src);
        if (!d) {
                if (lastError) snprintf(lastError, lastErrorLen, "opendir(%s): %s", src, strerror(errno));
                return -1;
        }
        if (eufs_ensure_directory(dst) != 0) {
                closedir(d);
                if (lastError) snprintf(lastError, lastErrorLen, "mkdir(%s): %s", dst, strerror(errno));
                return -1;
        }
        // mirror the source directory's own mode after populating it
        struct stat dstSt;
        if (lstat(src, &dstSt) == 0) chmod(dst, dstSt.st_mode & 07777);

        char srcChild[PATH_MAX], dstChild[PATH_MAX];
        struct dirent *de;
        int rc = 0;
        while (rc == 0 && (de = readdir(d)) != NULL) {
                if (eufs_skip_entry(de->d_name)) continue;
                snprintf(srcChild, sizeof(srcChild), "%s/%s", src, de->d_name);
                snprintf(dstChild, sizeof(dstChild), "%s/%s", dst, de->d_name);

                struct stat st;
                if (lstat(srcChild, &st) != 0) continue;

                if (S_ISDIR(st.st_mode)) {
                        rc = eufs_copy_rec(srcChild, dstChild, c, lastError, lastErrorLen);
                }
                else if (S_ISLNK(st.st_mode)) {
                        // Preserve the symlink TARGET VERBATIM — relative stays relative,
                        // absolute stays absolute.  Absolute targets pointing into a
                        // mount-over directory keep resolving to identical content after
                        // commit, so no remapping is needed (closes ghh TODO).
                        char target[PATH_MAX];
                        ssize_t n = readlink(srcChild, target, sizeof(target) - 1);
                        if (n < 0) {
                                if (lastError) snprintf(lastError, lastErrorLen, "readlink(%s): %s", srcChild, strerror(errno));
                                rc = -1;
                                break;
                        }
                        target[n] = '\0';
                        unlink(dstChild);
                        if (symlink(target, dstChild) != 0) {
                                if (lastError) snprintf(lastError, lastErrorLen, "symlink(%s): %s", dstChild, strerror(errno));
                                rc = -1;
                                break;
                        }
                }
                else if (S_ISREG(st.st_mode)) {
                        unlink(dstChild);
                        if (eufs_copy_one_file(srcChild, dstChild, c, lastError, lastErrorLen) != 0) {
                                rc = -1;
                                break;
                        }
                        c->dirBytesDone += (uint64_t)st.st_size;
                        c->filesCopied++;
                        eufs_maybe_emit(c, srcChild);
                }
                // other node types (devices, sockets, fifos) do not occur in the
                // copied trees; skipped on purpose
        }
        closedir(d);
        return rc;
}

int eufs_copy_dir(const char *src, const char *dst,
                  uint64_t globalOffset, uint64_t globalTotal,
                  eufs_copy_progress_cb cb, void *ctx,
                  char *lastError, size_t lastErrorLen)
{
        eufs_size_summary sum = { 0 };
        if (eufs_measure_dir(src, &sum) != 0) {
                if (lastError) snprintf(lastError, lastErrorLen, "measure(%s) failed", src);
                return -1;
        }
        eufs_copy_ctx c = {
                .dirBytesTotal = sum.bytes ? sum.bytes : 1,
                .dirBytesDone = 0,
                .globalOffset = globalOffset,
                .globalTotal = globalTotal ? globalTotal : 1,
                .cb = cb,
                .ctx = ctx,
                .lastEmit = 0,
                .emitInterval = 250, // ms — 4 events/s max per copy phase
        };
        int rc = eufs_copy_rec(src, dst, &c, lastError, lastErrorLen);
        if (rc == 0 && cb) {
                cb(dst, c.dirBytesTotal, c.dirBytesTotal,
                   c.globalOffset + c.dirBytesDone, c.globalTotal, ctx); // final 100%
        }
        return rc;
}
