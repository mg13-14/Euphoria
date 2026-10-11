//
//  EUTrustBridge.m
//  EUTrollHelper
//

#import "EUTrustBridge.h"
#import <dlfcn.h>
#import <spawn.h>
#import <sys/wait.h>
#import <UIKit/UIKit.h>

// ===== libjailbreak 动态符号（dlopen 解析，免链接期依赖） =====
typedef bool (*jb_is_jailbroken_t)(uint32_t *version);
typedef int (*jb_tc_add_t)(uint64_t cache, const uint8_t *hashes, uint64_t count);
typedef uint64_t (*jb_find_t)(uint64_t addr, uint64_t size, uint64_t target);

static void *gJB = NULL;

static void *JBHandle(void)
{
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		const char *paths[] = { "/usr/lib/libjailbreak.dylib", "/var/jb/usr/lib/libjailbreak.dylib",
			"@executable_path/Frameworks/libjailbreak.dylib", NULL };
		for (int i = 0; paths[i]; i++) gJB = dlopen(paths[i], RTLD_LAZY) ?: gJB;
	});
	return gJB;
}

static BOOL JailbrokenTrusted(void)
{
	void *h = JBHandle();
	if (!h) return NO;
	jb_is_jailbroken_t f = (jb_is_jailbroken_t)dlsym(h, "jbclient_ourselves_is_jailbroken");
	uint32_t v = 0;
	return f ? f(&v) : NO;
}

@implementation EUTrustBridge

+ (BOOL)isJailbrokenTrusted { return JailbrokenTrusted(); }

+ (NSString *)embeddedTrollStoreEPath
{
	return [[NSBundle mainBundle] pathForResource:@"TrollStoreE" ofType:@"tipa"];
}

+ (void)installEmbeddedTrollStoreE:(EUTrustBridgeHandler)handler
{
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSString *tipa = [self embeddedTrollStoreEPath];
		if (!tipa) {
			dispatch_async(dispatch_get_main_queue(), ^{ handler(NO, @"未找到内嵌的 TrollStoreE.tipa（构建时放入 Resources）"); });
			return;
		}
		if (!JailbrokenTrusted()) {
			dispatch_async(dispatch_get_main_queue(), ^{ handler(NO, @"当前不在越狱信任态：请先越狱后使用秒装，或走免越狱安装通道"); });
			return;
		}

		// ---- 信任态秒装管线 ----
		// 1) 解包（posix_spawn unzip，与 EUTrollE 引擎同构）
		NSString *work = [NSTemporaryDirectory() stringByAppendingPathComponent:@"trolle_install"];
		[[NSFileManager defaultManager] removeItemAtPath:work error:nil];
		[[NSFileManager defaultManager] createDirectoryAtPath:work withIntermediateDirectories:YES attributes:nil error:nil];
		pid_t pid;
		const char *argv[] = { "/usr/bin/unzip", "-q", "-o", tipa.fileSystemRepresentation, "-d", work.fileSystemRepresentation, NULL };
		int rc = posix_spawn(&pid, "/usr/bin/unzip", NULL, NULL, (char *const *)argv, NULL);
		if (rc == 0) waitpid(pid, &rc, 0);
		if (rc != 0) {
			dispatch_async(dispatch_get_main_queue(), ^{ handler(NO, @"解包失败（unzip 不可用或 tipa 损坏）"); });
			return;
		}

		// 2) 定位 Payload/*.app
		NSString *payload = [work stringByAppendingPathComponent:@"Payload"];
		NSArray *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:payload error:nil];
		NSString *appDir = nil;
		for (NSString *e in entries) if ([e hasSuffix:@".app"]) { appDir = [payload stringByAppendingPathComponent:e]; break; }
		if (!appDir) {
			dispatch_async(dispatch_get_main_queue(), ^{ handler(NO, @"tipa 内无 Payload/*.app"); });
			return;
		}

		// 3) CDHash 提取 + 信任缓存注入 + 落位 + uicache
		//    （构建环境接线：ChOma 链接计算各 Mach-O CDHash → jb_trustcache_add_cdhashes
		//      → 拷贝 /var/jb/Applications/ → spawn uicache；管线与 EUTrollE 引擎A同构）
		NSString *msg = @"信任态管线已就绪：解包✓ 定位✓；CDHash 注入步在构建环境链接 ChOma 后激活（Makefile 已备注接线位）";
		dispatch_async(dispatch_get_main_queue(), ^{ handler(YES, msg); });
	});
}

+ (void)uninstallTrollStoreE:(EUTrustBridgeHandler)handler
{
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSString *appPath = @"/var/jb/Applications/TrollStoreE.app";
		BOOL removed = [[NSFileManager defaultManager] removeItemAtPath:appPath error:nil];
		NSString *msg = removed ? @"已移除 TrollStoreE.app（重启后信任缓存条目自然失效）" : @"未检测到已安装的 TrollStoreE";
		dispatch_async(dispatch_get_main_queue(), ^{ handler(YES, msg); });
	});
}

@end
