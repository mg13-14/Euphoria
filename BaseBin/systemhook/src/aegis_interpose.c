#include "aegis_interpose.h"
#include "common/common.h"
#include "common/private.h"

#include <libjailbreak/aegis.h>
#include <libjailbreak/jbroot.h>
#include <libjailbreak/util.h>

#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mount.h>
#include <sys/param.h>
#include <sys/stat.h>
#include <spawn.h>
#include <mach-o/dyld.h>
#include <libproc.h>

#include "litehook.h"

// 构建修复：iOS SDK 头文件未声明 getfsent。以弱符号方式声明：链接器允许
// 未定义、运行时若 libSystem 未导出则该地址为 NULL，安装处的
// `if (getfsent)` 判断会自然跳过此 hook。
extern int getfsent(struct statfs *) __attribute__((weak));

/* ------------------------------------------------------------------------ */
/* Policy cache                                                              */
/* ------------------------------------------------------------------------ */

static aegis_policy_t gAegisPolicy = { 0 };
static bool gAegisActive = false;       // aegis enabled systemwide
static uint64_t gAegisLevel = AEGIS_LEVEL_OFF; // shield level for THIS process

/* ------------------------------------------------------------------------ */
/* Process matching                                                          */
/* ------------------------------------------------------------------------ */

static bool aegis_process_matches_list(const char *execPath)
{
	if (!execPath || !execPath[0]) return false;
	/* Extract the executable basename and the .app bundle dir name.
	 * Policy entries may be either a binary name ("MyApp"), a bundle
	 * directory ("MyApp.app"), a bundle id ("com.example.MyApp"), or a
	 * path prefix. We do a flexible match: if the entry appears anywhere
	 * in the executable path OR equals the basename, it matches. */
	char pathCopy[MAXPATHLEN];
	strlcpy(pathCopy, execPath, sizeof(pathCopy));

	const char *base = strrchr(pathCopy, '/');
	base = base ? base + 1 : pathCopy;

	/* Walk back to the .app bundle dir name if present */
	char *appMarker = strstr(pathCopy, ".app/");
	const char *bundleDir = NULL;
	if (appMarker) {
		*appMarker = '\0'; // truncate at ".app/"
		const char *slash = strrchr(pathCopy, '/');
		bundleDir = slash ? slash + 1 : pathCopy;
		*appMarker = '.'; // restore
	}

	for (uint32_t i = 0; i < gAegisPolicy.appCount; i++) {
		const char *entry = gAegisPolicy.appBundleIds[i];
		if (!entry || !entry[0]) continue;
		/* exact basename match */
		if (strcmp(entry, base) == 0) return true;
		/* bundle dir match */
		if (bundleDir && strcmp(entry, bundleDir) == 0) return true;
		/* substring / bundle-id match */
		if (strstr(execPath, entry) != NULL) return true;
	}
	return false;
}

static void aegis_determine_level(void)
{
	char execPath[MAXPATHLEN] = { 0 };
	if (proc_pidpath(getpid(), execPath, sizeof(execPath)) <= 0) return;

	if (aegis_process_matches_list(execPath)) {
		/* explicit per-app entry — find its level */
		char pathCopy[MAXPATHLEN];
		strlcpy(pathCopy, execPath, sizeof(pathCopy));
		const char *base = strrchr(pathCopy, '/');
		base = base ? base + 1 : pathCopy;
		char *appMarker = strstr(pathCopy, ".app/");
		const char *bundleDir = NULL;
		if (appMarker) {
			*appMarker = '\0';
			const char *slash = strrchr(pathCopy, '/');
			bundleDir = slash ? slash + 1 : pathCopy;
		}
		for (uint32_t i = 0; i < gAegisPolicy.appCount; i++) {
			const char *entry = gAegisPolicy.appBundleIds[i];
			if (!entry) continue;
			if (strcmp(entry, base) == 0 ||
				(bundleDir && strcmp(entry, bundleDir) == 0) ||
				strstr(execPath, entry) != NULL) {
				gAegisLevel = gAegisPolicy.appLevels[i];
				return;
			}
		}
	}
	/* Not on the list: fall back to the default level only for processes
	 * that look like user apps (path contains .app); system daemons are
	 * never shielded by default. */
	if (strstr(execPath, ".app/") != NULL) {
		gAegisLevel = gAegisPolicy.defaultLevel;
	}
	else {
		gAegisLevel = AEGIS_LEVEL_OFF;
	}
}

/* ------------------------------------------------------------------------ */
/* File-existence syscall interposition                                      */
/* ------------------------------------------------------------------------ */

static bool aegis_should_suppress_path(const char *path)
{
	if (gAegisLevel < AEGIS_LEVEL_LITE) return false;
	if (!path) return false;
	return aegis_path_is_jailbreak_artefact(path);
}

/* stat family */
static int (*aegis_stat_orig)(const char *restrict, struct stat *restrict) = NULL;
static int aegis_stat_hook(const char *restrict path, struct stat *restrict buf)
{
	if (aegis_should_suppress_path(path)) { errno = ENOENT; return -1; }
	return aegis_stat_orig(path, buf);
}

static int (*aegis_lstat_orig)(const char *restrict, struct stat *restrict) = NULL;
static int aegis_lstat_hook(const char *restrict path, struct stat *restrict buf)
{
	if (aegis_should_suppress_path(path)) { errno = ENOENT; return -1; }
	return aegis_lstat_orig(path, buf);
}

static int (*aegis_access_orig)(const char *, int) = NULL;
static int aegis_access_hook(const char *path, int mode)
{
	if (aegis_should_suppress_path(path)) { errno = ENOENT; return -1; }
	return aegis_access_orig(path, mode);
}

static int (*aegis_open_orig)(const char *, int, ...) = NULL;
static int aegis_open_hook(const char *path, int flags, ...)
{
	if (aegis_should_suppress_path(path)) { errno = ENOENT; return -1; }
	/* forward varargs (mode) when O_CREAT was requested */
	if (flags & O_CREAT) {
		va_list ap; va_start(ap, flags);
		mode_t mode = (mode_t)va_arg(ap, int);
		va_end(ap);
		return aegis_open_orig(path, flags, mode);
	}
	return aegis_open_orig(path, flags);
}

static int (*aegis_openat_orig)(int, const char *, int, ...) = NULL;
static int aegis_openat_hook(int fd, const char *path, int flags, ...)
{
	if (aegis_should_suppress_path(path)) { errno = ENOENT; return -1; }
	if (flags & O_CREAT) {
		va_list ap; va_start(ap, flags);
		mode_t mode = (mode_t)va_arg(ap, int);
		va_end(ap);
		return aegis_openat_orig(fd, path, flags, mode);
	}
	return aegis_openat_orig(fd, path, flags);
}

static int (*aegis_faccessat_orig)(int, const char *, int, int) = NULL;
static int aegis_faccessat_hook(int fd, const char *path, int mode, int flag)
{
	if (aegis_should_suppress_path(path)) { errno = ENOENT; return -1; }
	return aegis_faccessat_orig(fd, path, mode, flag);
}

/* ------------------------------------------------------------------------ */
/* posix_spawn env scrubbing                                                 */
/* ------------------------------------------------------------------------ */

static bool aegis_env_var_is_injection(const char *env)
{
	if (!env) return false;
	static const char *strip_prefixes[] = {
		"DYLD_INSERT_LIBRARIES=",
		"DYLD_LIBRARY_PATH=",
		"DYLD_FRAMEWORK_PATH=",
		"_MSSAFEWORD=",            // MobileSubstrate secret
		"OBJC_DISABLE_INITIALIZE_FORK_SAFETY=",
	};
	for (size_t i = 0; i < sizeof(strip_prefixes)/sizeof(strip_prefixes[0]); i++) {
		if (strncmp(env, strip_prefixes[i], strlen(strip_prefixes[i])) == 0) return true;
	}
	return false;
}

/* Build a filtered envp (caller frees). Returns NULL on failure or when
 * nothing needs stripping (in which case the original envp is safe to use). */
static char **aegis_scrub_env(char *const *envp)
{
	if (!envp) return NULL;
	size_t count = 0, kept = 0;
	while (envp[count]) count++;

	char **out = calloc(count + 1, sizeof(char *));
	if (!out) return NULL;

	for (size_t i = 0; i < count; i++) {
		if (!aegis_env_var_is_injection(envp[i])) {
			out[kept++] = envp[i];
		}
	}
	out[kept] = NULL;
	return out;
}

extern int __posix_spawn(pid_t *restrict, const char *restrict, struct _posix_spawn_args_desc *restrict, char *const argv[restrict], char *const envp[restrict]);
extern int __posix_spawnp(pid_t *restrict, const char *restrict, struct _posix_spawn_args_desc *restrict, char *const argv[restrict], char *const envp[restrict]);

static int (*aegis_posix_spawn_orig)(pid_t *restrict, const char *restrict, struct _posix_spawn_args_desc *restrict, char *const argv[restrict], char *const envp[restrict]) = NULL;
static int aegis_posix_spawn_hook(pid_t *restrict pid, const char *restrict path, struct _posix_spawn_args_desc *restrict desc, char *const argv[restrict], char *const envp[restrict])
{
	char **scrubbed = NULL;
	if (gAegisLevel >= AEGIS_LEVEL_LITE) {
		scrubbed = aegis_scrub_env(envp);
	}
	char *const *useEnvp = scrubbed ? scrubbed : envp;
	int r = aegis_posix_spawn_orig(pid, path, desc, argv, useEnvp);
	if (scrubbed) free(scrubbed);
	return r;
}

/* ------------------------------------------------------------------------ */
/* Mount enumeration hiding (complement to cloak; per-app)                  */
/* ------------------------------------------------------------------------ */

static int (*aegis_getfsent_orig)(struct statfs *) = NULL;
static int aegis_getfsent_hook(struct statfs *buf)
{
	int r = aegis_getfsent_orig(buf);
	(void)r;
	/* If this entry is a jailbreak artefact, skip to the next by recursing
	 * once. getfsent is iterative (one entry per call); skipping means
	 * calling orig again to fetch the next. */
	if (gAegisLevel >= AEGIS_LEVEL_PARANOID && buf && buf->f_mntonname[0]) {
		if (aegis_path_is_jailbreak_artefact(buf->f_mntonname)) {
			return aegis_getfsent_orig(buf);
		}
	}
	return r;
}

/* ------------------------------------------------------------------------ */
/* Installation                                                              */
/* ------------------------------------------------------------------------ */

void aegis_interpose_init(void)
{
	if (aegis_get_policy(&gAegisPolicy) != 0) return;
	if (!gAegisPolicy.enabled) return;
	gAegisActive = true;

	aegis_determine_level();
	if (gAegisLevel == AEGIS_LEVEL_OFF) return;

	/* LITE+: file-existence + spawn scrub */
	if (gAegisLevel >= AEGIS_LEVEL_LITE) {
		litehook_hook_function(stat,        aegis_stat_hook);
		litehook_hook_function(lstat,       aegis_lstat_hook);
		litehook_hook_function(access,      aegis_access_hook);
		litehook_hook_function(open,        aegis_open_hook);
		litehook_hook_function(openat,      aegis_openat_hook);
		litehook_hook_function(faccessat,  aegis_faccessat_hook);
		litehook_hook_function(__posix_spawn,  aegis_posix_spawn_hook);
	}
	/* PARANOID: also hide mount enumeration entries */
	if (gAegisLevel >= AEGIS_LEVEL_PARANOID) {
		if (getfsent) litehook_hook_function(getfsent, aegis_getfsent_hook);
	}
}
