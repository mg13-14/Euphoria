//
//  EnvironmentManager.h
//  Euphoria
//
//  Created by Lars Fröder on 10.01.24.
//

#import <Foundation/Foundation.h>
#import "EUBootstrapper.h"

NS_ASSUME_NONNULL_BEGIN

@interface EUEnvironmentManager : NSObject
{
    EUBootstrapper *_bootstrapper;
    BOOL _isJailbroken;
    NSString *_jailbrokenVersion;
    BOOL _bootstrapNeedsMigration;
}

+ (instancetype)sharedManager;

- (NSString *)appVersion;
- (NSString *)appVersionDisplayString;
- (NSString *)nightlyHash;

- (NSString *)privatePrebootPath;
- (NSString *)activePrebootPath;

- (BOOL)isInstalledThroughTrollStore;
- (BOOL)isJailbroken;
- (BOOL)isJailbrokenWithOtherJailbreak;
- (BOOL)isBootstrapped;
- (BOOL)hasLeftoverBootstrap;
- (BOOL)isRoothideMode;
// R38：屏蔽形态检测（rootful 态=深档 stealth 3 / 普通 roothide=基础档 stealth 1）
// 形态源=jbsettings rootfulUserEnabled（与 isRoothideMode 同源，R37 联动保证
// rootful 开则 roothide 必开）。返回 3=深档（rootful），1=基础档（roothide），0=未启用。
- (NSUInteger)cloakStealthForm;
- (NSString *)jailbrokenVersion;
- (NSString *)systemVersion;

- (BOOL)isSupported;
- (BOOL)isArm64e;
- (BOOL)isSPTM;
- (NSString *)versionSupportString;
- (NSString *)accessibleKernelPath;
- (NSString *)accessibleSPTMPath;
- (NSString *)accessibleTXMPath;
- (void)locateJailbreakRoot;
- (NSError *)ensureJailbreakRootExists;

- (void)setJailbroken:(BOOL)jailbroken withVersion:(NSString *)version;


- (void)runUnsandboxed:(void (^)(void))unsandboxBlock;
- (void)runAsRoot:(void (^)(void))rootBlock;

- (void)respring;
- (void)rebootUserspace;
// 构建修复：.m 已有实现但头文件漏声明，EUSettingsController 调用处报
// "no visible @interface declares the selector"
- (int)spawnJbctlAsRootWithArgs:(NSArray *)args;
- (void)rebuildIconCache;
- (void)refreshJailbreakApps;
- (void)reboot;
- (void)changeMobilePassword:(NSString *)newPassword;
- (NSError*)updateEnvironment;
- (void)updateJailbreakFromTIPA:(NSString *)tipaPath;

- (BOOL)isTweakInjectionEnabled;
- (void)setTweakInjectionEnabled:(BOOL)enabled;
- (BOOL)isIDownloadEnabled;
- (void)setIDownloadEnabled:(BOOL)enabled needsUnsandbox:(BOOL)needsUnsandbox;
- (void)setIDownloadLoaded:(BOOL)loaded needsUnsandbox:(BOOL)needsUnsandbox;
- (BOOL)isFakelibMounted;
- (int)setFakelibMounted:(BOOL)mounted;
- (int)setPrivatePrebootProtected:(BOOL)protected;
- (BOOL)isJailbreakHidden;
- (void)setJailbreakHidden:(BOOL)hidden;

- (BOOL)isPACBypassRequired;
- (BOOL)isPPLBypassRequired;

- (NSError *)prepareBootstrap;
- (NSError *)finalizeBootstrap;
- (NSError *)deleteBootstrap;
- (NSError *)reinstallPackageManagers;
- (NSError *)updateBootLogo;
@end

NS_ASSUME_NONNULL_END
