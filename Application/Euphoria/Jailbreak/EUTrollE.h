//
//  EUTrollE.h
//  Euphoria
//
//  巨魔E（TrollStore E）核心 —— R19 / B23 Tier A（V0.9.0 越狱态）
//  Created by 并行搜索员B on 27.08.2026.
//
//  机制（B23 信任缓存路线）：
//   - 安装：解包 IPA → ChOma 取主二进制 CDHash → jb_trustcache_add_cdhashes
//     注入运行时信任缓存（条目与系统二进制同权）→ 拷入 /var/jb/Applications → uicache
//   - 持久：条目落 /var/jb/var/db/euphoria/trolle.plist，每次越狱幂等重放
//   - 边界（如实）：重启未越狱期间不可用 —— "不越狱可用"=Tier B 攻坚目标
//     （B24：XNU-12377 启动期 cryptex TC 三道锁实证，攻击面=km daemon/TXM/amfid）
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const EUTrollEErrorDomain;

typedef NS_ENUM(NSInteger, EUTrollEErrorCode) {
    EUTrollEErrorCodeInvalidInput = 1,
    EUTrollEErrorCodeNotJailbroken = 2,
    EUTrollEErrorCodeUnzipMissing = 3,
    EUTrollEErrorCodeUnpackFailed = 4,
    EUTrollEErrorCodeNoPayload = 5,
    EUTrollEErrorCodeUnsignedBinary = 6,
    EUTrollEErrorCodeCDHashFailed = 7,
    EUTrollEErrorCodeTrustCacheFailed = 8,
    EUTrollEErrorCodeCopyFailed = 9,
    EUTrollEErrorCodeUICacheFailed = 10,
    EUTrollEErrorCodeEngineBUnavailable = 11,
    // Engine B 专用（B25 契约：会话失败建议扩展 code 12+，C 实现补充）
    EUTrollEErrorCodeSessionFailed = 12,       ///< 一次性漏洞会话失败（kfd/dmaFail 拿 KRW/root 失败；零残留）
    EUTrollEErrorCodeDomainUnsupported = 13,   ///< 当前系统在免越狱永久域之外（C24 矩阵；会话档/PC 辅助档提示）
    EUTrollEErrorCodePermasignInstallFailed = 14, ///< CT 永久签名安装失败（installd/MobileInstallation 路径）
};

/// 安装模式（C23 双模式架构 + B26 分层可用）
typedef NS_ENUM(NSInteger, EUTrollEInstallMode) {
    EUTrollEInstallModeAuto = 0,            ///< 按越狱态自动选择（越狱→A，未越狱→B）
    EUTrollEInstallModeJailbroken = 1,      ///< 引擎A：越狱态信任缓存秒装（已实现）
    EUTrollEInstallModeJailbreakFree = 2,   ///< 引擎B：免越狱一次性会话（kfd+dmaFail，V0.9.1 目标）
    EUTrollEInstallModeContainerized = 3,   ///< 引擎C：免越狱容器模式（L1 基线，B26；无漏洞全版本可用）
};

/// 巨魔E 安装引擎契约（Engine A=trustcache / Engine B=免越狱会话 / Engine C=容器模式）
/// Engine B 实现者（C）须知：
///  - 一次性会话内拿到 root/KRW 后，按 C23 语义完成"装本体+Persistence Helper"；
///  - helper 常驻后负责 respring/图标缓存重载后的签名态恢复；
///  - 安装成功的应用仍须登记进重放表（registryPath），保持与 Engine A 同一张表，
///    引擎 A 在后续越狱时幂等重放信任缓存，两种来源的应用互不冲突。
/// Engine C 实现者须知（B26 L1 基线，容器模式）：
///  - 无漏洞、全版本域；app 以宿主证书代签在容器内启动（JIT-Less），无 entitlements；
///  - 参考对象 LiveContainer 为 GPL-3.0：只做机制借鉴与协议方式重实现，禁止搬运代码；
///  - 需向 UI 暴露"签名健康度"（宿主证书有效期）；容器内 app 同样登记进重放表，
///    后续越狱时由 Engine A 顺带升级为满血形态（L1→L3 升级路径）。
///
/// 【R32 版本域契约（用户 11:42:13"越狱何谓越狱都必须原有巨魔的范围，必须支持"
///   + 11:42:25/52 双态澄清 + 11:44:59 精确域定案
///   + 11:47:32 build 级勘误"16.6.1到17.0中间有很多个本来支持巨魔的"）】
/// 用户定案原文："未越狱的巨魔E范围ios14.0到ios18.7.1,A12到A13"
/// → 未越狱（Engine B/C）：iOS 14.0 ~ 18.7.1，设备 A12 ~ A13，三档按 build 精确分层：
///   ① 永久档（CT 存活，原版巨魔同域，不得降级进会话档）：
///      14.0b2~16.6.1 ＋ 16.7 b1~b6/16.7RC（20H18）＋ 17.0 各 build（第二 CT 段）
///      ——中间版本（16.7b/RC、17.0 全系）原本巨魔就支持，巨魔E 全收录保持永久档；
///   ② 会话/容器档：16.7.x 正式版（CT 修复首发 20H19 死区）＋ 17.0.1~18.7.1
///      （DarkSword 一次性会话可装；重启持久化=非 CT 向量攻坚线未定，
///       re-arm 依赖正常签名渠道保活=B26 L2；L1 容器兜底）；
///   ③ PC 辅助子模式：16.7b/RC/17.0 设备端 kfd 装法死（arm64e 16.6.2+）
///      → 该档免越狱安装走 PC 备份注入（TrollRestore 先例，原版巨魔同款路径）。
/// → 越狱态（Engine A）：越狱链可及域（15.0~18.7.6 + 26.0~26.3.x，R29 快胜线已拉宽），
///   "越狱到哪巨魔E 跟到哪"，**零辅助安装**（用户 11:50 定案：越狱态一律安装器直装，
///   不需要 PC/辅助渠道——信任缓存注入链已闭环）。
/// 两态并集对外呈现；UI 按"永久/会话"双态徽标（会话态带重激活按钮，不标永久）；
/// 硬边界：17.0.1+ 永久档无公开第三 CT bug（TrollStore 2.1.1@2026-04 仍 ≤17.0 佐证）。
@protocol EUTrollEEngine <NSObject>

- (BOOL)installApplicationAtURL:(NSURL *)appURL
                           mode:(EUTrollEInstallMode)mode
                          error:(NSError *_Nullable *_Nullable)error;

@end

@interface EUTrollE : NSObject

+ (instancetype)sharedInstance;

/// 永久安装一个应用（.ipa 或已解包 .app 目录）。
/// 三引擎门面（C23+B25+B26）：越狱态走引擎A（信任缓存秒装，零辅助）；未越狱走
/// 引擎B（免越狱一次性会话：CT 域设备端 kfd 装本体+helper，V0.9.1 实机验证）
/// 或引擎C（容器模式 L1 基线：全版本域，宿主代签，JIT-Less）。mode=Auto 按越狱态选择。
- (BOOL)installApplicationAtURL:(NSURL *)appURL
                           mode:(EUTrollEInstallMode)mode
                          error:(NSError *_Nullable *_Nullable)error;

/// 兼容入口（= mode Auto）。
- (BOOL)installApplicationAtURL:(NSURL *)appURL
                          error:(NSError *_Nullable *_Nullable)error;

/// 卸载巨魔E 安装的应用（删除 .app + 移除重放表条目；TC 条目随重启自然失效）。
- (BOOL)uninstallApplicationWithBundleID:(NSString *)bundleID
                                   error:(NSError *_Nullable *_Nullable)error;

/// 已安装的巨魔E 应用清单（重放表内容）。
- (NSArray<NSDictionary<NSString *, id> *> *)installedApplications;

/// 每次越狱时由 EUBootstrapper 调用：重放全部 CDHash 到运行时信任缓存（幂等）。
+ (void)replayTrustCacheEntries;

/// 巨魔E 重放表路径（双模：越狱态=/var/jb/var/db/euphoria/trolle.plist 主表；
/// 免越狱态=沙盒镜像表 Documents/EUTrollE/registry.plist，条目结构一致）。
+ (NSString *)registryPath;

/// 免越狱期沙盒镜像表路径（引擎B 首装/引擎C 全程写入；越狱时被迁移合并）。
+ (NSString *)sandboxRegistryPath;

/// 越狱引导时调用（replayTrustCacheEntries 前置）：把免越狱期写入沙盒镜像表的
/// 条目按 path 去重合并进主表并清空镜像表（幂等）——L1/L2→L3 满血升级闭环。
+ (void)migrateSandboxRegistryIfNeeded;

@end

NS_ASSUME_NONNULL_END
