#import "internal.h"
#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>
#import <sys/mount.h>
#import <libjailbreak/stock_fixes.h>
#import <libjailbreak/rootful_fakefs.h>

SInt32 CFUserNotificationDisplayAlert(CFTimeInterval timeout, CFOptionFlags flags, CFURLRef iconURL, CFURLRef soundURL, CFURLRef localizationURL, CFStringRef alertHeader, CFStringRef alertMessage, CFStringRef defaultButtonTitle, CFStringRef alternateButtonTitle, CFStringRef otherButtonTitle, CFOptionFlags *responseFlags) API_AVAILABLE(ios(3.0));

void execute_unsandboxed(void (^block)(void))
{
        uint64_t credBackup = 0;
        jbclient_root_steal_ucred(0, &credBackup);
        block();
        jbclient_root_steal_ucred(credBackup, NULL);
}

int mount_unsandboxed(const char *type, const char *dir, int flags, void *data)
{
        __block int r = 0;
        execute_unsandboxed(^{
                r = mount(type, dir, flags, data);
        });
        return r;
}

int unmount_unsandboxed(const char *dir, int flags)
{
        __block int r = 0;
        execute_unsandboxed(^{
                r = unmount(dir, flags);
        });
        return r;
}

bool is_protected(const char *path)
{
        struct statfs sb;
        statfs(path, &sb);
        return strcmp(path, sb.f_mntonname) == 0;
}

int ensure_protected(const char *path)
{
        if (!is_protected(path)) {
                return mount_unsandboxed("bindfs", path, 0, (void *)path);
        }
        return 0;
}

int ensure_unprotected(const char *path)
{
        if (is_protected(path)) {
                return unmount_unsandboxed(path, MNT_FORCE);
        }
        return 0;
}

int protection_set_active(bool active)
{
        int r = 0;
        if (active) {
                // Protect /private/preboot/UUID/<System, usr> from being modified by bind mounting them on top of themselves
                // This protects dumb users from accidentally deleting these, which would induce a recovery loop after rebooting
                r |= ensure_protected(prebootUUIDPath("/System"));
                r |= ensure_protected(prebootUUIDPath("/usr"));
        }
        else {
                r |= ensure_unprotected(prebootUUIDPath("/System"));
                r |= ensure_unprotected(prebootUUIDPath("/usr"));
        }
        return r;
}

bool fakelib_is_mounted(void)
{
        struct statfs fsb;
    if (statfs("/usr/lib", &fsb) != 0) return NO;
    return strcmp(fsb.f_mntonname, "/usr/lib") == 0;
}

int fakelib_set_mounted(bool mounted)
{
        int r = 0;
        if (mounted != fakelib_is_mounted()) {
                if (mounted) {
                        r = mount_unsandboxed("bindfs", "/usr/lib", MNT_RDONLY, (void *)JBROOT_PATH("/basebin/.fakelib"));
                }
                else {
                        r = unmount_unsandboxed("/usr/lib", MNT_FORCE);
                }
        }
        return r;
}

int jbctl_handle_internal(const char *command, int argc, char* argv[])
{
        if (!strcmp(command, "launchd_stash_port")) {
                mach_port_t *selfInitPorts = NULL;
                mach_msg_type_number_t selfInitPortsCount = 0;
                if (mach_ports_lookup(mach_task_self(), &selfInitPorts, &selfInitPortsCount) != 0) {
                        printf("ERROR: Failed port lookup on self\n");
                        return -1;
                }
                if (selfInitPortsCount < 3) {
                        printf("ERROR: Unexpected initports count on self\n");
                        return -1;
                }
                if (selfInitPorts[2] == MACH_PORT_NULL) {
                        printf("ERROR: Port to stash not set\n");
                        return -1;
                }

                printf("Port to stash: %u\n", selfInitPorts[2]);

                mach_port_t launchdTaskPort;
                if (task_for_pid(mach_task_self(), 1, &launchdTaskPort) != 0) {
                        printf("task_for_pid on launchd failed\n");
                        return -1;
                }
                mach_port_t *launchdInitPorts = NULL;
                mach_msg_type_number_t launchdInitPortsCount = 0;
                if (mach_ports_lookup(launchdTaskPort, &launchdInitPorts, &launchdInitPortsCount) != 0) {
                        printf("mach_ports_lookup on launchd failed\n");
                        return -1;
                }
                if (launchdInitPortsCount < 3) {
                        printf("ERROR: Unexpected initports count on launchd\n");
                        return -1;
                }
                launchdInitPorts[2] = selfInitPorts[2]; // Transfer port to launchd
                if (mach_ports_register(launchdTaskPort, launchdInitPorts, launchdInitPortsCount) != 0) {
                        printf("ERROR: Failed stashing port into launchd\n");
                        return -1;
                }
                mach_port_deallocate(mach_task_self(), launchdTaskPort);
                return 0;
        }
        else if (!strcmp(command, "protection")) {
                bool toSet = false;
                if (argc > 1) {
                        if (!strcmp(argv[1], "activate")) {
                                toSet = true;
                        }
                        else if (!strcmp(argv[1], "deactivate")) {
                                toSet = false;
                        }
                        else {
                                return -1;
                        }

                        return protection_set_active(toSet);
                }
                return -1;
        }
        else if (!strcmp(command, "rootful")) {
                // jbctl internal rootful <status|enable|recover|disable|rollback|purge>
                // Maintenance entry points into the bootstrapfs engine (T14:
                // switch flows; progress events are printed as JSON lines so
                // the App can parse them when driving this programmatically).
                if (argc > 1) {
                        const char *sub = argv[1];
                        const char *extra = NULL;
                        if (!strcmp(sub, "purge")) {
                                if (argc < 3 || strcmp(argv[2], "--confirm") != 0) {
                                        printf("Refusing to purge: this DESTROYS all rootful volumes and their contents.\n");
                                        printf("If you really want this, run: jbctl internal rootful purge --confirm\n");
                                        return 1;
                                }
                                extra = "--confirm";
                        }
                        static const char *allowed[] = { "status", "enable", "recover", "disable", "rollback", "purge", NULL };
                        bool ok = false;
                        for (int i = 0; allowed[i]; i++) ok = ok || !strcmp(sub, allowed[i]);
                        if (ok) {
                                char err[192] = { 0 };
                                int r = rootful_fakefs_run(sub, extra,
                                        ^(const char *line, void *ctx) {
                                                (void)ctx;
                                                printf("%s\n", line);
                                                fflush(stdout);
                                        }, NULL, err, sizeof(err));
                                if (r != 0 && err[0]) printf("ERROR: %s\n", err);
                                return r;
                        }
                }
                printf("Usage: jbctl internal rootful <status|enable|recover|disable|rollback|purge [--confirm]>\n");
                return -1;
        }
        else if (!strcmp(command, "fakelib")) {
                bool toMount = false;
                if (argc > 1) {
                        if (!strcmp(argv[1], "mount")) {
                                toMount = true;
                        }
                        else if (!strcmp(argv[1], "unmount")) {
                                toMount = false;
                        }
                        else {
                                return -1;
                        }

                        return fakelib_set_mounted(toMount);
                }
                return -1;
        }
        else if (!strcmp(command, "startup")) {
                protection_set_active(true);
                char *panicMessage = NULL;
                if (jbclient_watchdog_get_last_userspace_panic(&panicMessage) == 0) {
                        NSString *printMessage = [NSString stringWithFormat:@"Euphoria has protected you from a userspace panic by temporarily disabling tweak injection and triggering a userspace reboot instead. A log is available under Analytics in the Preferences app. You can reenable tweak injection in the Euphoria app.\n\nPanic message: \n%s", panicMessage];
                        CFUserNotificationDisplayAlert(0, 2/*kCFUserNotificationCautionAlertLevel*/, NULL, NULL, NULL, CFSTR("Watchdog Timeout"), (__bridge CFStringRef)printMessage, NULL, NULL, NULL, NULL);
                        free(panicMessage);
                }
                exec_cmd(JBROOT_PATH("/usr/bin/uicache"), "-a", NULL);
        }
        else if (!strcmp(command, "install_pkg")) {
                if (argc > 1) {
                        extern char **environ;
                        const char *dpkg = JBROOT_PATH("/usr/bin/dpkg");
                        int r = execve(dpkg, (char *const *)(const char *[]){dpkg, "-i", argv[1], NULL}, environ);
                        return r;
                }
                return -1;
        }
        return -1;
}
