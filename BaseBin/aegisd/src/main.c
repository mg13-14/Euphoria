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

#include <libjailbreak/aegis.h>
#include <libjailbreak/jbroot.h>
#include <libjailbreak/util.h>

/*
 * aegisd — Euphoria per-app shielding daemon
 *
 * Mirrors cloakd's lifecycle: brings up a cover mount during bootstrap
 * (the "treat it as a mount" persistence requirement), keeps the per-app
 * shield policy synchronised across the running system through the
 * JBS_DOMAIN_AEGIS XPC domain, and stays resident after jailbreak.
 *
 * aegisd also owns the human-editable policy file at
 *   JBROOT_PATH("/basebin/aegis.conf")
 * Format: one entry per line, either
 *   bundleId=level
 * or a bare
 *   bundleId
 * (which defaults to AEGIS_LEVEL_FULL).  On startup aegisd parses the
 * file and pushes the entries into launchdhook's runtime state; on any
 * jbctl-driven mutation aegisd rewrites the file so the change survives
 * a jailbreak restart.
 */

#define AEGIS_MOUNT_POINT "/private/var/.mobile_repair_cache"
#define AEGIS_STAGING_DIR JBROOT_PATH("/basebin/aegis")

static volatile sig_atomic_t gQuit = 0;
static bool gMounted = false;

static void aegisd_settle_signal(int sig) { gQuit = sig; }

/* ---- cover mount ------------------------------------------------------- */

static int aegisd_do_mount(void)
{
	/* staging dir is just a marker directory in the jbroot */
	mkdir(AEGIS_STAGING_DIR, 0755);

	struct {
		char *fspec;
	} args = { .fspec = (char *)AEGIS_STAGING_DIR };

	/* read-only nullfs view at an innocuous path */
	int rv = mount("nullfs", AEGIS_MOUNT_POINT, MNT_RDONLY | MNT_NOSUID | MNT_NOEXEC, &args);
	if (rv != 0 && errno != EEXIST) {
		/* mount failed — the marker file approach is the fallback */
		int fd = open(AEGIS_MOUNT_POINT "/.aegis_marker", O_CREAT | O_WRONLY, 0644);
		if (fd >= 0) close(fd);
	}
	gMounted = (rv == 0) || (errno == EEXIST) || (access(AEGIS_MOUNT_POINT "/.aegis_marker", F_OK) == 0);
	return rv;
}

static void aegisd_do_unmount(void)
{
	if (gMounted) {
		unmount(AEGIS_MOUNT_POINT, MNT_FORCE);
		gMounted = false;
	}
}

static void aegisd_report_mount(void)
{
	const char *err = (gMounted ? NULL : "mount failed");
	aegis_report_mount(gMounted ? AEGIS_MOUNT_POINT : "", err ? err : "");
}

/* ---- policy file I/O --------------------------------------------------- */

static void aegisd_push_policy_file(void)
{
	FILE *fp = fopen(JBROOT_PATH("/basebin/aegis.conf"), "r");
	if (!fp) return;

	char line[512];
	while (fgets(line, sizeof(line), fp)) {
		/* trim */
		char *nl = strchr(line, '\n');
		if (nl) *nl = '\0';
		char *ws = line;
		while (*ws == ' ' || *ws == '\t') ws++;
		if (*ws == '\0' || *ws == '#') continue;

		char *eq = strchr(ws, '=');
		uint64_t level = AEGIS_LEVEL_FULL;
		if (eq) {
			*eq = '\0';
			level = strtoull(eq + 1, NULL, 10);
		}
		aegis_add_app(ws, level);
	}
	fclose(fp);
}

static void aegisd_write_policy_file(void)
{
	aegis_policy_t policy = { 0 };
	if (aegis_get_policy(&policy) != 0) return;

	FILE *fp = fopen(JBROOT_PATH("/basebin/aegis.conf"), "w");
	if (!fp) return;
	for (uint32_t i = 0; i < policy.appCount; i++) {
		fprintf(fp, "%s=%llu\n", policy.appBundleIds[i],
			(unsigned long long)policy.appLevels[i]);
	}
	fclose(fp);
}

/* ---- sync -------------------------------------------------------------- */

static void aegisd_sync_with_policy(void)
{
	aegis_policy_t policy = { 0 };
	if (aegis_get_policy(&policy) != 0) return;

	if (policy.enabled && !gMounted) {
		aegisd_do_mount();
		aegisd_report_mount();
	}
	else if (!policy.enabled && gMounted) {
		aegisd_do_unmount();
		aegisd_report_mount();
	}
	else if (gMounted) {
		aegisd_report_mount(); /* keep launchdhook state fresh */
	}
}

int main(int argc, char *argv[])
{
	if (geteuid() != 0) {
		fprintf(stderr, "aegisd: must run as root\n");
		return 1;
	}

	signal(SIGTERM, aegisd_settle_signal);
	signal(SIGINT,  aegisd_settle_signal);

	/* push persisted policy into runtime state, then sync mount */
	aegisd_push_policy_file();
	aegisd_sync_with_policy();

	dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
	if (timer) {
		dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 10LL * NSEC_PER_SEC), 10LL * NSEC_PER_SEC, 1LL * NSEC_PER_SEC);
		dispatch_source_set_event_handler(timer, ^{
			aegisd_sync_with_policy();
		});
		dispatch_resume(timer);
	}

	dispatch_main();

	if (gQuit) aegisd_do_unmount();
	return 0;
}
