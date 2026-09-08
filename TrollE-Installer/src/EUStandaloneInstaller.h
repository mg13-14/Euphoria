//
//  EUStandaloneInstaller.h
//  TrollE-Installer
//
//  巨魔E 独立安装器——引擎 B/C 门面（从主树 Application/Euphoria/Jailbreak/EUTrollE.h/.m
//  抽取独立化，契约逐条对齐 research/B25；引擎 A【越狱信任缓存】不进独立项目：
//  独立安装器使命=免越狱装出本体，装完后本体脱狱常驻，越狱态重放由主树 Euphoria 承担）。
//  抽离：并行搜索员C，2026-09-03。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const EUStandaloneInstallerErrorDomain;

typedef NS_ENUM(NSInteger, EUStandaloneInstallerErrorCode) {
    EUStandaloneErrorInvalidInput = 1,
    EUStandaloneErrorNotJailbroken = 2,
    EUStandaloneErrorUnzipMissing = 3,
    EUStandaloneErrorUnpackFailed = 4,
    EUStandaloneErrorNoPayload = 5,
    EUStandaloneErrorCopyFailed = 6,
    EUStandaloneErrorPermasignInstallFailed = 7,
    EUStandaloneErrorCDHashFailed = 8,
    EUStandaloneErrorSessionFailed = 9,
    EUStandaloneErrorDomainUnsupported = 10,
};

@interface EUStandaloneInstaller : NSObject

+ (instancetype)sharedInstaller;

/// 【主使命】引擎 B：免越狱一次性漏洞会话（kfd KRW + dmaFail PPL）→ root →
/// CT custom 法装巨魔E 本体（永久签名，重启可用）。CT 域 = 14.0b2–16.7RC + 17.0 全系。
/// 契约（B25）：成功=登记重放表；会话失败=零残留（staging 回滚+漏洞清理）。
/// ⚠️ 实机验证完成前为【实验性】（entitlement 门禁风险，见 README §七-1）。
- (BOOL)installPermasignedAppAtURL:(NSURL *)appURL error:(NSError **)error;

/// 引擎 C：免越狱容器化安装（无漏洞、全版本域、沙盒内）。
- (BOOL)installApplicationContainerizedAtURL:(NSURL *)appURL error:(NSError **)error;

/// 卸载（引擎 C 容器条目：删容器目录+移除重放表条目；
/// 引擎 B 本体=普通 .app，用户桌面长按删除即可，无需本口）
- (BOOL)uninstallContainerizedWithBundleID:(NSString *)bundleID error:(NSError **)error;

/// 重放表内容（沙盒镜像表；条目结构与主树一致：bundleID/path/cdhash/role/engine/container/installedAt）
- (NSArray<NSDictionary<NSString *, id> *> *)installedApplications;

/// 免越狱期沙盒镜像表路径（越狱时主树 EUTrollE migrateSandboxRegistryIfNeeded 幂等合并→L1 升 L3）
+ (NSString *)sandboxRegistryPath;

/// CT 永久域判定（C24 修正版矩阵；含 16.7.x GA 死区 RC 例外）
- (BOOL)deviceInCoreTrustDomain;

@end

NS_ASSUME_NONNULL_END
