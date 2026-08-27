//
//  progress.m
//  Euphoria bootstrapfs — stage-event emitter implementation
//

#import "progress.h"
#import <Foundation/Foundation.h>
#import <stdio.h>
#import <string.h>
#import <unistd.h>
#import <errno.h>

static int gProgressFd = STDOUT_FILENO;

void eufs_progress_set_fd(int fd) { gProgressFd = fd; }
int  eufs_progress_get_fd(void)   { return gProgressFd; }

// Escape a string for embedding inside a JSON string literal.
static NSString *eufs_json_escape(NSString *s)
{
	if (!s) return @"";
	NSMutableString *out = [NSMutableString stringWithString:s];
	[out replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, out.length)];
	[out replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:0 range:NSMakeRange(0, out.length)];
	[out replaceOccurrencesOfString:@"\n" withString:@"\\n" options:0 range:NSMakeRange(0, out.length)];
	[out replaceOccurrencesOfString:@"\r" withString:@"\\r" options:0 range:NSMakeRange(0, out.length)];
	[out replaceOccurrencesOfString:@"\t" withString:@"\\t" options:0 range:NSMakeRange(0, out.length)];
	return out;
}

static void eufs_emit_raw(NSString *json)
{
	NSString *line = [json stringByAppendingString:@"\n"];
	const char *utf8 = line.UTF8String;
	size_t len = strlen(utf8);
	size_t done = 0;
	// Whole-line-or-nothing write with EINTR retry; a short write on a pipe
	// would interleave events, so loop.
	while (done < len) {
		ssize_t w = write(gProgressFd, utf8 + done, len - done);
		if (w < 0) {
			if (errno == EINTR) continue;
			return; // progress channel is best-effort; never abort the action
		}
		done += (size_t)w;
	}
}

void eufs_emit_probe(const char *key, const char *value)
{
	eufs_emit_raw([NSString stringWithFormat:
		@"{\"v\":1,\"ev\":\"probe\",\"key\":\"%@\",\"value\":\"%@\"}",
		eufs_json_escape(@(key ?: "")), eufs_json_escape(@(value ?: ""))]);
}

void eufs_emit_stage(const char *stage, const char *dir, int index, int total)
{
	eufs_emit_raw([NSString stringWithFormat:
		@"{\"v\":1,\"ev\":\"stage\",\"stage\":\"%@\",\"dir\":\"%@\",\"index\":%d,\"total\":%d}",
		eufs_json_escape(@(stage ?: "")), eufs_json_escape(@(dir ?: "")), index, total]);
}

void eufs_emit_copy(const char *dir, uint64_t bytes, uint64_t bytesTotal,
                    uint64_t files, double pct, double pctGlobal)
{
	eufs_emit_raw([NSString stringWithFormat:
		@"{\"v\":1,\"ev\":\"copy\",\"dir\":\"%@\",\"bytes\":%llu,\"bytesTotal\":%llu,\"files\":%llu,\"pct\":%.1f,\"pctGlobal\":%.1f}",
		eufs_json_escape(@(dir ?: "")),
		(unsigned long long)bytes, (unsigned long long)bytesTotal,
		(unsigned long long)files, pct, pctGlobal]);
}

void eufs_emit_done(const char *mode, double elapsedSeconds)
{
	eufs_emit_raw([NSString stringWithFormat:
		@"{\"v\":1,\"ev\":\"done\",\"mode\":\"%@\",\"elapsed\":%.1f}",
		eufs_json_escape(@(mode ?: "")), elapsedSeconds]);
}

void eufs_emit_error(const char *stage, const char *dir, const char *path,
                     int err, const char *msg, bool fatal)
{
	eufs_emit_raw([NSString stringWithFormat:
		@"{\"v\":1,\"ev\":\"error\",\"stage\":\"%@\",\"dir\":\"%@\",\"path\":\"%@\",\"errno\":%d,\"msg\":\"%@\",\"fatal\":%@}",
		eufs_json_escape(@(stage ?: "")), eufs_json_escape(@(dir ?: "")),
		eufs_json_escape(@(path ?: "")), err, eufs_json_escape(@(msg ?: "")),
		fatal ? @"true" : @"false"]);
}

void eufs_emit_rollback(const char *reason, int unmounted, int destroyed)
{
	eufs_emit_raw([NSString stringWithFormat:
		@"{\"v\":1,\"ev\":\"rollback\",\"reason\":\"%@\",\"unmounted\":%d,\"destroyed\":%d}",
		eufs_json_escape(@(reason ?: "")), unmounted, destroyed]);
}
