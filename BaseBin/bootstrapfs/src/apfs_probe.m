//
//  apfs_probe.m
//  Euphoria bootstrapfs — APFS layout probing + volume primitives
//
//  apfs_mount_args_t and the APFS SPI discovery originate from
//  ghh-jb/Dopamine_Rootful BaseBin/bootstrapfs (author: untether).
//

#import "apfs_probe.h"
#import "eufs_common.h"
#import "progress.h"
#import <libjailbreak/libjailbreak.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <IOKit/IOKitLib.h>
#import <dlfcn.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <unistd.h>
#import <errno.h>
#import <sys/mount.h>

// ---- apfs(5) mount arguments (reverse engineered, upstream XNU missing) ----
enum {
        APFS_MOUNT_AS_ROOT = 0,
        APFS_MOUNT_FILESYSTEM,
        APFS_MOUNT_SNAPSHOT,
};

typedef struct apfs_mount_args {
        char *fspec;
        uint64_t apfs_flags;
        uint32_t mount_mode;
        uint32_t pad1;
        uint32_t unk_flags;
        union {
                char snapshot[256];
                struct {
                        char tier1_dev[128];
                        char tier2_dev[128];
                };
        };
        void *im4p_ptr;
        uint32_t im4p_size;
        uint32_t pad2;
        void *im4m_ptr;
        uint32_t im4m_size;
        uint32_t pad3;
        uint32_t cryptex_type;
        int32_t auth_mode;
        uid_t uid;
        gid_t gid;
} __attribute__((packed, aligned(4))) apfs_mount_args_t;

// ---- APFS.framework private SPIs (dlopen'ed, presence reported) ----
static int64_t (*_eufs_APFSVolumeCreate)(char *device, CFMutableDictionaryRef args);
static uint64_t (*_eufs_APFSVolumeDelete)(char *device);

// ---- helpers --------------------------------------------------------------

static NSString *eufs_bsd_name_of(io_object_t service)
{
        CFStringRef dev = IORegistryEntrySearchCFProperty(service, kIOServicePlane, CFSTR("BSD Name"), nil, 0);
        NSString *result = nil;
        if (dev) {
                result = [(__bridge NSString *)dev copy];
                CFRelease(dev);
        }
        return result;
}

// FullName of an AppleAPFSVolume service whose BSD Name equals `bsdName.
static NSString *eufs_fullname_for_bsd(NSString *bsdName)
{
        if (!bsdName.length) return nil;
        CFMutableDictionaryRef matching = IOServiceMatching("AppleAPFSVolume");
        io_iterator_t iter = 0;
        if (IOServiceGetMatchingServices(kIOMasterPortDefault, matching, &iter) != KERN_SUCCESS) return nil;
        NSString *result = nil;
        io_object_t service;
        while ((service = IOIteratorNext(iter)) != 0) {
                NSString *dev = eufs_bsd_name_of(service);
                if ([dev isEqualToString:bsdName]) {
                        CFStringRef name = IORegistryEntrySearchCFProperty(service, kIOServicePlane, CFSTR("FullName"), nil, 0);
                        if (name) {
                                result = [(__bridge NSString *)name copy];
                                CFRelease(name);
                        }
                }
                IOObjectRelease(service);
                if (result) break;
        }
        IOObjectRelease(iter);
        return result;
}

// All AppleAPFSVolume BSD names (for layout reporting / sibling checks).
static NSArray<NSString *> *eufs_all_volume_bsds(void)
{
        CFMutableDictionaryRef matching = IOServiceMatching("AppleAPFSVolume");
        io_iterator_t iter = 0;
        NSMutableArray *out = [NSMutableArray array];
        if (IOServiceGetMatchingServices(kIOMasterPortDefault, matching, &iter) != KERN_SUCCESS) return out;
        io_object_t service;
        while ((service = IOIteratorNext(iter)) != 0) {
                NSString *dev = eufs_bsd_name_of(service);
                if (dev) [out addObject:dev];
                IOObjectRelease(service);
        }
        IOObjectRelease(iter);
        return out;
}

// Strip one trailing "s<digits>" suffix: disk0s1s3 -> disk0s1, disk1s4 -> disk1.
static BOOL eufs_strip_snapshot_suffix(NSString *bsd, NSString **out)
{
        NSRange r = [bsd rangeOfString:@"s" options:NSBackwardsSearch];
        if (r.location == NSNotFound || r.location == 0) return NO;
        NSString *digits = [bsd substringFromIndex:r.location + 1];
        if (!digits.length) return NO;
        for (NSUInteger i = 0; i < digits.length; i++) {
                if (![[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[digits characterAtIndex:i]]) return NO;
        }
        if (out) *out = [bsd substringToIndex:r.location];
        return YES;
}

static BOOL eufs_device_exists(NSString *bsd)
{
        NSString *path = [@"/dev/" stringByAppendingString:bsd];
        return access(path.UTF8String, F_OK) == 0;
}

// BSD name of the PARENT media (the APFS container) of an AppleAPFSVolume,
// via the IOKit registry parent link.  This is the authoritative container
// discovery — no layout assumption involved.
static NSString *eufs_parent_of_volume(NSString *bsdName)
{
        if (!bsdName.length) return nil;
        CFMutableDictionaryRef matching = IOServiceMatching("AppleAPFSVolume");
        io_iterator_t iter = 0;
        if (IOServiceGetMatchingServices(kIOMasterPortDefault, matching, &iter) != KERN_SUCCESS) return nil;
        NSString *result = nil;
        io_object_t service;
        while (!result && (service = IOIteratorNext(iter)) != 0) {
                CFStringRef dev = IORegistryEntrySearchCFProperty(service, kIOServicePlane, CFSTR("BSD Name"), nil, 0);
                if (dev && [(__bridge NSString *)dev isEqualToString:bsdName]) {
                        io_registry_entry_t parent = 0;
                        if (IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS && parent) {
                                CFStringRef pbsd = IORegistryEntrySearchCFProperty(parent, kIOServicePlane, CFSTR("BSD Name"), nil, 0);
                                if (pbsd) {
                                        result = [(__bridge NSString *)pbsd copy];
                                        CFRelease(pbsd);
                                }
                                IOObjectRelease(parent);
                        }
                }
                if (dev) CFRelease(dev);
                IOObjectRelease(service);
        }
        IOObjectRelease(iter);
        return result;
}

// ---- probe ----------------------------------------------------------------

int eufs_probe_layout(eufs_probe_t *out)
{
        if (!out) return -1;
        memset(out, 0, sizeof(*out));

        // Resolve the APFS.framework SPIs up front; absence is not fatal for
        // recover/disable (mount/unmount only) but is fatal for enable/purge.
        void *apfs = dlopen("/System/Library/PrivateFrameworks/APFS.framework/APFS", RTLD_NOW);
        if (apfs) {
                _eufs_APFSVolumeCreate = dlsym(apfs, "APFSVolumeCreate");
                _eufs_APFSVolumeDelete = dlsym(apfs, "APFSVolumeDelete");
        }
        out->spi_volume_create = (_eufs_APFSVolumeCreate != NULL);
        out->spi_volume_delete = (_eufs_APFSVolumeDelete != NULL);
        eufs_emit_probe("spi.volumeCreate", out->spi_volume_create ? "yes" : "no");
        eufs_emit_probe("spi.volumeDelete", out->spi_volume_delete ? "yes" : "no");

        // 1. Where is "/" mounted from?  (the sealed system snapshot)
        struct statfs sfs;
        if (statfs("/", &sfs) != 0) {
                eufs_emit_probe("root.statfs", "failed");
                return -1;
        }
        strlcpy(out->root_mount_from, sfs.f_mntfromname, sizeof(out->root_mount_from));
        eufs_emit_probe("root.mountFrom", out->root_mount_from);

        NSString *snapshotBsd = [[[NSString stringWithUTF8String:out->root_mount_from] lastPathComponent] copy];
        NSString *systemVolume = nil;
        if (!eufs_strip_snapshot_suffix(snapshotBsd, &systemVolume)) {
                // "/" mounted from the live volume itself (unexpected on SSV, but
                // treat it as the system volume directly).
                systemVolume = snapshotBsd;
        }
        strlcpy(out->system_volume, systemVolume.UTF8String, sizeof(out->system_volume));
        eufs_emit_probe("root.systemVolume", out->system_volume);

        // 2. Find the container (parent media) of the system volume.
        //    PRIMARY: IOKit registry parent-walk (volume -> parent media BSD).
        //    Both the 15.x layout (volume disk0s1sN, container disk0s1) and the
        //    16+/macOS layout (volume disk1sN, container disk1) need no
        //    hardcoding this way; the registry tells us the truth.
        NSArray<NSString *> *allVols = eufs_all_volume_bsds();
        eufs_emit_probe("volumes.count", [NSString stringWithFormat:@"%lu", (unsigned long)allVols.count].UTF8String);

        NSString *candidate = nil;
        NSString *method = nil;

        NSString *parentBsd = eufs_parent_of_volume(systemVolume.UTF8String);
        if (parentBsd && eufs_device_exists(parentBsd)) {
                candidate = parentBsd;
                method = @"iokit:parent-walk";
        }

        if (!candidate) {
                NSString *strippedOnce = nil;
                if (eufs_strip_snapshot_suffix(systemVolume, &strippedOnce) && [allVols containsObject:strippedOnce]) {
                        // Parent of the system volume is itself listed as a volume -> the
                        // system volume we found is actually a member volume of a container
                        // device whose BSD name is the stripped form.
                        candidate = strippedOnce;
                        method = @"iokit:parent-of-system-volume";
                }
        }
        if (!candidate) {
                // Last-resort candidates by known layouts, verified against IOKit.
                for (NSString *guess in @[@"disk0s1", @"disk1", @"disk0s2"]) {
                        NSString *volPrefix = [guess stringByAppendingString:@"s"];
                        BOOL isParent = NO;
                        for (NSString *v in allVols) {
                                if ([v hasPrefix:volPrefix] && ![v isEqualToString:guess]) { isParent = YES; break; }
                        }
                        if (isParent && eufs_device_exists(guess)) {
                                candidate = guess;
                                method = [NSString stringWithFormat:@"iokit:layout-guess:%@", guess];
                                break;
                        }
                }
        }
        if (!candidate || !eufs_device_exists(candidate)) {
                eufs_emit_probe("container", "unresolved");
                return -1;
        }

        strlcpy(out->container, candidate.UTF8String, sizeof(out->container));
        strlcpy(out->container_method, method.UTF8String ?: "unknown", sizeof(out->container_method));
        eufs_emit_probe("container", out->container);
        eufs_emit_probe("container.method", out->container_method);
        return 0;
}

// ---- volume primitives ----------------------------------------------------

char *eufs_volume_device(const char *volumeName)
{
        NSString *name = @(volumeName ?: "");
        NSArray *allVols = eufs_all_volume_bsds();
        const char *found = NULL;
        for (NSString *v in allVols) {
                NSString *fn = eufs_fullname_for_bsd(v);
                if ([fn isEqualToString:name]) {
                        found = v.UTF8String;
                        break;
                }
        }
        if (!found) return NULL;
        char *dev = malloc(64);
        if (!dev) return NULL;
        snprintf(dev, 64, "/dev/%s", found);
        return dev;
}

int eufs_mount_volume(const char *mntPoint, const char *device, int flags)
{
        apfs_mount_args_t args = {
                .fspec = (char *)device,
                .apfs_flags = 0,
                .mount_mode = APFS_MOUNT_FILESYSTEM, // live FS, never a snapshot
                .snapshot = { "" },
        };

        uint64_t credBackup = 0;
        int ret;
        jbclient_root_steal_ucred(0, &credBackup);
        ret = mount("apfs", mntPoint, flags, &args);
        jbclient_root_steal_ucred(credBackup, NULL);
        return ret;
}

int eufs_unmount_path(const char *mntPoint)
{
        uint64_t credBackup = 0;
        int ret;
        jbclient_root_steal_ucred(0, &credBackup);
        ret = unmount(mntPoint, MNT_FORCE);
        jbclient_root_steal_ucred(credBackup, NULL);
        return ret;
}

int eufs_create_volume(const char *containerDevice, const char *volumeName)
{
        if (!_eufs_APFSVolumeCreate) return -1;

        NSDictionary *createDict = @{ @"com.apple.apfs.volume.name": @(volumeName) };
        CFMutableDictionaryRef mut = CFDictionaryCreateMutableCopy(NULL, 0, (__bridge CFDictionaryRef)createDict);

        uint64_t credBackup = 0;
        jbclient_root_steal_ucred(0, &credBackup);
        int64_t r = _eufs_APFSVolumeCreate((char *)containerDevice, mut);
        jbclient_root_steal_ucred(credBackup, NULL);
        CFRelease(mut);
        return (r == 0) ? 0 : -1;
}

int eufs_destroy_volume(const char *deviceNode)
{
        if (!_eufs_APFSVolumeDelete) return -1;
        // Accept both "disk0s1s9" and "/dev/disk0s1s9".
        const char *bsd = deviceNode;
        if (strncmp(bsd, "/dev/", 5) == 0) bsd += 5;
        char node[64];
        snprintf(node, sizeof(node), "/dev/%s", bsd);

        uint64_t credBackup = 0;
        jbclient_root_steal_ucred(0, &credBackup);
        int64_t r = _eufs_APFSVolumeDelete((char *)bsd);
        jbclient_root_steal_ucred(credBackup, NULL);
        (void)node;
        return (r == 0) ? 0 : -1;
}

int eufs_wait_for_device(const char *deviceNode, int timeoutMs)
{
        const char *bsd = deviceNode;
        if (strncmp(bsd, "/dev/", 5) == 0) bsd += 5;
        char path[64];
        snprintf(path, sizeof(path), "/dev/%s", bsd);
        for (int waited = 0; waited < timeoutMs; waited += 100) {
                if (access(path, F_OK) == 0) return 0;
                usleep(100 * 1000);
        }
        return access(path, F_OK) == 0 ? 0 : -1;
}
