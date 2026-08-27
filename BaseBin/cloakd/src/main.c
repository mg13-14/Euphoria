#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <dispatch/dispatch.h>

#include <sys/mount.h>
#include <sys/param.h>
#include <sys/stat.h>
#include <sys/types.h>

#include <libjailbreak/cloak.h>
#include <libjailbreak/jbroot.h>
#include <libjailbreak/util.h>

/*
 * cloakd — Euphoria stealth mount daemon
 *
 * The "cloak" module hides root privileges and jailbreak artefacts while the
 * jailbreak is active (see libjailbreak/src/cloak.h).  This daemon owns the
 * mount side of that promise:
 *
 *   1. On startup it pulls the cloak policy from launchdhook.
 *   2. If cloaking is enabled it creates the cover mount: a read-only
 *      nullfs mount whose mount point looks completely innocuous.  This
 *      mount doubles as the persistent "jailbroken" marker that survives
 *      userspace crashes (the kernel keeps the mount until unmount/reboot).
 *   3. It reports the mount state (or any error string) back into
 *      launchdhook via JBS_CLOAK_MOUNT_REPORT so that the app and jbctl can
 *      display it, and so systemhook knows whether mount hiding has to
 *      filter one or two entries.
 *   4. It re-checks the policy periodically; when cloaking gets disabled it
 *      unmounts the cover mount again.
 *
 * The mount point is deliberately boring ("com.apple" style dot-file) and
 * is additionally filtered out of getfsstat() results for untrusted
 * processes by systemhook's cloak interposer.
 */

#define CLOAKD_DEFAULT_MOUNT_POINT "/private/var/.com.apple.fsinterop"
#define CLOAKD_STAGING_DIR         "/.cleanser_staging"

static char gMountPoint[MAXPATHLEN] = CLOAKD_DEFAULT_MOUNT_POINT;
static bool gMounted = false;
static volatile sig_atomic_t gQuit = 0;

static void cloakd_settle_signal(int sig)
{
	gQuit = 1;
}

static bool cloakd_ensure_mount_point(void)
{
	// The mount point must exist and must never be writable by non-root,
	// otherwise an untrusted process could plant content in it.
	struct stat sb = { 0 };
	if (lstat(gMountPoint, &sb) != 0) {
		if (mkdir(gMountPoint, 0) != 0 && errno != EEXIST) return false;
	} else if (!S_ISDIR(sb.st_mode)) {
		return false;
	}
	chmod(gMountPoint, 0);
	return true;
}

static bool cloakd_do_mount(void)
{
	if (!cloakd_ensure_mount_point()) return false;

	// Cover mount: read-only nullfs view of an empty staging directory
	// inside the jbroot.  To an untrusted observer this looks like yet
	// another obscure system mount.
	char staging[MAXPATHLEN];
	strlcpy(staging, JBROOT_PATH(CLOAKD_STAGING_DIR), sizeof(staging));

	struct stat sb = { 0 };
	if (lstat(staging, &sb) != 0) {
		mkdir(staging, 0755);
	}

	// nullfs is bind-style: source filesystem path goes in fspec
	char fspec[MAXPATHLEN];
	strlcpy(fspec, staging, sizeof(fspec));

	struct {
		const char *fspec;
	} args = {
		.fspec = fspec,
	};

	// MNT_RDONLY | MNT_NOSUID | MNT_NOEXEC keeps the footprint minimal
	if (mount("nullfs", gMountPoint, MNT_RDONLY | MNT_NOSUID | MNT_NOEXEC, &args) != 0) {
		// Fallback: some kernels reject nullfs from userspace; report it
		// verbatim so the UI can explain why stealth mode is degraded.
		return false;
	}

	gMounted = true;
	return true;
}

static void cloakd_do_unmount(void)
{
	if (gMounted) {
		unmount(gMountPoint, MNT_FORCE);
		gMounted = false;
	}
}

static void cloakd_report(void)
{
	const char *error = NULL;
	if (!gMounted) {
		error = "cover mount not active";
	}
	cloak_report_mount(gMounted ? gMountPoint : "", error ? error : "");
}

static void cloakd_sync_with_policy(void)
{
	cloak_policy_t policy = { 0 };
	if (cloak_get_policy(&policy) != 0) return;

	if (policy.enabled && !gMounted) {
		cloakd_do_mount();
		cloakd_report();
	}
	else if (!policy.enabled && gMounted) {
		cloakd_do_unmount();
		cloakd_report();
	}
	else if (gMounted) {
		// Periodic refresh of the report so launchdhook state cannot go
		// stale (e.g. after a launchdhook crash + relaunch).
		cloakd_report();
	}
}

int main(int argc, char *argv[])
{
	if (geteuid() != 0) {
		fprintf(stderr, "cloakd: must run as root\n");
		return 1;
	}

	signal(SIGTERM, cloakd_settle_signal);
	signal(SIGINT,  cloakd_settle_signal);

	// Initial sync, then re-check every 5 seconds
	cloakd_sync_with_policy();

	dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
	if (timer) {
		dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 5LL * NSEC_PER_SEC), 5LL * NSEC_PER_SEC, 1LL * NSEC_PER_SEC);
		dispatch_source_set_event_handler(timer, ^{
			cloakd_sync_with_policy();
		});
		dispatch_resume(timer);
	}

	dispatch_main();

	// Unreachable in practice, but keeps the intent documented
	if (gQuit) cloakd_do_unmount();
	return 0;
}
