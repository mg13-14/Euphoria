//
//  EUStandaloneConfig.h
//  TrollE-Installer
//
//  独立安装器配置层——替代主树 JBROOT_PATH 等宏（解耦点 #4）。
//  抽离：并行搜索员C，2026-09-03（源：Euphoria 主树 TrollE-Installer 独立化任务）
//

#ifndef EUStandaloneConfig_h
#define EUStandaloneConfig_h

#import <Foundation/Foundation.h>

/// 独立安装器 Bundle ID（Info.plist 与 DEBIAN/control 保持一致）
FOUNDATION_EXPORT NSString *const EUStandaloneBundleID;

/// URL scheme（与主树 EUTrollE handoff 语义对齐；euphoria-trolle://launch?id=<uuid>）
FOUNDATION_EXPORT NSString *const EUStandaloneURLScheme;

/// 重放表·沙盒镜像表路径（独立安装器免越狱态的唯一注册表；条目结构与主树一致：
/// bundleID/path/cdhash/role/engine/container/installedAt——保持 L1→L3 升级闭环兼容，
/// 越狱时由 Euphoria 主树 EUTrollE migrateSandboxRegistryIfNeeded 幂等合并）
FOUNDATION_EXPORT NSString *EUStandaloneSandboxRegistryPath(void);

/// 越狱态主表路径（只读兼容：探测到 /var/jb 在位时读取；独立安装器永不写入主表）
FOUNDATION_EXPORT NSString *EUStandaloneMainRegistryPath(void);

/// JBROOT_PATH 的独立版（解耦点 #4）：
///   免越狱态 = 恒空前缀（无越狱根，引擎 A 不进独立项目）
///   越狱态兼容 = /var/jb 探测在位时取越狱根（只读用途，如读取主表判断本体是否已装）
#define EUStandaloneJBROOT(x) ([EUStandaloneJailbreakRootPath() isEqualToString:@""] \
    ? (x) \
    : [NSString stringWithFormat:@"%@%@", EUStandaloneJailbreakRootPath(), (x)])

/// 运行时越狱根探测（空串=免越狱；"/var/jb"=越狱态）
FOUNDATION_EXPORT NSString *EUStandaloneJailbreakRootPath(void);

#endif /* EUStandaloneConfig_h */
