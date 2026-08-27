//
//  eufs_state.m
//  Euphoria bootstrapfs — persistent engine state (plist) implementation
//

#import "eufs_state.h"
#import <libjailbreak/jbroot.h>
#import <Foundation/Foundation.h>
#import <stdio.h>
#import <string.h>

#define EUFS_STATE_VERSION 1

const char *eufs_state_path(void)
{
	static char path[512];
	if (path[0] == '\0') {
		snprintf(path, sizeof(path), "%s", JBROOT_PATH("/basebin/.rootful_fs_state.plist"));
	}
	return path;
}

static NSDictionary *role_to_dict(const eufs_role_info *r)
{
	return @{
		@"volume": @(r->volumeName),
		@"device": @(r->device),
		@"bytes": @(r->bytes),
		@"files": @(r->files),
	};
}

int eufs_state_save(const eufs_state *s)
{
	NSMutableDictionary *roles = [NSMutableDictionary dictionary];
	for (int i = 0; i < EUFS_ROLE_COUNT; i++) {
		[roles setObject:role_to_dict(&s->roles[i]) forKey:@(eufs_role_ids[i])];
	}
	NSDictionary *plist = @{
		@"version": @(s->version),
		@"prefix": @(s->prefix),
		@"committed": @(s->committed),
		@"roles": roles,
	};
	NSString *path = [NSString stringWithUTF8String:eufs_state_path()];
	if (![plist writeToFile:path atomically:YES]) {
		fprintf(stderr, "[eufs] state save failed: %s\n", path.UTF8String);
		return -1;
	}
	return 0;
}

int eufs_state_load(eufs_state *s)
{
	if (!s) return -1;
	memset(s, 0, sizeof(*s));
	NSString *path = [NSString stringWithUTF8String:eufs_state_path()];
	NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
	if (![plist isKindOfClass:[NSDictionary class]]) return -1;

	NSNumber *v = plist[@"version"];
	if (![v isKindOfClass:[NSNumber class]] || v.intValue != EUFS_STATE_VERSION) return -1;
	s->version = (uint32_t)v.intValue;

	NSString *prefix = plist[@"prefix"];
	if ([prefix isKindOfClass:[NSString class]]) {
		strlcpy(s->prefix, prefix.UTF8String, sizeof(s->prefix));
	}
	NSNumber *committed = plist[@"committed"];
	s->committed = [committed isKindOfClass:[NSNumber class]] ? committed.intValue : 0;

	NSDictionary *roles = plist[@"roles"];
	if (![roles isKindOfClass:[NSDictionary class]]) return -1;
	for (int i = 0; i < EUFS_ROLE_COUNT; i++) {
		NSDictionary *r = roles[@(eufs_role_ids[i])];
		if (![r isKindOfClass:[NSDictionary class]]) return -1;
		NSString *volume = [r[@"volume"] isKindOfClass:[NSString class]] ? (NSString *)r[@"volume"] : nil;
		NSString *device = [r[@"device"] isKindOfClass:[NSString class]] ? (NSString *)r[@"device"] : nil;
		strlcpy(s->roles[i].volumeName, volume.UTF8String ?: "", sizeof(s->roles[i].volumeName));
		strlcpy(s->roles[i].device, device.UTF8String ?: "", sizeof(s->roles[i].device));
		s->roles[i].bytes = [r[@"bytes"] isKindOfClass:[NSNumber class]] ? ((NSNumber *)r[@"bytes"]).unsignedLongLongValue : 0;
		s->roles[i].files = [r[@"files"] isKindOfClass:[NSNumber class]] ? ((NSNumber *)r[@"files"]).unsignedLongLongValue : 0;
		if (s->roles[i].volumeName[0] == '\0' || s->roles[i].device[0] == '\0') return -1;
	}
	return 0;
}

int eufs_state_delete(void)
{
	return unlink(eufs_state_path()) == 0 ? 0 : -1;
}
