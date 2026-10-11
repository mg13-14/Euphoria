//
//  EUTrustBridge.h
//  EUTrollHelper（巨魔E安装器 · TrollHelper 2.1.1 改进版）
//
//  越狱信任态秒装桥：dlopen 直连 libjailbreak（无需链接期依赖）
//  机制：检测越狱态 → 信任缓存注入（与系统二进制同权）→ 秒装巨魔E
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^EUTrustBridgeHandler)(BOOL installed, NSString *_Nullable message);

@interface EUTrustBridge : NSObject

/// 当前是否处于越狱信任态（dlopen libjailbreak → jbclient 检测）
+ (BOOL)isJailbrokenTrusted;

/// 信任态秒装：安装 bundle 内嵌入的 TrollStoreE.tipa
/// （解包 → ChOma 取 CDHash → jb_trustcache_add_cdhashes → 落位 /var/jb/Applications → uicache）
+ (void)installEmbeddedTrollStoreE:(EUTrustBridgeHandler)handler;

/// 卸载巨魔E（移除 .app + 重放表条目）
+ (void)uninstallTrollStoreE:(EUTrustBridgeHandler)handler;

@end

NS_ASSUME_NONNULL_END
