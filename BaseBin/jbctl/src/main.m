#import <libjailbreak/libjailbreak.h>
#import <libjailbreak/jbclient_xpc.h>
#import <libjailbreak/jbclient_mach.h>
#import <libjailbreak/stock_fixes.h>
#import <libjailbreak/rootful.h>
#import <libjailbreak/cloak.h>
#import <libjailbreak/aegis.h>
#import "internal.h"

#import <Foundation/Foundation.h>
#import <CoreServices/LSApplicationProxy.h>
#import <CoreServices/LSApplicationWorkspace.h>

int reboot3(uint64_t flags, ...);
#define RB2_USERREBOOT (0x2000000000000000llu)
extern char **environ;

void print_usage(void)
{
	printf("Usage: jbctl <command> <arguments>\n\
Available commands:\n\
	proc_set_debugged <pid>\t\tMarks the process with the given pid as being debugged, allowing invalid code pages inside of it\n\
	trustcache info\t\t\tPrint info about all jailbreak related trustcaches and the cdhashes contained in them\n\
	trustcache clear\t\tClears all existing cdhashes from the jailbreaks trustcache\n\
	trustcache add <cdhash>\t\tAdd an arbitrary cdhash to the jailbreaks trustcache\n\
	update <tipa/basebin/tarball> <path>\tInitiates a jailbreak update either based on a TIPA, based on a basebin.tar file or based on a standalone tarball, TIPA installation depends on TrollStore, afterwards it triggers a userspace reboot\n");
}

int main(int argc, char* argv[])
{
	if (!strcmp(argv[argc-1], "earlyboot")) {
		// If jbctl is spawned in "early boot" state, the jbserver port needs to be obtained from registeredPorts[0] instead
		mach_port_t *registeredPorts;
		mach_msg_type_number_t registeredPortsCount = 0;
		if (mach_ports_lookup(mach_task_self(), &registeredPorts, &registeredPortsCount) == KERN_SUCCESS) {
			jbclient_xpc_set_custom_port(registeredPorts[0]);

			for(mach_msg_type_number_t i = 1; i < registeredPortsCount; i++) {
				mach_port_deallocate(mach_task_self(), registeredPorts[i]);
			}
			vm_deallocate(mach_task_self(), (vm_address_t)registeredPorts, registeredPortsCount * sizeof(mach_port_t));
		}
	}

	setvbuf(stdout, NULL, _IOLBF, 0);
	if (argc < 2) {
		print_usage();
		return 1;
	}

	if (getuid() != 0 && geteuid() == 0) {
		// When jailbroken the Euphoria app cannot have uid 0 because it can't drop it anymore without loosing it
		// So in some cases (e.g. for spawning dpkg) we need to use jbctl to get it
		setuid(0);
	}

	if (argc > 2) {
		if (!strcmp(argv[argc-2], "--waitfor")) {
			// When the Euphoria app spawns jbctl it needs to clean up it's own ucred before jbctl does the requested action
			// For this it will attach a pipe fd and write to it once the cleanup is done, so we need to wait until that write happens
			int fd = atoi(argv[argc-1]);
			int r = 0;
			read(fd, &r, sizeof(r));
			close(fd);
		}
	}

	const char *rootPath = jbclient_get_jbroot();
	if (rootPath) {
		gSystemInfo.jailbreakInfo.rootPath = strdup(rootPath);
	}

	char *cmd = argv[1];
	if (!strcmp(cmd, "proc_set_debugged")) {
		if (argc != 3) {
			print_usage();
			return 1;
		}
		int pid = atoi(argv[2]);
		int64_t result = jbclient_platform_set_process_debugged(pid, true);
		if (result == 0) {
			printf("Successfully marked proc of pid %d as debugged\n", pid);
		}
		else {
			printf("Failed to mark proc of pid %d as debugged\n", pid);
		}
	}
	else if (!strcmp(cmd, "trustcache")) {
		if (argc < 3) {
			print_usage();
			return 2;
		}
		if (getuid() != 0) {
			printf("ERROR: trustcache subcommand requires root.\n");
			return 3;
		}
		const char *trustcacheCmd = argv[2];
		if (!strcmp(trustcacheCmd, "info")) {
			xpc_object_t tcArr = nil;
			if (jbclient_root_trustcache_info(&tcArr) == 0) {
				size_t tcCount = xpc_array_get_count(tcArr);
				for (size_t i = 0; i < tcCount; i++) {
					xpc_object_t tc = xpc_array_get_dictionary(tcArr, i);
					size_t uuidLength = 0;
					const void *uuidData = xpc_dictionary_get_data(tc, "uuid", &uuidLength);
					xpc_object_t cdhashesArr = xpc_dictionary_get_array(tc, "cdhashes");
					if (uuidData && cdhashesArr) {
						size_t length = xpc_array_get_count(cdhashesArr);
						char uuidString[uuidLength * 2 + 1];
						convert_data_to_hex_string(uuidData, uuidLength, uuidString);
						printf("Jailbreak Trustcache %zd <UUID: %s> (length: %zd)\n", i, uuidString, length);
						for (size_t j = 0; j < length; j++) {
							size_t cdhashLength = 0;
							const void *cdhashData = xpc_array_get_data(cdhashesArr, j, &cdhashLength);
							if (cdhashData) {
								char cdhashString[cdhashLength * 2 + 1];
								convert_data_to_hex_string(cdhashData, cdhashLength, cdhashString);
								printf("| %zd:\t%s\n", j+1, cdhashString);
							}
						}
					}
				}
			}
			return 0;
		}
		else if (!strcmp(trustcacheCmd, "clear")) {
			return jbclient_root_trustcache_clear();
		}
		else if (!strcmp(trustcacheCmd, "add")) {
			if (argc < 4) {
				print_usage();
				return 2;
			}
			const char *cdhashString = argv[3];
			if (strlen(cdhashString) != (sizeof(cdhash_t) * 2)) {
				printf("ERROR: passed cdhash has wrong length\n");
				return 2;
			}
			cdhash_t cdhash;
			if (convert_hex_string_to_data(cdhashString, &cdhash)) {
				printf("ERROR: passed cdhash is malformed\n");
				return 2;
			}
			return jbclient_root_trustcache_add_cdhash(cdhash, sizeof(cdhash));
		}
	}
	else if (!strcmp(cmd, "reboot_userspace")) {
		return reboot3(RB2_USERREBOOT);
	}
	else if (!strcmp(cmd, "respring")) {
		const char *sbreloadPath = JBROOT_PATH("/usr/bin/sbreload");
		if (execve(sbreloadPath, (char *[]){ (char *)sbreloadPath, NULL }, environ) != 0) {
			killall("/usr/libexec/backboardd", SIGTERM);
		}
	}
	else if (!strcmp(cmd, "rebuild_icon_cache")) {
		BOOL suc = [[LSApplicationWorkspace defaultWorkspace] _LSPrivateRebuildApplicationDatabasesForSystemApps:YES internal:YES user:YES];
		return suc ? 0 : -1;
	}
	else if (!strcmp(cmd, "update")) {
		if (argc < 4) {
			print_usage();
			return 2;
		}
		char *updateType = argv[2];
		char *updateFile = argv[3];
		if (access(updateFile, F_OK) != 0) {
			printf("ERROR: File %s does not exist\n", updateFile);
			return 3;
		}

		if (!strcmp(updateType, "tipa")) {
			setsid();

			LSApplicationProxy *trollstoreAppProxy = [LSApplicationProxy applicationProxyForIdentifier:@"com.opa334.TrollStore"];
			if (!trollstoreAppProxy || !trollstoreAppProxy.installed) {
				printf("Unable to locate TrollStore, doesn't seem like it's installed.\n");
				return 4;
			}
			NSString *trollstorehelperPath = [trollstoreAppProxy.bundleURL.path stringByAppendingPathComponent:@"trollstorehelper"];
			int r = exec_cmd(trollstorehelperPath.fileSystemRepresentation, "install", "skip-uicache", "force", updateFile, NULL);
			if (r != 0) {
				printf("Failed to install tipa via TrollStore: %d\n", r);
				return 5;
			}

			LSApplicationProxy *euphoriaAppProxy = [LSApplicationProxy applicationProxyForIdentifier:@"dev.euphoria.Euphoria"];
			if (!euphoriaAppProxy) {
				printf("Unable to locate newly installed Euphoria build.\n");
				return 6;
			}
			updateFile = strdup([euphoriaAppProxy.bundleURL.path stringByAppendingPathComponent:@"basebin.tar"].fileSystemRepresentation);
			// Fall through to basebin installation
		}
		else if (!strcmp(updateType, "tarball")) {
			NSString *tmpPath = [@"/tmp" stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
			[[NSFileManager defaultManager] createDirectoryAtPath:tmpPath withIntermediateDirectories:NO attributes:nil error:nil];
			int r = libarchive_unarchive(updateFile, tmpPath.fileSystemRepresentation);
			if (r != 0) {
				printf("Failed to extract tarball: %d\n", r);
				return 7;
			}
			updateFile = strdup([tmpPath stringByAppendingPathComponent:@"basebin.tar"].fileSystemRepresentation);
			// Fall through to basebin installation
		}
		else if (strcmp(updateType, "basebin") != 0) {
			// If type is not tipa, tarball or basebin, bail out
			print_usage();
			return 2;
		}

		int64_t result = jbclient_platform_stage_jailbreak_update(updateFile);
		if (result == 0) {
			printf("Staged update for installation during the next userspace reboot, userspace rebooting now...\n");
			usleep(10000);
			return reboot3(RB2_USERREBOOT);
		}
		else {
			printf("Staging update failed with error code %lld\n", result);
			return result;
		}
	}
	else if (!strcmp(cmd, "internal")) {
		if (getuid() != 0) return 41;
		if (argc < 3) return 42;

		const char *internalCmd = argv[2];
		return jbctl_handle_internal(internalCmd, argc-2, &argv[2]);
	}

		else if (!strcmp(cmd, "rootful")) {
		        if (getuid() != 0) {
		                printf("Error: rootful requires root\n");
		                return 41;
		        }
		        if (argc < 3) {
		                printf("Usage: jbctl rootful <status|enable|disable>\n");
		                return 1;
		        }
		        const char *rootfulCmd = argv[2];
		        if (!strcmp(rootfulCmd, "status")) {
		                rootful_status_t status = { 0 };
		                int r = rootful_get_status(&status);
		                if (r != 0) {
		                        printf("Error: rootful_get_status failed (%s)\n", strerror(r));
		                        return r;
		                }
		                printf("Rootful mode:\n");
		                printf("  Root filesystem remounted read-write: %s\n", status.rootMountedRW ? "yes" : "no");
		                printf("  Overlay mounts active:               %s\n", status.overlayActive ? "yes" : "no");
		                printf("  Configuration supported:             %s\n", rootful_supported_configuration() ? "yes" : "no");
		                printf("  Last error:                          %s\n", status.lastError[0] ? status.lastError : "none");
		                return 0;
		        }
		        else if (!strcmp(rootfulCmd, "enable")) {
		                rootful_status_t status = { 0 };
		                int r = rootful_enable(true, &status);
		                if (r != 0) {
		                        printf("Error: rootful_enable failed (%s)\n", strerror(r));
		                        return r;
		                }
		                printf("Rootful mode enabled (root RW: %s, overlays: %s)\n",
		                        status.rootMountedRW ? "yes" : "no",
		                        status.overlayActive ? "yes" : "no");
		                return 0;
		        }
		        else if (!strcmp(rootfulCmd, "disable")) {
		                int r = rootful_disable();
		                if (r != 0) {
		                        printf("Error: rootful_disable failed (%s)\n", strerror(r));
		                        return r;
		                }
		                printf("Rootful mode disabled\n");
		                return 0;
		        }
		        printf("Usage: jbctl rootful <status|enable|disable>\n");
		        return 1;
		}
		else if (!strcmp(cmd, "cloak")) {
		        if (getuid() != 0) {
		                printf("Error: cloak requires root\n");
		                return 41;
		        }
		        if (argc < 3) {
		                printf("Usage: jbctl cloak <status|enable|disable|set> [options]\n");
		                return 1;
		        }
		        const char *cloakCmd = argv[2];
		        if (!strcmp(cloakCmd, "status")) {
		                cloak_policy_t policy = { 0 };
		                if (cloak_get_policy(&policy) != 0) {
		                        printf("Error: unable to query cloak policy\n");
		                        return 1;
		                }
		                cloak_mount_status_t mnt = { 0 };
		                cloak_get_mount_status(&mnt);
		                printf("Cloak (stealth) mode:\n");
		                printf("  Enabled:          %s\n", policy.enabled ? "yes" : "no");
		                printf("  Hide mounts:      %s\n", policy.hideMounts ? "yes" : "no");
		                printf("  Hide credentials: %s\n", policy.hideCredentials ? "yes" : "no");
		                printf("  Hide trustcache:  %s\n", policy.hideTrustcache ? "yes" : "no");
		                printf("  Stealth level:    %llu\n", (unsigned long long)policy.stealthLevel);
		                printf("  Cover mount:      %s\n", mnt.active ? mnt.mountPoint : "not mounted");
		                if (mnt.error[0]) printf("  Last error:       %s\n", mnt.error);
		                return 0;
		        }
		        else if (!strcmp(cloakCmd, "enable")) {
		                int r = cloak_enable();
		                if (r != 0) {
		                        printf("Error: cloak_enable failed\n");
		                        return r;
		                }
		                printf("Cloak enabled (cloakd will bring up the cover mount)\n");
		                return 0;
		        }
		        else if (!strcmp(cloakCmd, "disable")) {
		                int r = cloak_disable();
		                if (r != 0) {
		                        printf("Error: cloak_disable failed\n");
		                        return r;
		                }
		                printf("Cloak disabled\n");
		                return 0;
		        }
		        else if (!strcmp(cloakCmd, "set")) {
		                // jbctl cloak set hideMounts=1 hideCredentials=1 hideTrustcache=1 stealthLevel=2
		                cloak_policy_t policy = { 0 };
		                if (cloak_get_policy(&policy) != 0) {
		                        printf("Error: unable to query cloak policy\n");
		                        return 1;
		                }
		                for (int i = 3; i < argc; i++) {
		                        char *arg = argv[i];
		                        char *eq = strchr(arg, '=');
		                        if (!eq) continue;
		                        *eq = '\0';
		                        const char *key = arg;
		                        const char *value = eq + 1;
		                        if (!strcmp(key, "hideMounts")) policy.hideMounts = atoi(value);
		                        else if (!strcmp(key, "hideCredentials")) policy.hideCredentials = atoi(value);
		                        else if (!strcmp(key, "hideTrustcache")) policy.hideTrustcache = atoi(value);
		                        else if (!strcmp(key, "stealthLevel")) policy.stealthLevel = strtoull(value, NULL, 10);
		                        // R40: blacklistMode=<0|1>（黑名单制开关——拉黑的 app 才被过滤）
		                        else if (!strcmp(key, "blacklistMode")) policy.blacklistMode = (strtoull(value, NULL, 10) != 0);
		                }
		                int r = cloak_set_options(&policy);
		                if (r != 0) {
		                        printf("Error: cloak_set_options failed\n");
		                        return r;
		                }
		                printf("Cloak options updated\n");
		                return 0;
		        }
		        printf("Usage: jbctl cloak <status|enable|disable|set> [options]\n");
		        return 1;
		}

	else if (!strcmp(cmd, "aegis")) {
		if (getuid() != 0) {
			printf("Error: aegis requires root\n");
			return 41;
		}
		if (argc < 3) {
			printf("Usage: jbctl aegis <status|enable|disable|set-level|add|remove|list|clear> [args]\n");
			return 1;
		}
		const char *aegisCmd = argv[2];
		if (!strcmp(aegisCmd, "status")) {
			aegis_policy_t policy = { 0 };
			if (aegis_get_policy(&policy) != 0) {
				printf("Error: unable to query aegis policy\n");
				return 1;
			}
			printf("Aegis (per-app shielding):\n");
			printf("  Enabled:        %s\n", policy.enabled ? "yes" : "no");
			printf("  Default level:  %llu\n", (unsigned long long)policy.defaultLevel);
			printf("  Shielded apps:  %u\n", policy.appCount);
			for (uint32_t i = 0; i < policy.appCount && i < AEGIS_MAX_APPS; i++) {
				printf("    %s (level %llu)\n", policy.appBundleIds[i], (unsigned long long)policy.appLevels[i]);
			}
			return 0;
		}
		else if (!strcmp(aegisCmd, "enable")) {
			int r = aegis_enable();
			if (r != 0) { printf("Error: aegis_enable failed\n"); return r; }
			printf("Aegis enabled (aegisd will bring up the cover mount)\n");
			return 0;
		}
		else if (!strcmp(aegisCmd, "disable")) {
			int r = aegis_disable();
			if (r != 0) { printf("Error: aegis_disable failed\n"); return r; }
			printf("Aegis disabled\n");
			return 0;
		}
		else if (!strcmp(aegisCmd, "set-level")) {
			if (argc < 4) { printf("Usage: jbctl aegis set-level <0=off|1=lite|2=full|3=paranoid>\n"); return 1; }
			uint64_t level = strtoull(argv[3], NULL, 10);
			int r = aegis_set_default_level(level);
			if (r != 0) { printf("Error: aegis_set_default_level failed\n"); return r; }
			printf("Aegis default level set to %llu\n", (unsigned long long)level);
			return 0;
		}
		else if (!strcmp(aegisCmd, "add")) {
			if (argc < 4) { printf("Usage: jbctl aegis add <bundleId> [level]\n"); return 1; }
			const char *bid = argv[3];
			uint64_t level = (argc >= 5) ? strtoull(argv[4], NULL, 10) : AEGIS_LEVEL_FULL;
			int r = aegis_add_app(bid, level);
			if (r != 0) { printf("Error: aegis_add_app failed\n"); return r; }
			printf("Aegis: added %s at level %llu\n", bid, (unsigned long long)level);
			return 0;
		}
		else if (!strcmp(aegisCmd, "remove")) {
			if (argc < 4) { printf("Usage: jbctl aegis remove <bundleId>\n"); return 1; }
			int r = aegis_remove_app(argv[3]);
			if (r != 0) { printf("Error: aegis_remove_app failed\n"); return r; }
			printf("Aegis: removed %s\n", argv[3]);
			return 0;
		}
		else if (!strcmp(aegisCmd, "clear")) {
			int r = aegis_clear_apps();
			if (r != 0) { printf("Error: aegis_clear_apps failed\n"); return r; }
			printf("Aegis: app list cleared\n");
			return 0;
		}
		else if (!strcmp(aegisCmd, "list")) {
			aegis_policy_t policy = { 0 };
			if (aegis_get_policy(&policy) != 0) {
				printf("Error: unable to query aegis policy\n");
				return 1;
			}
			if (policy.appCount == 0) {
				printf("No apps in aegis shield list\n");
			}
			else {
				for (uint32_t i = 0; i < policy.appCount && i < AEGIS_MAX_APPS; i++) {
					printf("%s\t%llu\n", policy.appBundleIds[i], (unsigned long long)policy.appLevels[i]);
				}
			}
			return 0;
		}
		printf("Usage: jbctl aegis <status|enable|disable|set-level|add|remove|list|clear> [args]\n");
		return 1;
	}

	return 0;
}
